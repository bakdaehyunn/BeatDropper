import {
  ChangeEvent,
  DragEvent,
  useEffect,
  useMemo,
  useRef,
  useState
} from 'react';
import { estimateAdaptiveDecodeTimeoutMs } from '../shared/decodeTimeout';
import {
  buildMixPlanComparisonExportEnvelope,
  buildMixPlanComparisonRows,
  MixPlanComparisonExportEnvelope,
  parseMixPlanComparisonExportJson
} from '../shared/mixPlanComparison';
import { MixPlan } from '../shared/mixPlan';
import {
  MIX_PLAN_PLANNER_PRESET_DESCRIPTIONS,
  MixPlanExportEnvelope,
  MixPlanPlannerPreset,
  buildMixPlanExportEnvelope,
  buildMixPlanExportMetadata,
  parseMixPlanExportContextFromUnknown,
  parseMixPlanExportJson
} from '../shared/mixPlanExport';
import { DEFAULT_SETTINGS, sanitizeSettings } from '../shared/settings';
import { PlayerEvent, PlayerSettings, Track, TrackLoadMode } from '../shared/types';
import { AudioEngine } from './player';
import {
  applyTrackLoadResult,
  formatTrackLoadError,
  skippedMessagesToEvents
} from './player/trackImportFlow';

const MAX_LOG_ITEMS = 100;

const formatDuration = (sec: number): string => {
  const safeSec = Math.max(0, Math.floor(sec));
  const min = Math.floor(safeSec / 60);
  const rem = safeSec % 60;
  return `${min}:${String(rem).padStart(2, '0')}`;
};

const formatEventTime = (value: number): string => value.toFixed(2);
const METER_BAR_COUNT = 18;
const PREVIEW_TRACK_DURATION_SEC = 10;
const PREVIEW_TRACK_SIZE_BYTES = 8 * 1024 * 1024;
const START_DECODE_BASE_TIMEOUT_MS = 2500;
const PREDECODE_BASE_TIMEOUT_MS = 3000;
const TRANSITION_DECODE_BASE_TIMEOUT_MS = 1200;
const MAX_IMPORTED_MIX_PLAN_ARTIFACTS = 5;
const LOCAL_COMPARE_TARGET_ID = '__latest_local__';
type TransportIconName = 'play' | 'pause' | 'previous' | 'next';

interface ImportedMixPlanArtifact {
  id: string;
  filename: string;
  importedAt: string;
  envelope: MixPlanExportEnvelope;
}

interface ImportedMixPlanComparisonArtifact {
  id: string;
  filename: string;
  importedAt: string;
  envelope: MixPlanComparisonExportEnvelope;
}

interface MixPlanCompareTargetOption {
  id: string;
  label: string;
  mixPlan: MixPlan;
  summary: string;
}

interface DecodeTimeoutPreset {
  id: 'fast' | 'balanced' | 'stable';
  label: string;
  durationWeightMs: number;
  sizeWeightMs: number;
}

const DECODE_TIMEOUT_PRESETS: DecodeTimeoutPreset[] = [
  {
    id: 'fast',
    label: '고성능',
    durationWeightMs: 10,
    sizeWeightMs: 80
  },
  {
    id: 'balanced',
    label: '균형',
    durationWeightMs: 20,
    sizeWeightMs: 200
  },
  {
    id: 'stable',
    label: '안정',
    durationWeightMs: 36,
    sizeWeightMs: 480
  }
];

const formatDecodePreviewSec = (timeoutMs: number): string => {
  return `${(timeoutMs / 1000).toFixed(1)}s`;
};

