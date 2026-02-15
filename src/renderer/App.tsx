import {
  CSSProperties,
  ChangeEvent,
  DragEvent,
  useEffect,
  useMemo,
  useRef,
  useState
} from 'react';
import { DEFAULT_SETTINGS, sanitizeSettings } from '../shared/settings';
import { PlayerEvent, PlayerSettings, Track } from '../shared/types';
import { AudioEngine } from './player';

const MAX_LOG_ITEMS = 100;

const formatDuration = (sec: number): string => {
  const safeSec = Math.max(0, Math.floor(sec));
  const min = Math.floor(safeSec / 60);
  const rem = safeSec % 60;
  return `${min}:${String(rem).padStart(2, '0')}`;
};

const formatEventTime = (value: number): string => value.toFixed(2);
const METER_BAR_COUNT = 18;
type TransportIconName = 'play' | 'pause' | 'previous' | 'next';

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

  const tracksRef = useRef<Track[]>([]);
  const audioEngine = useMemo(
    () =>
      new AudioEngine({
        readTrackBuffer: window.dropperApi.readTrackBufferById,
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
    const handle = window.setInterval(() => {
      setRmsLevel(audioEngine.getOutputLevel());
    }, 60);
    return () => window.clearInterval(handle);
  }, [audioEngine]);

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

  const handleLoadTracks = async (): Promise<void> => {
    const result = await window.dropperApi.openTracks();
    setTracks(result.tracks);
    tracksRef.current = result.tracks;
    setSelectedIndex(0);
    setSkippedItems(result.skipped);
    setResolvedBpmByTrack({});
    audioEngine.loadTracks(result.tracks);

    if (result.skipped.length > 0) {
      const skippedEvents = result.skipped.map<PlayerEvent>((message) => ({
        type: 'track_skipped',
        at: 0,
        message
      }));
      setEvents((previous) =>
        [...skippedEvents.reverse(), ...previous].slice(0, MAX_LOG_ITEMS)
      );
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

  const progressPercent =
    currentTrackDurationSec > 0
      ? Math.min((elapsedSec / currentTrackDurationSec) * 100, 100)
      : 0;

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

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="brand-block">
          <span className="brand-chip">DROP MODE</span>
          <h1>BeatDropper</h1>
          <p>You pick tracks, BeatDropper drops the beat.</p>
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
            <span
              key={index}
              className={index < activeMeterBars ? 'on' : ''}
              style={
                {
                  '--meter-height': `${22 + (index % 6) * 10}%`
                } as CSSProperties
              }
            />
          ))}
        </div>
        <div className="identity-copy">
          <strong>Live Audio Meter</strong>
          <span>
            RMS {Math.round(rmsLevel * 100)}% · BPM{' '}
            {currentTrackBpm ? Math.round(currentTrackBpm) : '--'}
          </span>
        </div>
      </section>

      <main className="main-layout">
        <section className="panel transport-panel">
          <h2>Player</h2>
          <div className="player-hero">
            <div className={`cover-disc ${isPlaying ? 'spinning' : ''}`}>
              <span>DROP</span>
            </div>
            <div className="hero-meta">
              <p>Now Playing</p>
              <strong>{currentTrackLabel}</strong>
              <small>
                {isPlaying
                  ? 'Seamless Mix Running'
                  : isPaused
                    ? 'Paused'
                    : 'Ready to Mix'}
              </small>
            </div>
          </div>

          <div className="progress-wrap">
            <div className="progress-track">
              <span style={{ width: `${progressPercent}%` }} />
            </div>
            <div className="time-row">
              <span>{formatDuration(elapsedSec)}</span>
              <span>{formatDuration(currentTrackDurationSec)}</span>
            </div>
          </div>

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

        </section>

        <section className="panel playlist-panel">
          <div className="playlist-head">
            <h2>Playlist</h2>
            <button
              type="button"
              className="load-button playlist-load"
              onClick={() => void handleLoadTracks()}
            >
              + Load Tracks
            </button>
          </div>
          {tracks.length === 0 ? (
            <p className="muted">Load local MP3/WAV files to start.</p>
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
                      <span className="message">{event.message}</span>
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