const formatPlannerArgsDraft = (args: string[]): string => args.join('\n');
const prettyJson = (value: unknown): string => {
  if (value === null || value === undefined) {
    return 'null';
  }

  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const asFiniteNumber = (value: unknown): number | null => {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
};

const asString = (value: unknown): string | null => {
  return typeof value === 'string' && value.length > 0 ? value : null;
};

const asPlannerResponseSchemaVersion = (value: unknown): number | null => {
  return isRecord(value) ? asFiniteNumber(value.schemaVersion) : null;
};

const formatTempoSyncRate = (value: unknown): string | null => {
  const rate = asFiniteNumber(value);
  return rate === null ? null : `${rate.toFixed(3)}x`;
};

const formatSignedDeltaSec = (value: number): string => {
  const sign = value > 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}s`;
};

const formatComparisonDelta = (left: string, right: string): string => {
  return left === right ? 'same' : `${right} -> ${left}`;
};

const formatPlannerEventDetails = (event: PlayerEvent): string | null => {
  const details = event.details ?? {};

  if (event.type === 'mix_plan_applied') {
    const startAt = asFiniteNumber(details.transitionStartAt);
    const endAt = asFiniteNumber(details.transitionEndAt);
    const offset = asFiniteNumber(details.nextTrackStartOffsetSec);
    const summary = asString(details.reasoningSummary);
    const parts = [
      startAt !== null && endAt !== null ? `window ${formatDuration(startAt)} -> ${formatDuration(endAt)}` : null,
      offset !== null ? `offset ${formatDuration(offset)}` : null,
      summary
    ].filter(Boolean);
    return parts.length > 0 ? parts.join(' · ') : null;
  }

  if (event.type === 'mix_plan_fallback') {
    return asString(details.reason) ?? null;
  }

  if (event.type === 'transition_started') {
    const source = asString(details.source);
    const offset = asFiniteNumber(details.nextTrackStartOffsetSec);
    return [
      source ? `source ${source}` : null,
      offset !== null ? `offset ${formatDuration(offset)}` : null
    ]
      .filter(Boolean)
      .join(' · ') || null;
  }

  if (event.type === 'tempo_sync_applied') {
    const rate = formatTempoSyncRate(details.targetRate);
    return rate ? `target ${rate}` : null;
  }

  if (event.type === 'tempo_sync_skipped') {
    return asString(details.reason) ?? null;
  }

  return null;
};

const TransportIcon = ({ name }: { name: TransportIconName }): JSX.Element => {
  if (name === 'play') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M8 5.5v13l10-6.5-10-6.5Z" />
      </svg>
    );
  }

  if (name === 'pause') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <rect x="6.5" y="5.5" width="4" height="13" rx="1.2" />
        <rect x="13.5" y="5.5" width="4" height="13" rx="1.2" />
      </svg>
    );
  }

  if (name === 'previous') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <rect x="5.5" y="6" width="2.8" height="12" rx="0.8" />
        <path d="M18.2 6.2v11.6l-8.6-5.8 8.6-5.8Z" />
      </svg>
    );
  }

  if (name === 'next') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <rect x="15.7" y="6" width="2.8" height="12" rx="0.8" />
        <path d="M5.8 6.2v11.6l8.6-5.8-8.6-5.8Z" />
      </svg>
    );
  }

  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M8 5.5v13l10-6.5-10-6.5Z" />
    </svg>
  );
};

export const App = (): JSX.Element => {
  const [tracks, setTracks] = useState<Track[]>([]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [settings, setSettings] = useState<PlayerSettings>(DEFAULT_SETTINGS);
  const [skippedItems, setSkippedItems] = useState<string[]>([]);
  const [events, setEvents] = useState<PlayerEvent[]>([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [currentTitle, setCurrentTitle] = useState('Idle');
  const [currentTrackIndex, setCurrentTrackIndex] = useState<number | null>(null);
  const [currentTrackDurationSec, setCurrentTrackDurationSec] = useState(0);
  const [elapsedSec, setElapsedSec] = useState(0);
  const [playbackStartedAtMs, setPlaybackStartedAtMs] = useState<number | null>(null);
  const [isUtilityOpen, setIsUtilityOpen] = useState(false);
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);
  const [rmsLevel, setRmsLevel] = useState(0);
  const [resolvedBpmByTrack, setResolvedBpmByTrack] = useState<Record<string, number>>({});
  const [lastImportMode, setLastImportMode] = useState<TrackLoadMode | null>(null);
  const [lastImportAt, setLastImportAt] = useState<number | null>(null);
  const [isTrackLoadPending, setIsTrackLoadPending] = useState(false);
  const [trackLoadNotice, setTrackLoadNotice] = useState<string | null>(null);
  const [plannerCommandDraft, setPlannerCommandDraft] = useState('');
  const [plannerArgsDraft, setPlannerArgsDraft] = useState('');
  const [plannerTimeoutDraft, setPlannerTimeoutDraft] = useState(
    String(DEFAULT_SETTINGS.plannerTimeoutMs)
  );
  const [plannerDebugCopyNotice, setPlannerDebugCopyNotice] = useState<string | null>(null);
  const [importedMixPlanArtifacts, setImportedMixPlanArtifacts] = useState<
    ImportedMixPlanArtifact[]
  >([]);
  const [importedMixPlanComparisonArtifacts, setImportedMixPlanComparisonArtifacts] = useState<
    ImportedMixPlanComparisonArtifact[]
  >([]);
  const [selectedImportedMixPlanArtifactId, setSelectedImportedMixPlanArtifactId] =
    useState<string | null>(null);
  const [selectedImportedMixPlanComparisonArtifactId, setSelectedImportedMixPlanComparisonArtifactId] =
    useState<string | null>(null);
  const [selectedMixPlanCompareTargetId, setSelectedMixPlanCompareTargetId] =
    useState<string>(LOCAL_COMPARE_TARGET_ID);

  const tracksRef = useRef<Track[]>([]);
  const plannerImportInputRef = useRef<HTMLInputElement | null>(null);
  const comparisonImportInputRef = useRef<HTMLInputElement | null>(null);
  const audioEngine = useMemo(
    () =>
      new AudioEngine({
        readTrackBuffer: window.dropperApi.readTrackBufferById,
        requestMixPlan: window.dropperApi.requestMixPlan,
        settings: DEFAULT_SETTINGS
      }),
    []
  );

  useEffect(() => {
    tracksRef.current = tracks;
    audioEngine.loadTracks(tracks);
  }, [audioEngine, tracks]);

  useEffect(() => {
    const unsubscribe = audioEngine.onEvent((event) => {
      setEvents((previous) => [event, ...previous].slice(0, MAX_LOG_ITEMS));

      if (event.type === 'track_started') {
        const trackId = event.details?.trackId;
        const trackIndex = event.details?.index;

        if (typeof trackId === 'string') {
          const track = tracksRef.current.find((item) => item.id === trackId);
          if (track) {
            setCurrentTitle(track.title);
            setCurrentTrackDurationSec(track.durationSec);
            setElapsedSec(0);
            setPlaybackStartedAtMs(Date.now());
            setIsPaused(false);
          }
        }

        if (typeof trackIndex === 'number') {
          setCurrentTrackIndex(trackIndex);
        } else if (typeof trackId === 'string') {
          const index = tracksRef.current.findIndex((item) => item.id === trackId);
          if (index >= 0) {
            setCurrentTrackIndex(index);
          }
        }
      }

      if (event.type === 'playback_stopped') {
        setIsPlaying(false);
        setIsPaused(false);
        setCurrentTitle('Idle');
        setCurrentTrackIndex(null);
        setCurrentTrackDurationSec(0);
        setElapsedSec(0);
        setPlaybackStartedAtMs(null);
      }

      if (event.type === 'bpm_resolved') {
        const trackId = event.details?.trackId;
        const bpm = event.details?.bpm;
        if (typeof trackId === 'string' && typeof bpm === 'number' && Number.isFinite(bpm)) {
          setResolvedBpmByTrack((previous) => ({
            ...previous,
            [trackId]: bpm
          }));
        }
      }

      if (event.type === 'playback_paused') {
        setIsPlaying(false);
        setIsPaused(true);
      }

      if (event.type === 'playback_resumed') {
        setIsPlaying(true);
        setIsPaused(false);
      }
    });

    return () => {
      unsubscribe();
      void audioEngine.destroy();
    };
  }, [audioEngine]);

  useEffect(() => {
    let mounted = true;
    void window.dropperApi
      .getSettings()
      .then((loaded) => {
        if (!mounted) {
          return;
        }
        const next = sanitizeSettings(loaded);
        setSettings(next);
        audioEngine.setSettings(next);
      })
      .catch(() => undefined);

    return () => {
      mounted = false;
    };
  }, [audioEngine]);

  useEffect(() => {
    setPlannerCommandDraft(settings.plannerCommand);
    setPlannerArgsDraft(formatPlannerArgsDraft(settings.plannerArgs));
    setPlannerTimeoutDraft(String(settings.plannerTimeoutMs));
  }, [
    settings.plannerArgs,
    settings.plannerCommand,
    settings.plannerTimeoutMs
  ]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') {
        setIsUtilityOpen(false);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  useEffect(() => {
    if (!isPlaying || !playbackStartedAtMs || currentTrackDurationSec <= 0) {
      return;
    }

    const handle = window.setInterval(() => {
      const nextElapsed = Math.min(
        currentTrackDurationSec,
        (Date.now() - playbackStartedAtMs) / 1000
      );
      setElapsedSec(nextElapsed);
    }, 250);

    return () => window.clearInterval(handle);
  }, [currentTrackDurationSec, isPlaying, playbackStartedAtMs]);

  useEffect(() => {
    if (!isPlaying) {
      setRmsLevel(0);
      return;
    }

    const handle = window.setInterval(() => {
      setRmsLevel(audioEngine.getOutputLevel());
    }, 60);
    return () => window.clearInterval(handle);
  }, [audioEngine, isPlaying]);

  const persistSettings = async (nextCandidate: Partial<PlayerSettings>) => {
    const nextLocal = sanitizeSettings({ ...settings, ...nextCandidate });
    setSettings(nextLocal);
    audioEngine.setSettings(nextLocal);

    try {
      const saved = await window.dropperApi.saveSettings(nextLocal);
      const nextSaved = sanitizeSettings(saved);
      setSettings(nextSaved);
      audioEngine.setSettings(nextSaved);
    } catch {
      const errorEvent: PlayerEvent = {
        type: 'error',
        at: 0,
        message: 'Failed to persist settings'
      };
      setEvents((previous) => [errorEvent, ...previous].slice(0, MAX_LOG_ITEMS));
    }
  };

  const pushLocalErrorEvent = (message: string): void => {
    const errorEvent: PlayerEvent = {
      type: 'error',
      at: 0,
      message
    };
    setEvents((previous) => [errorEvent, ...previous].slice(0, MAX_LOG_ITEMS));
  };

  const flashPlannerDebugNotice = (message: string): void => {
    setPlannerDebugCopyNotice(message);
    window.setTimeout(() => {
      setPlannerDebugCopyNotice((previous) => (previous === message ? null : previous));
    }, 1800);
  };

  const copyPlannerDebug = async (label: string, payload: string): Promise<void> => {
    try {
      await navigator.clipboard.writeText(payload);
      flashPlannerDebugNotice(`${label} copied`);
    } catch {
      pushLocalErrorEvent(`Failed to copy ${label.toLowerCase()}`);
    }
  };

  const triggerMixPlanImport = (): void => {
    plannerImportInputRef.current?.click();
  };

  const triggerComparisonImport = (): void => {
    comparisonImportInputRef.current?.click();
  };

  const onMixPlanImportChange = async (
    event: ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const files = event.target.files ? Array.from(event.target.files) : [];
    event.target.value = '';

    if (files.length === 0) {
      return;
    }

    const importedArtifacts: ImportedMixPlanArtifact[] = [];
    const failures: string[] = [];

    for (const file of files) {
      try {
        const payload = await file.text();
        const parsed = parseMixPlanExportJson(payload);

        if (!parsed.envelope) {
          failures.push(`${file.name}: ${parsed.reason ?? 'invalid export'}`);
          continue;
        }

        importedArtifacts.push({
          id: `${Date.now()}-${file.name}-${importedArtifacts.length}`,
          filename: file.name,
          importedAt: new Date().toISOString(),
          envelope: parsed.envelope
        });
      } catch {
        failures.push(`${file.name}: read_failed`);
      }
    }

    if (importedArtifacts.length > 0) {
      setImportedMixPlanArtifacts((previous) =>
        [...importedArtifacts, ...previous].slice(0, MAX_IMPORTED_MIX_PLAN_ARTIFACTS)
      );
      setSelectedImportedMixPlanArtifactId(importedArtifacts[0].id);
      flashPlannerDebugNotice(
        `Imported ${importedArtifacts.length} artifact${importedArtifacts.length > 1 ? 's' : ''}`
      );
    }

    if (failures.length > 0) {
      pushLocalErrorEvent(`MixPlan import failures: ${failures.join(', ')}`);
      if (importedArtifacts.length === 0) {
        flashPlannerDebugNotice('Import failed');
      }
    }
  };

  const onComparisonImportChange = async (
    event: ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const files = event.target.files ? Array.from(event.target.files) : [];
    event.target.value = '';

    if (files.length === 0) {
      return;
    }

    const importedArtifacts: ImportedMixPlanComparisonArtifact[] = [];
    const failures: string[] = [];

    for (const file of files) {
      try {
        const payload = await file.text();
        const parsed = parseMixPlanComparisonExportJson(payload);

        if (!parsed.envelope) {
          failures.push(`${file.name}: ${parsed.reason ?? 'invalid comparison export'}`);
          continue;
        }

        importedArtifacts.push({
          id: `${Date.now()}-${file.name}-${importedArtifacts.length}`,
          filename: file.name,
          importedAt: new Date().toISOString(),
          envelope: parsed.envelope
        });
      } catch {
        failures.push(`${file.name}: read_failed`);
      }
    }

    if (importedArtifacts.length > 0) {
      setImportedMixPlanComparisonArtifacts((previous) =>
        [...importedArtifacts, ...previous].slice(0, MAX_IMPORTED_MIX_PLAN_ARTIFACTS)
      );
      setSelectedImportedMixPlanComparisonArtifactId(importedArtifacts[0].id);
      flashPlannerDebugNotice(
        `Imported ${importedArtifacts.length} comparison artifact${
          importedArtifacts.length > 1 ? 's' : ''
        }`
      );
    }

    if (failures.length > 0) {
      pushLocalErrorEvent(`Comparison import failures: ${failures.join(', ')}`);
      if (importedArtifacts.length === 0) {
        flashPlannerDebugNotice('Comparison import failed');
      }
    }
  };

  const selectImportedMixPlanArtifact = (artifactId: string): void => {
    setSelectedImportedMixPlanArtifactId(artifactId);
  };

  const removeImportedMixPlanArtifact = (artifactId: string): void => {
    setImportedMixPlanArtifacts((previous) => {
      const next = previous.filter((artifact) => artifact.id !== artifactId);
      setSelectedImportedMixPlanArtifactId((currentSelected) => {
        if (currentSelected !== artifactId) {
          return currentSelected;
        }
        return next[0]?.id ?? null;
      });
      setSelectedMixPlanCompareTargetId((currentTarget) => {
        if (currentTarget !== artifactId) {
          return currentTarget;
        }
        return LOCAL_COMPARE_TARGET_ID;
      });
      return next;
    });
  };

  const clearImportedMixPlanArtifacts = (): void => {
    setImportedMixPlanArtifacts([]);
    setSelectedImportedMixPlanArtifactId(null);
    setSelectedMixPlanCompareTargetId(LOCAL_COMPARE_TARGET_ID);
    flashPlannerDebugNotice('Imported artifacts cleared');
  };

  const selectImportedMixPlanComparisonArtifact = (artifactId: string): void => {
    setSelectedImportedMixPlanComparisonArtifactId(artifactId);
  };

  const removeImportedMixPlanComparisonArtifact = (artifactId: string): void => {
    setImportedMixPlanComparisonArtifacts((previous) => {
      const next = previous.filter((artifact) => artifact.id !== artifactId);
      setSelectedImportedMixPlanComparisonArtifactId((currentSelected) => {
        if (currentSelected !== artifactId) {
          return currentSelected;
        }
        return next[0]?.id ?? null;
      });
      return next;
    });
  };

  const clearImportedMixPlanComparisonArtifacts = (): void => {
    setImportedMixPlanComparisonArtifacts([]);
    setSelectedImportedMixPlanComparisonArtifactId(null);
    flashPlannerDebugNotice('Imported comparison artifacts cleared');
  };

  const exportLastMixPlan = (): void => {
    if (!latestSuccessfulMixPlan) {
      pushLocalErrorEvent('No successful MixPlan available to export');
      return;
    }

    const payload = prettyJson(
      buildMixPlanExportEnvelope({
        planner: plannerExportMetadata,
        context: latestPlannerRequestContext,
        mixPlan: latestSuccessfulMixPlan
      })
    );
    const blob = new Blob([payload], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `beatdropper-mix-plan-${timestamp}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
    flashPlannerDebugNotice('Last MixPlan exported');
  };

  const exportPairwiseComparison = (): void => {
    if (!selectedMixPlanComparisonPrimary || !selectedMixPlanCompareTarget) {
      pushLocalErrorEvent('No pairwise comparison available to export');
      return;
    }

    const payload = prettyJson(
      buildMixPlanComparisonExportEnvelope({
        primary: selectedMixPlanComparisonPrimary,
        target: selectedMixPlanCompareTarget
      })
    );
    const blob = new Blob([payload], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `beatdropper-mix-plan-compare-${timestamp}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
    flashPlannerDebugNotice('Pairwise comparison exported');
  };

  const handleLoadTracks = async (mode: TrackLoadMode): Promise<void> => {
    setIsTrackLoadPending(true);
    setTrackLoadNotice(null);
    try {
      const result = await window.dropperApi.openTracks(mode);
      if (result.canceled) {
        setTrackLoadNotice('Import canceled. Current playlist remains unchanged.');
        return;
      }

      const nextState = applyTrackLoadResult(
        {
          tracks,
          selectedIndex,
          currentTrackIndex,
          resolvedBpmByTrack
        },
        result
      );

      setTracks(nextState.tracks);
      setSelectedIndex(nextState.selectedIndex);
      setCurrentTrackIndex(nextState.currentTrackIndex);
      setResolvedBpmByTrack(nextState.resolvedBpmByTrack);
      setLastImportMode(result.mode);
      setLastImportAt(Date.now());
      setSkippedItems(result.skipped);

      const actionLabel = result.mode === 'append' ? 'Added' : 'Loaded';
      const skippedSuffix =
        result.skipped.length > 0 ? ` (${result.skipped.length} skipped)` : '';
      setTrackLoadNotice(`${actionLabel} ${result.tracks.length} track(s)${skippedSuffix}.`);

      if (result.skipped.length > 0) {
        const skippedEvents = skippedMessagesToEvents(result.skipped);
        setEvents((previous) =>
          [...skippedEvents.reverse(), ...previous].slice(0, MAX_LOG_ITEMS)
        );
      }
    } catch (error) {
      const message = formatTrackLoadError(error);
      const loadErrorEvent: PlayerEvent = {
        type: 'error',
        at: 0,
        message
      };
      setEvents((previous) => [loadErrorEvent, ...previous].slice(0, MAX_LOG_ITEMS));
      setSkippedItems((previous) => [...previous, `load failed: ${message}`].slice(-12));
      setTrackLoadNotice(message);
    } finally {
      setIsTrackLoadPending(false);
    }
  };

  const handlePlay = async (): Promise<void> => {
    if (tracks.length === 0) {
      return;
    }

    audioEngine.loadTracks(tracks);
    await audioEngine.start(selectedIndex);
    setIsPlaying(audioEngine.isPlaying());
    setIsPaused(audioEngine.isPaused());
  };

  const handlePlayPause = async (): Promise<void> => {
    if (isPlaying) {
      await audioEngine.pause();
      setIsPlaying(false);
      setIsPaused(true);
      return;
    }

    if (isPaused) {
      await audioEngine.resume();
      setIsPlaying(audioEngine.isPlaying());
      setIsPaused(audioEngine.isPaused());
      setPlaybackStartedAtMs(Date.now() - elapsedSec * 1000);
      return;
    }

    await handlePlay();
  };

  const handleNext = async (): Promise<void> => {
    await audioEngine.skipToNext();
    setIsPlaying(audioEngine.isPlaying());
    setIsPaused(audioEngine.isPaused());
  };

  const handlePrevious = async (): Promise<void> => {
    await audioEngine.skipToPrevious();
    setIsPlaying(audioEngine.isPlaying());
    setIsPaused(audioEngine.isPaused());
  };

  const onFadeChange = (event: ChangeEvent<HTMLInputElement>): void => {
    const value = Number(event.target.value);
    void persistSettings({ fadeDurationSec: value });
  };

  const onRepeatChange = (event: ChangeEvent<HTMLInputElement>): void => {
    void persistSettings({ repeatAll: event.target.checked });
  };

  const onDecodeDurationWeightChange = (
    event: ChangeEvent<HTMLInputElement>
  ): void => {
    const value = Number(event.target.value);
    void persistSettings({ decodeTimeoutDurationWeightMs: value });
  };

  const onDecodeSizeWeightChange = (event: ChangeEvent<HTMLInputElement>): void => {
    const value = Number(event.target.value);
    void persistSettings({ decodeTimeoutSizeWeightMs: value });
  };

  const applyDecodeTimeoutPreset = (preset: DecodeTimeoutPreset): void => {
    void persistSettings({
      decodeTimeoutDurationWeightMs: preset.durationWeightMs,
      decodeTimeoutSizeWeightMs: preset.sizeWeightMs
    });
  };

  const onAiDjEnabledChange = (event: ChangeEvent<HTMLInputElement>): void => {
    void persistSettings({ aiDjEnabled: event.target.checked });
  };

  const onAiDjModeChange = (event: ChangeEvent<HTMLSelectElement>): void => {
    const value = event.target.value;
    if (value === 'safe' || value === 'balanced' || value === 'adventurous') {
      void persistSettings({ aiDjMode: value });
    }
  };

  const commitPlannerCommandDraft = (): void => {
    void persistSettings({ plannerCommand: plannerCommandDraft });
  };

  const commitPlannerArgsDraft = (): void => {
    const plannerArgs = plannerArgsDraft
      .split('\n')
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
    void persistSettings({ plannerArgs });
  };

  const commitPlannerTimeoutDraft = (): void => {
    const nextValue = Number(plannerTimeoutDraft);
    if (!Number.isFinite(nextValue)) {
      setPlannerTimeoutDraft(String(settings.plannerTimeoutMs));
      pushLocalErrorEvent('Planner timeout must be a valid number');
      return;
    }

    void persistSettings({ plannerTimeoutMs: nextValue });
  };

  const applyCodexPlannerPreset = (): void => {
    const nextCommand = 'node';
    const nextArgs = ['scripts/codex-mix-planner.cjs'];
    const nextTimeoutMs = 20000;
    setPlannerCommandDraft(nextCommand);
    setPlannerArgsDraft(formatPlannerArgsDraft(nextArgs));
    setPlannerTimeoutDraft(String(nextTimeoutMs));
    void persistSettings({
      aiDjEnabled: true,
      aiDjMode: 'balanced',
      plannerCommand: nextCommand,
      plannerArgs: nextArgs,
      plannerTimeoutMs: nextTimeoutMs
    });
  };

  const applyHeuristicPlannerPreset = (): void => {
    const nextCommand = 'node';
    const nextArgs = ['scripts/heuristic-mix-planner.cjs'];
    const nextTimeoutMs = 4000;
    setPlannerCommandDraft(nextCommand);
    setPlannerArgsDraft(formatPlannerArgsDraft(nextArgs));
    setPlannerTimeoutDraft(String(nextTimeoutMs));
    void persistSettings({
      aiDjEnabled: true,
      aiDjMode: 'safe',
      plannerCommand: nextCommand,
      plannerArgs: nextArgs,
      plannerTimeoutMs: nextTimeoutMs
    });
  };

  const reorderTracks = (fromIndex: number, toIndex: number): void => {
    if (fromIndex === toIndex) {
      return;
    }

    setTracks((previous) => {
      if (
        fromIndex < 0 ||
        fromIndex >= previous.length ||
        toIndex < 0 ||
        toIndex >= previous.length
      ) {
        return previous;
      }

      const selectedTrackId = previous[selectedIndex]?.id ?? null;
      const currentTrackId =
        currentTrackIndex !== null ? previous[currentTrackIndex]?.id : null;
      const next = [...previous];
      const [moved] = next.splice(fromIndex, 1);
      next.splice(toIndex, 0, moved);

      if (selectedTrackId) {
        const nextSelectedIndex = next.findIndex((track) => track.id === selectedTrackId);
        if (nextSelectedIndex >= 0) {
          setSelectedIndex(nextSelectedIndex);
        }
      }

      if (currentTrackId) {
        const nextCurrentIndex = next.findIndex((track) => track.id === currentTrackId);
        if (nextCurrentIndex >= 0) {
          setCurrentTrackIndex(nextCurrentIndex);
        }
      }

      return next;
    });
  };

  const onTrackDragStart = (index: number): void => {
    setDragIndex(index);
    setDragOverIndex(index);
  };

  const onTrackDragOver = (event: DragEvent<HTMLLIElement>, index: number): void => {
    event.preventDefault();
    if (dragOverIndex !== index) {
      setDragOverIndex(index);
    }
  };

  const onTrackDrop = (index: number): void => {
    if (dragIndex === null) {
      return;
    }
    reorderTracks(dragIndex, index);
    setDragIndex(null);
    setDragOverIndex(null);
  };

  const onTrackDragEnd = (): void => {
    setDragIndex(null);
    setDragOverIndex(null);
  };

  const safeProgressMax = Math.max(currentTrackDurationSec, 1);
  const safeProgressValue = Math.min(Math.max(elapsedSec, 0), safeProgressMax);

  const currentTrackLabel =
    currentTrackIndex !== null && tracks[currentTrackIndex]
      ? tracks[currentTrackIndex].title
      : currentTitle;
  const currentTrack = currentTrackIndex !== null ? tracks[currentTrackIndex] : null;
  const currentTrackBpm = currentTrack
    ? resolvedBpmByTrack[currentTrack.id] ?? currentTrack.bpm ?? null
    : null;
  const activeMeterBars = Math.max(
    0,
    Math.min(METER_BAR_COUNT, Math.round(rmsLevel * METER_BAR_COUNT * 1.7))
  );

  const queueStartIndex =
    currentTrackIndex !== null
      ? Math.min(currentTrackIndex + 1, tracks.length)
      : Math.min(selectedIndex, tracks.length);
  const queueTracks = tracks.slice(queueStartIndex);
  const activeDecodePreset =
    DECODE_TIMEOUT_PRESETS.find(
      (preset) =>
        preset.durationWeightMs === settings.decodeTimeoutDurationWeightMs &&
        preset.sizeWeightMs === settings.decodeTimeoutSizeWeightMs
    ) ?? null;
  const previewStartDecodeMs = estimateAdaptiveDecodeTimeoutMs(
    settings,
    START_DECODE_BASE_TIMEOUT_MS,
    PREVIEW_TRACK_DURATION_SEC,
    PREVIEW_TRACK_SIZE_BYTES
  );
  const previewPredecodeMs = estimateAdaptiveDecodeTimeoutMs(
    settings,
    PREDECODE_BASE_TIMEOUT_MS,
    PREVIEW_TRACK_DURATION_SEC,
    PREVIEW_TRACK_SIZE_BYTES
  );
  const previewTransitionDecodeMs = estimateAdaptiveDecodeTimeoutMs(
    settings,
    TRANSITION_DECODE_BASE_TIMEOUT_MS,
    PREVIEW_TRACK_DURATION_SEC,
    PREVIEW_TRACK_SIZE_BYTES
  );
  const plannerStatusLabel = !settings.aiDjEnabled
    ? 'Disabled'
    : settings.plannerCommand
      ? `Enabled · ${settings.aiDjMode}`
      : 'Enabled · command missing';
  const plannerPresetLabel: MixPlanPlannerPreset =
    settings.plannerCommand === 'node' &&
    settings.plannerArgs.length === 1 &&
    settings.plannerArgs[0] === 'scripts/codex-mix-planner.cjs'
      ? 'codex'
      : settings.plannerCommand === 'node' &&
          settings.plannerArgs.length === 1 &&
          settings.plannerArgs[0] === 'scripts/heuristic-mix-planner.cjs'
        ? 'heuristic'
        : settings.plannerCommand
          ? 'custom'
          : 'none';
  const latestMixPlanApplied = events.find((event) => event.type === 'mix_plan_applied') ?? null;
  const latestMixPlanFallback = events.find((event) => event.type === 'mix_plan_fallback') ?? null;
  const latestTransitionEvent = events.find((event) => event.type === 'transition_started') ?? null;
  const latestTempoApplied = events.find((event) => event.type === 'tempo_sync_applied') ?? null;
  const latestPlannerDebugEvent = latestMixPlanApplied ?? latestMixPlanFallback;
  const latestPlannerResponse = latestPlannerDebugEvent?.details?.plannerResponse ?? null;
  const latestSuccessfulMixPlan: MixPlan | null =
    latestMixPlanApplied?.details?.plannerResponse &&
    isRecord(latestMixPlanApplied.details.plannerResponse) &&
    isRecord(latestMixPlanApplied.details.plannerResponse.mixPlan)
      ? (latestMixPlanApplied.details.plannerResponse.mixPlan as MixPlan)
      : null;
  const latestPlannerReasoning =
    asString(latestMixPlanApplied?.details?.reasoningSummary) ??
    asString(latestTransitionEvent?.details?.reasoningSummary);
  const latestPlannerWindow =
    asFiniteNumber(latestMixPlanApplied?.details?.transitionStartAt) !== null &&
    asFiniteNumber(latestMixPlanApplied?.details?.transitionEndAt) !== null
      ? `${formatDuration(asFiniteNumber(latestMixPlanApplied?.details?.transitionStartAt) ?? 0)} -> ${formatDuration(
          asFiniteNumber(latestMixPlanApplied?.details?.transitionEndAt) ?? 0
        )}`
      : null;
  const latestPlannerOffset = asFiniteNumber(
    latestMixPlanApplied?.details?.nextTrackStartOffsetSec
  );
  const latestTempoRate = formatTempoSyncRate(latestTempoApplied?.details?.targetRate);
  const latestPlannerRequestJson = prettyJson(
    latestPlannerDebugEvent?.details?.plannerRequest ?? null
  );
  const latestPlannerResponseJson = prettyJson(latestPlannerResponse);
  const latestPlannerRequestContext = parseMixPlanExportContextFromUnknown(
    latestMixPlanApplied?.details?.plannerRequest ?? null
  );
  const selectedImportedMixPlanArtifact =
    importedMixPlanArtifacts.find((artifact) => artifact.id === selectedImportedMixPlanArtifactId) ??
    importedMixPlanArtifacts[0] ??
    null;
  const compareTargetOptions: MixPlanCompareTargetOption[] = [
    ...(latestSuccessfulMixPlan
      ? [
          {
            id: LOCAL_COMPARE_TARGET_ID,
            label: 'Latest local MixPlan',
            mixPlan: latestSuccessfulMixPlan,
            summary:
              latestPlannerReasoning ?? latestPlannerWindow ?? 'Latest applied planner result',
            context: latestPlannerRequestContext
          }
        ]
      : []),
    ...importedMixPlanArtifacts
      .filter((artifact) => artifact.id !== selectedImportedMixPlanArtifact?.id)
      .map((artifact) => ({
        id: artifact.id,
        label: artifact.filename,
        mixPlan: artifact.envelope.mixPlan,
        summary: [
          artifact.envelope.planner.presetLabel,
          artifact.envelope.planner.source ?? 'unknown source',
          `exported ${artifact.envelope.exportedAt}`
        ].join(' · '),
        context: artifact.envelope.context
      }))
  ];
  const importedMixPlanSummary = selectedImportedMixPlanArtifact
    ? [
        selectedImportedMixPlanArtifact.envelope.planner.presetLabel,
        selectedImportedMixPlanArtifact.envelope.planner.source ?? 'unknown source',
        selectedImportedMixPlanArtifact.envelope.context
          ? `${selectedImportedMixPlanArtifact.envelope.context.currentTrack.title} -> ${selectedImportedMixPlanArtifact.envelope.context.nextTrack.title}`
          : null,
        `exported ${selectedImportedMixPlanArtifact.envelope.exportedAt}`,
        `imported ${selectedImportedMixPlanArtifact.importedAt}`
      ]
        .filter(Boolean)
        .join(' · ')
    : null;
  const selectedMixPlanComparisonPrimary = selectedImportedMixPlanArtifact
    ? {
        id: selectedImportedMixPlanArtifact.id,
        label: selectedImportedMixPlanArtifact.filename,
        summary: importedMixPlanSummary ?? 'Imported artifact',
        mixPlan: selectedImportedMixPlanArtifact.envelope.mixPlan,
        context: selectedImportedMixPlanArtifact.envelope.context
      }
    : null;
  const selectedMixPlanCompareTarget =
    compareTargetOptions.find((option) => option.id === selectedMixPlanCompareTargetId) ??
    compareTargetOptions[0] ??
    null;
  const importedMixPlanJson = prettyJson(selectedImportedMixPlanArtifact?.envelope ?? null);
  const plannerExportMetadata = {
    preset: plannerPresetLabel,
    presetLabel: MIX_PLAN_PLANNER_PRESET_DESCRIPTIONS[plannerPresetLabel],
    source:
      asString(latestMixPlanApplied?.details?.source) ??
      asString(latestMixPlanFallback?.details?.source) ??
      null,
    command: settings.plannerCommand || null,
    args: settings.plannerArgs,
    timeoutMs: settings.plannerTimeoutMs,
    plannerResponseSchemaVersion: asPlannerResponseSchemaVersion(latestPlannerResponse)
  };
  const plannerExportMetadataEnvelope = buildMixPlanExportMetadata(plannerExportMetadata);
  const latestPlannerDebugMetadata = prettyJson(plannerExportMetadataEnvelope);
  const importedMixPlanComparison = selectedImportedMixPlanArtifact
    ? selectedMixPlanCompareTarget
      ? [
          `compare ${selectedImportedMixPlanArtifact.filename} -> ${selectedMixPlanCompareTarget.label}`,
          `start ${formatSignedDeltaSec(
            selectedImportedMixPlanArtifact.envelope.mixPlan.transitionStartSec -
              selectedMixPlanCompareTarget.mixPlan.transitionStartSec
          )}`,
          `end ${formatSignedDeltaSec(
            selectedImportedMixPlanArtifact.envelope.mixPlan.transitionEndSec -
              selectedMixPlanCompareTarget.mixPlan.transitionEndSec
          )}`,
          `offset ${formatSignedDeltaSec(
            selectedImportedMixPlanArtifact.envelope.mixPlan.nextTrackStartOffsetSec -
              selectedMixPlanCompareTarget.mixPlan.nextTrackStartOffsetSec
          )}`,
          selectedImportedMixPlanArtifact.envelope.mixPlan.style ===
          selectedMixPlanCompareTarget.mixPlan.style
            ? `style same (${selectedImportedMixPlanArtifact.envelope.mixPlan.style})`
            : `style ${selectedMixPlanCompareTarget.mixPlan.style} -> ${selectedImportedMixPlanArtifact.envelope.mixPlan.style}`,
          selectedImportedMixPlanArtifact.envelope.mixPlan.tempoSync.targetRate !==
          selectedMixPlanCompareTarget.mixPlan.tempoSync.targetRate
            ? `tempo ${
                formatTempoSyncRate(selectedMixPlanCompareTarget.mixPlan.tempoSync.targetRate) ??
                'off'
              } -> ${
                formatTempoSyncRate(selectedImportedMixPlanArtifact.envelope.mixPlan.tempoSync.targetRate) ??
                'off'
              }`
            : `tempo same (${
                formatTempoSyncRate(selectedImportedMixPlanArtifact.envelope.mixPlan.tempoSync.targetRate) ??
                'off'
              })`
        ].join(' · ')
      : 'Imported artifact loaded. No comparison target is available yet.'
    : null;
  const pairwiseComparisonRows = selectedMixPlanComparisonPrimary && selectedMixPlanCompareTarget
    ? buildMixPlanComparisonRows({
        primary: selectedMixPlanComparisonPrimary,
        target: selectedMixPlanCompareTarget
      })
    : [];
  const pairwiseComparisonJson = prettyJson(
    selectedMixPlanComparisonPrimary && selectedMixPlanCompareTarget
      ? buildMixPlanComparisonExportEnvelope({
          primary: selectedMixPlanComparisonPrimary,
          target: selectedMixPlanCompareTarget
        })
      : null
  );
  const livePairwiseComparisonEnvelope =
    selectedMixPlanComparisonPrimary && selectedMixPlanCompareTarget
      ? buildMixPlanComparisonExportEnvelope({
          primary: selectedMixPlanComparisonPrimary,
          target: selectedMixPlanCompareTarget
        })
      : null;
  const selectedImportedMixPlanComparisonArtifact =
    importedMixPlanComparisonArtifacts.find(
      (artifact) => artifact.id === selectedImportedMixPlanComparisonArtifactId
    ) ??
    importedMixPlanComparisonArtifacts[0] ??
    null;
  const importedComparisonSummary = selectedImportedMixPlanComparisonArtifact
    ? [
        `${selectedImportedMixPlanComparisonArtifact.envelope.comparison.primary.label} -> ${selectedImportedMixPlanComparisonArtifact.envelope.comparison.target.label}`,
        `exported ${selectedImportedMixPlanComparisonArtifact.envelope.exportedAt}`,
        `imported ${selectedImportedMixPlanComparisonArtifact.importedAt}`
      ].join(' · ')
    : null;
  const importedComparisonJson = prettyJson(
    selectedImportedMixPlanComparisonArtifact?.envelope ?? null
  );
  const liveVsImportedComparisonRows =
    selectedImportedMixPlanComparisonArtifact && livePairwiseComparisonEnvelope
      ? livePairwiseComparisonEnvelope.comparison.rows.map((liveRow) => {
          const importedRow =
            selectedImportedMixPlanComparisonArtifact.envelope.comparison.rows.find(
              (row) => row.label === liveRow.label
            ) ?? null;

          return {
            label: liveRow.label,
            live: `${liveRow.primary} | ${liveRow.target} | ${liveRow.delta}`,
            imported: importedRow
              ? `${importedRow.primary} | ${importedRow.target} | ${importedRow.delta}`
              : 'missing',
            delta: importedRow
              ? formatComparisonDelta(
                  `${liveRow.primary} | ${liveRow.target} | ${liveRow.delta}`,
                  `${importedRow.primary} | ${importedRow.target} | ${importedRow.delta}`
                )
              : 'missing in imported snapshot'
          };
        })
      : [];
  const plannerConfigSummary = [
    settings.plannerCommand ? `command ${settings.plannerCommand}` : 'command missing',
    settings.plannerArgs.length > 0 ? `args ${settings.plannerArgs.join(' ')}` : 'args none',
    `timeout ${settings.plannerTimeoutMs}ms`
  ].join(' · ');

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="brand-block">
          <span className="brand-chip">AUTO DJ / USB FLOW</span>
          <h1>BeatDropper</h1>
          <p>USB Explorer vibe with automatic DJ transitions.</p>
        </div>
        <div className="header-actions">
          <div className={`state-pill ${isPlaying ? 'live' : ''}`}>
            <span>{isPlaying ? 'LIVE MIX' : isPaused ? 'PAUSED' : 'STANDBY'}</span>
            <strong>{currentTrackLabel}</strong>
          </div>
          <button
            type="button"
            className="icon-button"
            aria-label="Open settings"
            onClick={() => setIsUtilityOpen(true)}
          >
            ⚙
          </button>
        </div>
      </header>

      <section className="identity-banner">
        <div className={`identity-meter ${isPlaying ? 'active' : ''}`}>
          {Array.from({ length: METER_BAR_COUNT }, (_, index) => (
            <span key={index} className={index < activeMeterBars ? 'on' : ''} />
          ))}
        </div>
        <div className="identity-copy">
          <strong>{'Flow: USB Load -> Analyze -> Auto Queue'}</strong>
          <span>
            RMS {Math.round(rmsLevel * 100)}% · BPM{' '}
            {currentTrackBpm ? Math.round(currentTrackBpm) : '--'}
          </span>
        </div>
      </section>

      <main className="main-layout">
        <section className="panel devices-panel">
          <div className="panel-head">
            <h2>Devices</h2>
            <span className="panel-tag">USB</span>
          </div>

          <article className="device-card active" aria-busy={isTrackLoadPending}>
            <p className="device-name">USB-1 / Playlists</p>
            <p className="device-path">/Volumes/USB/PLAYLISTS</p>
            <div className="device-actions">
              <button
                type="button"
                className="load-button"
                onClick={() => void handleLoadTracks('replace')}
                disabled={isTrackLoadPending}
              >
                {isTrackLoadPending ? 'Loading...' : 'Load as New'}
              </button>
              <button
                type="button"
                className="secondary-button"
                onClick={() => void handleLoadTracks('append')}
                disabled={tracks.length === 0 || isTrackLoadPending}
              >
                Add to Current
              </button>
            </div>
            <small>Canceling the browser keeps your current playlist unchanged.</small>
          </article>

          <div className="device-tree">
            <strong>Folder View</strong>
            <span>USB-1 / House</span>
            <span>USB-1 / Peak Time</span>
            <span>USB-1 / Warmup</span>
            <span>Local / Downloads</span>
          </div>

          <div className="import-note">
            {isTrackLoadPending ? (
              <p>Importing tracks. Please wait...</p>
            ) : trackLoadNotice ? (
              <p>{trackLoadNotice}</p>
            ) : lastImportAt && lastImportMode ? (
              <p>
                Last import: {lastImportMode === 'replace' ? 'replace' : 'append'} ·{' '}
                {new Date(lastImportAt).toLocaleTimeString()}
              </p>
            ) : (
              <p>No import yet in this session.</p>
            )}
          </div>
        </section>

        <section className="panel playlist-panel">
          <div className="playlist-head">
            <h2>Library</h2>
            <span className="track-count">{tracks.length} tracks</span>
          </div>
          {tracks.length === 0 ? (
            <p className="muted">Load MP3/WAV tracks from your USB playlist.</p>
          ) : (
            <ul className="track-list">
              {tracks.map((track, index) => (
                <li
                  key={track.id}
                  draggable
                  className={[
                    selectedIndex === index ? 'selected' : '',
                    currentTrackIndex === index ? 'playing' : '',
                    dragIndex === index ? 'dragging' : '',
                    dragOverIndex === index && dragIndex !== index ? 'drag-over' : ''
                  ]
                    .filter(Boolean)
                    .join(' ')}
                  onDragStart={() => onTrackDragStart(index)}
                  onDragOver={(event) => onTrackDragOver(event, index)}
                  onDrop={() => onTrackDrop(index)}
                  onDragEnd={onTrackDragEnd}
                >
                  <label>
                    <input
                      type="radio"
                      name="track-select"
                      checked={selectedIndex === index}
                      onChange={() => setSelectedIndex(index)}
                    />
                    <span className="title">{track.title}</span>
                    <span className="duration">{formatDuration(track.durationSec)}</span>
                  </label>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="panel queue-panel">
          <div className="panel-head">
            <h2>Auto DJ Queue</h2>
            <span className="panel-tag">Now / Next</span>
          </div>

          <div className="player-hero">
            <div className={`cover-disc ${isPlaying ? 'spinning' : ''}`}>
              <span>DROP</span>
            </div>
            <div className="hero-meta">
              <p>Now Playing</p>
              <strong>{currentTrackLabel}</strong>
              <small>
                {isPlaying
                  ? 'Seamless mix running'
                  : isPaused
                    ? 'Paused'
                    : 'Ready to start'}
              </small>
            </div>
          </div>

          <div className="progress-wrap">
            <progress
              className="progress-track"
              value={safeProgressValue}
              max={safeProgressMax}
            />
            <div className="time-row">
              <span>{formatDuration(elapsedSec)}</span>
              <span>{formatDuration(currentTrackDurationSec)}</span>
            </div>
          </div>

          <section className="planner-observability-card">
            <div className="planner-observability-head">
              <h3>Planner Watch</h3>
              <span className="panel-tag">{plannerStatusLabel}</span>
            </div>
            <div className="planner-observability-grid">
              <div className="planner-observability-item">
                <span>Last plan</span>
                <strong>{latestMixPlanApplied ? 'Applied' : 'None yet'}</strong>
                <small>
                  {latestPlannerWindow
                    ? `window ${latestPlannerWindow}`
                    : 'No applied plan during this session.'}
                </small>
              </div>
              <div className="planner-observability-item">
                <span>Next offset</span>
                <strong>
                  {latestPlannerOffset !== null ? formatDuration(latestPlannerOffset) : '--'}
                </strong>
                <small>
                  {latestTempoRate ? `tempo ${latestTempoRate}` : 'Tempo sync not fixed by planner.'}
                </small>
              </div>
              <div className="planner-observability-item wide">
                <span>Reasoning</span>
                <strong>{latestPlannerReasoning ?? 'No planner reasoning yet'}</strong>
                <small>
                  {latestMixPlanFallback
                    ? `Latest fallback: ${asString(latestMixPlanFallback.details?.reason) ?? 'unknown'}`
                    : 'No planner fallback recorded in this session.'}
                </small>
              </div>
            </div>
          </section>

          <div className="transport-shell main-buttons">
            <div className="transport-row">
              <button
                type="button"
                className="transport-btn prev"
                onClick={() => void handlePrevious()}
                disabled={!isPlaying && !isPaused}
                aria-label="Previous"
                title="Previous"
              >
                <span className="transport-icon">
                  <TransportIcon name="previous" />
                </span>
              </button>
              <button
                type="button"
                className={`transport-btn toggle ${isPlaying ? 'pause' : 'play'}`}
                onClick={() => void handlePlayPause()}
                disabled={!isPaused && !isPlaying && tracks.length === 0}
                aria-label={isPlaying ? 'Pause' : 'Play'}
                title={isPlaying ? 'Pause' : 'Play'}
              >
                <span className="transport-icon">
                  <TransportIcon name={isPlaying ? 'pause' : 'play'} />
                </span>
              </button>
              <button
                type="button"
                className="transport-btn next"
                onClick={() => void handleNext()}
                disabled={!isPlaying && !isPaused}
                aria-label="Next"
                title="Next"
              >
                <span className="transport-icon">
                  <TransportIcon name="next" />
                </span>
              </button>
            </div>
          </div>

          <div className="queue-list-wrap">
            <h3>Up Next</h3>
            {queueTracks.length === 0 ? (
              <p className="muted">Queue is empty.</p>
            ) : (
              <ul className="queue-list">
                {queueTracks.map((track, index) => (
                  <li key={`${track.id}-${index}`}>
                    <span className="queue-order">{queueStartIndex + index + 1}</span>
                    <span className="queue-title">{track.title}</span>
                    <span className="queue-duration">{formatDuration(track.durationSec)}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>
      </main>

      {isUtilityOpen && (
        <div className="utility-overlay" onClick={() => setIsUtilityOpen(false)}>
          <aside className="utility-drawer" onClick={(event) => event.stopPropagation()}>
            <header className="utility-header">
              <h2>Settings & Logs</h2>
              <button
                type="button"
                className="icon-button"
                aria-label="Close settings"
                onClick={() => setIsUtilityOpen(false)}
              >
                ✕
              </button>
            </header>

            <section className="utility-section">
              <h3>Advanced Playback</h3>
              <div className="setting-row">
                <label htmlFor="fade-slider">
                  Crossfade (sec): {settings.fadeDurationSec}
                </label>
                <input
                  id="fade-slider"
                  type="range"
                  min={2}
                  max={20}
                  step={1}
                  value={settings.fadeDurationSec}
                  onChange={onFadeChange}
                />
              </div>
              <div className="setting-row inline">
                <label htmlFor="repeat-all">Repeat All</label>
                <input
                  id="repeat-all"
                  type="checkbox"
                  checked={settings.repeatAll}
                  onChange={onRepeatChange}
                />
              </div>
              <div className="setting-row">
                <label htmlFor="decode-duration-weight">
                  Decode wait by track length: {settings.decodeTimeoutDurationWeightMs}ms/sec
                </label>
                <input
                  id="decode-duration-weight"
                  type="range"
                  min={0}
                  max={80}
                  step={1}
                  value={settings.decodeTimeoutDurationWeightMs}
                  onChange={onDecodeDurationWeightChange}
                />
              </div>
              <div className="setting-row">
                <label htmlFor="decode-size-weight">
                  Decode wait by file size: {settings.decodeTimeoutSizeWeightMs}ms/MB
                </label>
                <input
                  id="decode-size-weight"
                  type="range"
                  min={0}
                  max={1200}
                  step={10}
                  value={settings.decodeTimeoutSizeWeightMs}
                  onChange={onDecodeSizeWeightChange}
                />
              </div>
              <div className="setting-row">
                <label>
                  Decode profile: {activeDecodePreset ? activeDecodePreset.label : '커스텀'}
                </label>
                <div className="preset-row">
                  {DECODE_TIMEOUT_PRESETS.map((preset) => (
                    <button
                      key={preset.id}
                      type="button"
                      className={`preset-button ${
                        activeDecodePreset?.id === preset.id ? 'active' : ''
                      }`}
                      onClick={() => applyDecodeTimeoutPreset(preset)}
                    >
                      {preset.label}
                    </button>
                  ))}
                </div>
              </div>
              <div className="setting-row hint">
                <small className="setting-hint">
                  예상 대기시간(10초 / 8MB 기준): 시작 {formatDecodePreviewSec(
                    previewStartDecodeMs
                  )}{' '}
                  · 사전디코드 {formatDecodePreviewSec(previewPredecodeMs)} · 전환{' '}
                  {formatDecodePreviewSec(previewTransitionDecodeMs)}
                </small>
              </div>
            </section>

            <section className="utility-section">
              <h3>AI DJ Planner</h3>
              <div className="setting-row inline">
                <label htmlFor="ai-dj-enabled">Enable AI DJ Planner</label>
                <input
                  id="ai-dj-enabled"
                  type="checkbox"
                  checked={settings.aiDjEnabled}
                  onChange={onAiDjEnabledChange}
                />
              </div>
              <div className="setting-row">
                <label htmlFor="ai-dj-mode">Planner mode</label>
                <select
                  id="ai-dj-mode"
                  value={settings.aiDjMode}
                  onChange={onAiDjModeChange}
                >
                  <option value="safe">safe</option>
                  <option value="balanced">balanced</option>
                  <option value="adventurous">adventurous</option>
                </select>
              </div>
              <div className="setting-row">
                <label htmlFor="planner-command">Planner command</label>
                <input
                  id="planner-command"
                  type="text"
                  value={plannerCommandDraft}
                  onChange={(event) => setPlannerCommandDraft(event.target.value)}
                  onBlur={commitPlannerCommandDraft}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') {
                      event.preventDefault();
                      commitPlannerCommandDraft();
                    }
                  }}
                  placeholder="node"
                />
              </div>
              <div className="setting-row">
                <label htmlFor="planner-args">Planner args (one per line)</label>
                <textarea
                  id="planner-args"
                  rows={4}
                  value={plannerArgsDraft}
                  onChange={(event) => setPlannerArgsDraft(event.target.value)}
                  onBlur={commitPlannerArgsDraft}
                  placeholder={'scripts/codex-mix-planner.cjs'}
                />
              </div>
              <div className="setting-row">
                <label htmlFor="planner-timeout">Planner timeout (ms)</label>
                <input
                  id="planner-timeout"
                  type="number"
                  min={500}
                  max={30000}
                  step={100}
                  value={plannerTimeoutDraft}
                  onChange={(event) => setPlannerTimeoutDraft(event.target.value)}
                  onBlur={commitPlannerTimeoutDraft}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter') {
                      event.preventDefault();
                      commitPlannerTimeoutDraft();
                    }
                  }}
                />
              </div>
              <div className="setting-row">
                <label>Planner status: {plannerStatusLabel}</label>
                <div className="planner-helper-row">
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={applyCodexPlannerPreset}
                  >
                    Use Sample Codex Wrapper
                  </button>
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={applyHeuristicPlannerPreset}
                  >
                    Use Local Heuristic
                  </button>
                </div>
              </div>
              <div className="setting-row hint">
                <small className="setting-hint">
                  BeatDropper calls the planner through stdin/stdout JSON. Any agent CLI can work if
                  it follows the same `MixPlan` contract. The sample Codex wrapper lives at
                  `scripts/codex-mix-planner.cjs`.
                </small>
              </div>
            </section>

            <section className="utility-section">
              <h3>Planner Debug</h3>
              <input
                ref={plannerImportInputRef}
                type="file"
                accept=".json,application/json"
                multiple
                className="visually-hidden"
                onChange={(event) => void onMixPlanImportChange(event)}
              />
              <input
                ref={comparisonImportInputRef}
                type="file"
                accept=".json,application/json"
                multiple
                className="visually-hidden"
                onChange={(event) => void onComparisonImportChange(event)}
              />
              <div className="setting-row">
                <label>Current planner config</label>
                <div className="planner-debug-summary">
                  <strong>{MIX_PLAN_PLANNER_PRESET_DESCRIPTIONS[plannerPresetLabel]}</strong>
                  <small>{plannerConfigSummary}</small>
                </div>
              </div>
              <div className="setting-row">
                <label>Debug metadata</label>
                <textarea
                  className="debug-json debug-json-compact"
                  readOnly
                  value={latestPlannerDebugMetadata}
                />
              </div>
              <div className="setting-row">
                <label>Latest planner request</label>
                <textarea
                  className="debug-json"
                  readOnly
                  value={latestPlannerRequestJson}
                />
                <div className="planner-helper-row">
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={() => void copyPlannerDebug('Planner request', latestPlannerRequestJson)}
                  >
                    Copy Request JSON
                  </button>
                </div>
              </div>
              <div className="setting-row">
                <label>Latest planner response</label>
                <textarea
                  className="debug-json"
                  readOnly
                  value={latestPlannerResponseJson}
                />
                <div className="planner-helper-row">
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={() => void copyPlannerDebug('Planner response', latestPlannerResponseJson)}
                  >
                    Copy Response JSON
                  </button>
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={exportLastMixPlan}
                    disabled={!latestSuccessfulMixPlan}
                  >
                    Export Last MixPlan
                  </button>
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={triggerMixPlanImport}
                  >
                    Import Export JSON
                  </button>
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={triggerComparisonImport}
                  >
                    Import Comparison JSON
                  </button>
                </div>
              </div>
              <div className="setting-row">
                <label>Imported export artifacts</label>
                {importedMixPlanArtifacts.length > 0 ? (
                  <div className="planner-artifact-panel">
                    <div className="planner-helper-row">
                      <button
                        type="button"
                        className="secondary-button planner-preset-button"
                        onClick={clearImportedMixPlanArtifacts}
                      >
                        Clear Imported
                      </button>
                    </div>
                    <ul className="planner-artifact-list">
                      {importedMixPlanArtifacts.map((artifact) => {
                        const isActive = artifact.id === selectedImportedMixPlanArtifact?.id;
                        return (
                          <li key={artifact.id} className={isActive ? 'active' : ''}>
                            <button
                              type="button"
                              className="planner-artifact-select"
                              onClick={() => selectImportedMixPlanArtifact(artifact.id)}
                            >
                              <strong>{artifact.filename}</strong>
                              <small>
                                {artifact.envelope.planner.presetLabel} ·{' '}
                                {artifact.envelope.planner.source ?? 'unknown source'}
                              </small>
                            </button>
                            <button
                              type="button"
                              className="secondary-button planner-artifact-remove"
                              onClick={() => removeImportedMixPlanArtifact(artifact.id)}
                            >
                              Remove
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                    {selectedImportedMixPlanArtifact ? (
                      <div className="planner-debug-summary">
                        <strong>{selectedImportedMixPlanArtifact.filename}</strong>
                        <small>{importedMixPlanSummary}</small>
                      </div>
                    ) : null}
                  </div>
                ) : (
                  <p className="muted">No imported export artifacts.</p>
                )}
              </div>
              <div className="setting-row">
                <label>Selected imported artifact JSON</label>
                <textarea
                  className="debug-json"
                  readOnly
                  value={importedMixPlanJson}
                />
                <div className="planner-helper-row">
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={() => void copyPlannerDebug('Imported artifact', importedMixPlanJson)}
                    disabled={!selectedImportedMixPlanArtifact}
                  >
                    Copy Imported JSON
                  </button>
                </div>
              </div>
              <div className="setting-row">
                <label htmlFor="mix-plan-compare-target">Compare target</label>
                <select
                  id="mix-plan-compare-target"
                  value={selectedMixPlanCompareTarget?.id ?? ''}
                  onChange={(event) => setSelectedMixPlanCompareTargetId(event.target.value)}
                  disabled={!selectedImportedMixPlanArtifact || compareTargetOptions.length === 0}
                >
                  {compareTargetOptions.length === 0 ? (
                    <option value="">No compare target</option>
                  ) : (
                    compareTargetOptions.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.label}
                      </option>
                    ))
                  )}
                </select>
              </div>
              <div className="setting-row">
                <label>Pairwise comparison</label>
                {selectedImportedMixPlanArtifact && selectedMixPlanCompareTarget ? (
                  <div className="planner-compare-panel">
                    <div className="planner-debug-summary">
                      <strong>Primary: {selectedImportedMixPlanArtifact.filename}</strong>
                      <small>{importedMixPlanSummary}</small>
                    </div>
                    <div className="planner-debug-summary">
                      <strong>Target: {selectedMixPlanCompareTarget.label}</strong>
                      <small>{selectedMixPlanCompareTarget.summary}</small>
                    </div>
                    <div className="planner-helper-row">
                      <button
                        type="button"
                        className="secondary-button planner-preset-button"
                        onClick={() => void copyPlannerDebug('Pairwise comparison', pairwiseComparisonJson)}
                      >
                        Copy Comparison JSON
                      </button>
                      <button
                        type="button"
                        className="secondary-button planner-preset-button"
                        onClick={exportPairwiseComparison}
                      >
                        Export Comparison JSON
                      </button>
                    </div>
                    <div className="planner-compare-grid">
                      <div className="planner-compare-grid-head">Metric</div>
                      <div className="planner-compare-grid-head">Primary</div>
                      <div className="planner-compare-grid-head">Target</div>
                      <div className="planner-compare-grid-head">Delta</div>
                      {pairwiseComparisonRows.flatMap((row) => [
                        <div className="planner-compare-grid-label" key={`${row.label}-label`}>
                          {row.label}
                        </div>,
                        <div key={`${row.label}-primary`}>{row.primary}</div>,
                        <div key={`${row.label}-target`}>{row.target}</div>,
                        <div key={`${row.label}-delta`}>{row.delta}</div>
                      ])}
                    </div>
                  </div>
                ) : (
                  <p className="muted">Select an imported artifact and a compare target.</p>
                )}
              </div>
              <div className="setting-row">
                <label>Imported comparison artifacts</label>
                {importedMixPlanComparisonArtifacts.length > 0 ? (
                  <div className="planner-artifact-panel">
                    <div className="planner-helper-row">
                      <button
                        type="button"
                        className="secondary-button planner-preset-button"
                        onClick={clearImportedMixPlanComparisonArtifacts}
                      >
                        Clear Imported Comparisons
                      </button>
                    </div>
                    <ul className="planner-artifact-list">
                      {importedMixPlanComparisonArtifacts.map((artifact) => {
                        const isActive =
                          artifact.id === selectedImportedMixPlanComparisonArtifact?.id;
                        return (
                          <li key={artifact.id} className={isActive ? 'active' : ''}>
                            <button
                              type="button"
                              className="planner-artifact-select"
                              onClick={() => selectImportedMixPlanComparisonArtifact(artifact.id)}
                            >
                              <strong>{artifact.filename}</strong>
                              <small>
                                {artifact.envelope.comparison.primary.label}
                                {' -> '}
                                {artifact.envelope.comparison.target.label}
                              </small>
                            </button>
                            <button
                              type="button"
                              className="secondary-button planner-artifact-remove"
                              onClick={() => removeImportedMixPlanComparisonArtifact(artifact.id)}
                            >
                              Remove
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                    {selectedImportedMixPlanComparisonArtifact ? (
                      <div className="planner-debug-summary">
                        <strong>{selectedImportedMixPlanComparisonArtifact.filename}</strong>
                        <small>{importedComparisonSummary}</small>
                      </div>
                    ) : null}
                  </div>
                ) : (
                  <p className="muted">No imported comparison artifacts.</p>
                )}
              </div>
              <div className="setting-row">
                <label>Selected imported comparison JSON</label>
                <textarea
                  className="debug-json"
                  readOnly
                  value={importedComparisonJson}
                />
                <div className="planner-helper-row">
                  <button
                    type="button"
                    className="secondary-button planner-preset-button"
                    onClick={() =>
                      void copyPlannerDebug('Imported comparison', importedComparisonJson)
                    }
                    disabled={!selectedImportedMixPlanComparisonArtifact}
                  >
                    Copy Imported Comparison JSON
                  </button>
                </div>
              </div>
              <div className="setting-row">
                <label>Imported comparison review</label>
                {selectedImportedMixPlanComparisonArtifact ? (
                  <div className="planner-compare-panel">
                    <div className="planner-debug-summary">
                      <strong>
                        Primary: {selectedImportedMixPlanComparisonArtifact.envelope.comparison.primary.label}
                      </strong>
                      <small>
                        {selectedImportedMixPlanComparisonArtifact.envelope.comparison.primary.summary}
                      </small>
                    </div>
                    <div className="planner-debug-summary">
                      <strong>
                        Target: {selectedImportedMixPlanComparisonArtifact.envelope.comparison.target.label}
                      </strong>
                      <small>
                        {selectedImportedMixPlanComparisonArtifact.envelope.comparison.target.summary}
                      </small>
                    </div>
                    <div className="planner-compare-grid">
                      <div className="planner-compare-grid-head">Metric</div>
                      <div className="planner-compare-grid-head">Primary</div>
                      <div className="planner-compare-grid-head">Target</div>
                      <div className="planner-compare-grid-head">Delta</div>
                      {selectedImportedMixPlanComparisonArtifact.envelope.comparison.rows.flatMap(
                        (row) => [
                          <div className="planner-compare-grid-label" key={`${row.label}-imported-label`}>
                            {row.label}
                          </div>,
                          <div key={`${row.label}-imported-primary`}>{row.primary}</div>,
                          <div key={`${row.label}-imported-target`}>{row.target}</div>,
                          <div key={`${row.label}-imported-delta`}>{row.delta}</div>
                        ]
                      )}
                    </div>
                  </div>
                ) : (
                  <p className="muted">No imported comparison artifact selected.</p>
                )}
              </div>
              <div className="setting-row">
                <label>Imported vs live comparison</label>
                {selectedImportedMixPlanComparisonArtifact && livePairwiseComparisonEnvelope ? (
                  <div className="planner-compare-panel">
                    <div className="planner-debug-summary">
                      <strong>
                        Live: {livePairwiseComparisonEnvelope.comparison.primary.label} {' -> '}{livePairwiseComparisonEnvelope.comparison.target.label}
                      </strong>
                      <small>
                        {livePairwiseComparisonEnvelope.comparison.primary.summary} ·{' '}
                        {livePairwiseComparisonEnvelope.comparison.target.summary}
                      </small>
                    </div>
                    <div className="planner-debug-summary">
                      <strong>
                        Imported: {selectedImportedMixPlanComparisonArtifact.envelope.comparison.primary.label}
                        {' -> '}
                        {selectedImportedMixPlanComparisonArtifact.envelope.comparison.target.label}
                      </strong>
                      <small>{importedComparisonSummary}</small>
                    </div>
                    <div className="planner-review-grid">
                      <div className="planner-compare-grid-head">Metric</div>
                      <div className="planner-compare-grid-head">Live</div>
                      <div className="planner-compare-grid-head">Imported</div>
                      <div className="planner-compare-grid-head">Change</div>
                      {liveVsImportedComparisonRows.flatMap((row) => [
                        <div className="planner-compare-grid-label" key={`${row.label}-review-label`}>
                          {row.label}
                        </div>,
                        <div key={`${row.label}-review-live`}>{row.live}</div>,
                        <div key={`${row.label}-review-imported`}>{row.imported}</div>,
                        <div key={`${row.label}-review-delta`}>{row.delta}</div>
                      ])}
                    </div>
                  </div>
                ) : (
                  <p className="muted">
                    Select an imported comparison artifact and keep a live pairwise comparison active.
                  </p>
                )}
              </div>
              <div className="setting-row hint">
                <small className="setting-hint">
                  {importedMixPlanComparison ??
                    'Imported export artifacts are compare-only in this slice, stay in the current session, and never override playback.'}
                </small>
              </div>
              <div className="setting-row hint">
                <small className="setting-hint">
                  {plannerDebugCopyNotice ??
                    'The latest applied or fallback planner event is shown here for debugging.'}
                </small>
              </div>
            </section>

            <section className="utility-section">
              <h3>Skipped Files</h3>
              {skippedItems.length === 0 ? (
                <p className="muted">No skipped files.</p>
              ) : (
                <ul className="skipped-list">
                  {skippedItems.map((item) => (
                    <li key={item}>{item}</li>
                  ))}
                </ul>
              )}
            </section>

            <section className="utility-section">
              <h3>Session Log</h3>
              {events.length === 0 ? (
                <p className="muted">No playback events yet.</p>
              ) : (
                <ul className="event-list">
                  {events.map((event, index) => (
                    <li key={`${event.type}-${index}`}>
                      <span className={`badge ${event.type}`}>{event.type}</span>
                      <span className="time">{formatEventTime(event.at)}s</span>
                      <div className="event-copy">
                        <span className="message">{event.message}</span>
                        {formatPlannerEventDetails(event) ? (
                          <small className="event-meta">
                            {formatPlannerEventDetails(event)}
                          </small>
                        ) : null}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </aside>
        </div>
      )}
    </div>
  );
};
