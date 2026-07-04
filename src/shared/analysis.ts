export const TRACK_ANALYSIS_SCHEMA_VERSION = 7;

export type TrackAnalysisSource = 'metadata' | 'derived' | 'external';
export type CueCandidateType =
  | 'intro'
  | 'first_downbeat'
  | 'outro'
  | 'low_energy_break'
  | 'high_energy_drop';
export type CueCandidateOrigin = 'derived' | 'heuristic_placeholder' | 'user';
export type AnalysisWarning =
  | 'bpm_unavailable'
  | 'bpm_low_confidence'
  | 'bpm_metadata_mismatch'
  | 'beat_grid_estimated'
  | 'short_track'
  | 'flat_energy'
  | 'analysis_upgrade_available'
  | 'key_unavailable'
  | 'key_low_confidence'
  | 'loudness_low_confidence'
  | 'headroom_low';
export type MusicalKeyMode = 'major' | 'minor';

export interface MusicalKeyEstimate {
  tonic: string;
  mode: MusicalKeyMode;
  confidence: number;
  chromaEnergy: number;
}

export interface LoudnessAnalysis {
  integratedRMSDb: number;
  integratedLUFS?: number | null;
  peakDb: number;
  truePeakDb?: number | null;
  headroomDb: number;
  crestFactorDb: number;
  dynamicRangeDb: number;
  loudnessRangeLU?: number | null;
  measurement?: string | null;
  confidence: number;
}

export interface StereoAnalysis {
  channelCount: number;
  leftPeakDb?: number | null;
  rightPeakDb?: number | null;
  leftRMSDb?: number | null;
  rightRMSDb?: number | null;
  stereoWidth: number;
  phaseCorrelation: number;
  midSideBalance: number;
  confidence: number;
}

export interface WaveformPeak {
  timeSec: number;
  peak: number;
  rms: number;
}

export interface WaveformDetailPoint extends WaveformPeak {
  min: number;
  max: number;
}

export interface SpectralBandPoint {
  timeSec: number;
  low: number;
  mid: number;
  high: number;
}

export interface TransientMarker {
  index: number;
  timeSec: number;
  strength: number;
}

export interface AnalysisQuality {
  waveformDetail: number;
  spectralBands: number;
  transientMarkers: number;
  beatGrid: number;
  harmonicKey?: number;
}

export interface TrackFileRevision {
  sizeBytes: number;
  mtimeMs: number;
}

export interface BarMarker {
  index: number;
  startSec: number;
  beatIndex: number;
}

export interface PhraseMarker {
  index: number;
  startSec: number;
  bars: number;
  confidence: number;
}

export interface CueCandidate {
  id: string;
  type: CueCandidateType;
  startSec: number;
  endSec: number;
  confidence: number;
  label: string;
  origin: CueCandidateOrigin;
}

export interface TrackAnalysis {
  schemaVersion: typeof TRACK_ANALYSIS_SCHEMA_VERSION;
  trackId: string;
  generatedAt: string;
  source: TrackAnalysisSource;
  fileRevision: TrackFileRevision | null;
  bpm: number | null;
  bpmConfidence: number;
  beatGridSec: number[];
  downbeatsSec: number[];
  barGrid: BarMarker[];
  phraseMarkers: PhraseMarker[];
  introCueSec: number | null;
  outroCueSec: number | null;
  energyProfile: number[];
  waveformPeaks: WaveformPeak[];
  waveformDetail: WaveformDetailPoint[];
  spectralBands: SpectralBandPoint[];
  transientMarkers: TransientMarker[];
  cueCandidates: CueCandidate[];
  musicalKey?: MusicalKeyEstimate | null;
  loudness?: LoudnessAnalysis | null;
  stereo?: StereoAnalysis | null;
  analysisConfidence: number;
  analysisQuality: AnalysisQuality;
  analysisWarnings: AnalysisWarning[];
}

export const PLANNER_READY_MIN_WAVEFORM_DETAIL_QUALITY = 0.2;
export const PLANNER_READY_MIN_BEAT_GRID_QUALITY = 0.35;
export const PLANNER_READY_MIN_BPM_CONFIDENCE = 0.45;

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const asNumberList = (value: unknown): number[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is number => isFiniteNumber(item));
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const asWaveformPeaks = (value: unknown): WaveformPeak[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isRecord)
    .map((item) => ({
      timeSec: isFiniteNumber(item.timeSec) ? Math.max(0, item.timeSec) : 0,
      peak: isFiniteNumber(item.peak) ? clamp(item.peak, 0, 1) : 0,
      rms: isFiniteNumber(item.rms) ? clamp(item.rms, 0, 1) : 0
    }))
    .filter((item) => item.timeSec >= 0);
};

const asWaveformDetail = (value: unknown): WaveformDetailPoint[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isRecord)
    .map((item) => {
      const min = isFiniteNumber(item.min) ? clamp(item.min, -1, 1) : 0;
      const max = isFiniteNumber(item.max) ? clamp(item.max, -1, 1) : 0;
      return {
        timeSec: isFiniteNumber(item.timeSec) ? Math.max(0, item.timeSec) : 0,
        peak: isFiniteNumber(item.peak) ? clamp(item.peak, 0, 1) : Math.max(Math.abs(min), Math.abs(max)),
        rms: isFiniteNumber(item.rms) ? clamp(item.rms, 0, 1) : 0,
        min,
        max
      };
    })
    .filter((item) => item.timeSec >= 0)
    .slice(0, 2000);
};

const asSpectralBands = (value: unknown): SpectralBandPoint[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isRecord)
    .map((item) => ({
      timeSec: isFiniteNumber(item.timeSec) ? Math.max(0, item.timeSec) : 0,
      low: isFiniteNumber(item.low) ? clamp(item.low, 0, 1) : 0,
      mid: isFiniteNumber(item.mid) ? clamp(item.mid, 0, 1) : 0,
      high: isFiniteNumber(item.high) ? clamp(item.high, 0, 1) : 0
    }))
    .filter((item) => item.timeSec >= 0)
    .slice(0, 2000);
};

const asTransientMarkers = (value: unknown): TransientMarker[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isRecord)
    .map((item, index) => ({
      index: isFiniteNumber(item.index) ? Math.max(0, Math.floor(item.index)) : index,
      timeSec: isFiniteNumber(item.timeSec) ? Math.max(0, item.timeSec) : 0,
      strength: isFiniteNumber(item.strength) ? clamp(item.strength, 0, 1) : 0
    }))
    .filter((item) => item.timeSec >= 0 && item.strength > 0)
    .slice(0, 512);
};

const asBarMarkers = (value: unknown): BarMarker[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isRecord)
    .map((item) => ({
      index: isFiniteNumber(item.index) ? Math.max(0, Math.floor(item.index)) : 0,
      startSec: isFiniteNumber(item.startSec) ? Math.max(0, item.startSec) : 0,
      beatIndex: isFiniteNumber(item.beatIndex) ? Math.max(0, Math.floor(item.beatIndex)) : 0
    }));
};

const asPhraseMarkers = (value: unknown): PhraseMarker[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isRecord)
    .map((item) => ({
      index: isFiniteNumber(item.index) ? Math.max(0, Math.floor(item.index)) : 0,
      startSec: isFiniteNumber(item.startSec) ? Math.max(0, item.startSec) : 0,
      bars: isFiniteNumber(item.bars) ? Math.max(1, Math.floor(item.bars)) : 8,
      confidence: isFiniteNumber(item.confidence) ? clamp(item.confidence, 0, 1) : 0
    }));
};

const asCueCandidates = (value: unknown): CueCandidate[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(isRecord)
    .map((item, index) => {
      const type =
        item.type === 'intro' ||
        item.type === 'first_downbeat' ||
        item.type === 'outro' ||
        item.type === 'low_energy_break' ||
        item.type === 'high_energy_drop'
          ? item.type
          : 'intro';
      const startSec = isFiniteNumber(item.startSec) ? Math.max(0, item.startSec) : 0;
      const endSec = isFiniteNumber(item.endSec)
        ? Math.max(startSec, item.endSec)
        : startSec;
      return {
        id: typeof item.id === 'string' && item.id.length > 0 ? item.id : `${type}-${index}`,
        type,
        startSec,
        endSec,
        confidence: isFiniteNumber(item.confidence) ? clamp(item.confidence, 0, 1) : 0,
        label: typeof item.label === 'string' && item.label.length > 0 ? item.label : type,
        origin:
          item.origin === 'derived' || item.origin === 'user'
            ? item.origin
            : 'heuristic_placeholder'
      };
    });
};

const asAnalysisWarnings = (value: unknown): AnalysisWarning[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is AnalysisWarning =>
    item === 'bpm_unavailable' ||
    item === 'bpm_low_confidence' ||
    item === 'bpm_metadata_mismatch' ||
    item === 'beat_grid_estimated' ||
    item === 'short_track' ||
    item === 'flat_energy' ||
    item === 'analysis_upgrade_available' ||
    item === 'key_unavailable' ||
    item === 'key_low_confidence' ||
    item === 'loudness_low_confidence' ||
    item === 'headroom_low'
  );
};

const asAnalysisQuality = (value: unknown): AnalysisQuality => {
  if (!isRecord(value)) {
    return {
      waveformDetail: 0,
      spectralBands: 0,
      transientMarkers: 0,
      beatGrid: 0,
      harmonicKey: 0
    };
  }

  return {
    waveformDetail: isFiniteNumber(value.waveformDetail) ? clamp(value.waveformDetail, 0, 1) : 0,
    spectralBands: isFiniteNumber(value.spectralBands) ? clamp(value.spectralBands, 0, 1) : 0,
    transientMarkers: isFiniteNumber(value.transientMarkers) ? clamp(value.transientMarkers, 0, 1) : 0,
    beatGrid: isFiniteNumber(value.beatGrid) ? clamp(value.beatGrid, 0, 1) : 0,
    harmonicKey: isFiniteNumber(value.harmonicKey) ? clamp(value.harmonicKey, 0, 1) : 0
  };
};

const asMusicalKey = (value: unknown): MusicalKeyEstimate | null => {
  if (!isRecord(value)) {
    return null;
  }
  const tonic = typeof value.tonic === 'string' ? value.tonic : '';
  if (!/^[A-G](#|b)?$/.test(tonic)) {
    return null;
  }
  if (value.mode !== 'major' && value.mode !== 'minor') {
    return null;
  }
  return {
    tonic,
    mode: value.mode,
    confidence: isFiniteNumber(value.confidence) ? clamp(value.confidence, 0, 1) : 0,
    chromaEnergy: isFiniteNumber(value.chromaEnergy) ? Math.max(0, value.chromaEnergy) : 0
  };
};

const asLoudness = (value: unknown): LoudnessAnalysis | null => {
  if (!isRecord(value)) {
    return null;
  }
  if (!isFiniteNumber(value.integratedRMSDb) || !isFiniteNumber(value.peakDb)) {
    return null;
  }
  return {
    integratedRMSDb: clamp(value.integratedRMSDb, -120, 12),
    integratedLUFS: isFiniteNumber(value.integratedLUFS) ? clamp(value.integratedLUFS, -120, 12) : null,
    peakDb: clamp(value.peakDb, -120, 12),
    truePeakDb: isFiniteNumber(value.truePeakDb) ? clamp(value.truePeakDb, -120, 12) : null,
    headroomDb: isFiniteNumber(value.headroomDb) ? clamp(value.headroomDb, 0, 120) : 0,
    crestFactorDb: isFiniteNumber(value.crestFactorDb) ? clamp(value.crestFactorDb, 0, 80) : 0,
    dynamicRangeDb: isFiniteNumber(value.dynamicRangeDb) ? clamp(value.dynamicRangeDb, 0, 80) : 0,
    loudnessRangeLU: isFiniteNumber(value.loudnessRangeLU) ? clamp(value.loudnessRangeLU, 0, 80) : null,
    measurement: typeof value.measurement === 'string' && value.measurement.length > 0 ? value.measurement : null,
    confidence: isFiniteNumber(value.confidence) ? clamp(value.confidence, 0, 1) : 0
  };
};

const asStereo = (value: unknown): StereoAnalysis | null => {
  if (!isRecord(value) || !isFiniteNumber(value.channelCount)) {
    return null;
  }
  return {
    channelCount: Math.max(1, Math.floor(value.channelCount)),
    leftPeakDb: isFiniteNumber(value.leftPeakDb) ? clamp(value.leftPeakDb, -120, 12) : null,
    rightPeakDb: isFiniteNumber(value.rightPeakDb) ? clamp(value.rightPeakDb, -120, 12) : null,
    leftRMSDb: isFiniteNumber(value.leftRMSDb) ? clamp(value.leftRMSDb, -120, 12) : null,
    rightRMSDb: isFiniteNumber(value.rightRMSDb) ? clamp(value.rightRMSDb, -120, 12) : null,
    stereoWidth: isFiniteNumber(value.stereoWidth) ? clamp(value.stereoWidth, 0, 1) : 0,
    phaseCorrelation: isFiniteNumber(value.phaseCorrelation) ? clamp(value.phaseCorrelation, -1, 1) : 1,
    midSideBalance: isFiniteNumber(value.midSideBalance) ? clamp(value.midSideBalance, 0, 12) : 1,
    confidence: isFiniteNumber(value.confidence) ? clamp(value.confidence, 0, 1) : 0
  };
};

const asTrackFileRevision = (value: unknown): TrackFileRevision | null => {
  if (!isRecord(value)) {
    return null;
  }
  if (!isFiniteNumber(value.sizeBytes) || !isFiniteNumber(value.mtimeMs)) {
    return null;
  }

  return {
    sizeBytes: Math.max(0, value.sizeBytes),
    mtimeMs: Math.max(0, value.mtimeMs)
  };
};

export const sanitizeTrackAnalysis = (
  trackId: string,
  candidate?: Partial<TrackAnalysis> | null
): TrackAnalysis => {
  const confidence = isFiniteNumber(candidate?.analysisConfidence)
    ? candidate.analysisConfidence
    : 0;
  const waveformDetail = asWaveformDetail(candidate?.waveformDetail);
  const spectralBands = asSpectralBands(candidate?.spectralBands);
  const transientMarkers = asTransientMarkers(candidate?.transientMarkers);
  const sourceSchemaVersion = isFiniteNumber(candidate?.schemaVersion)
    ? Math.floor(candidate.schemaVersion)
    : 1;
  const analysisWarnings = asAnalysisWarnings(candidate?.analysisWarnings);
  const quality = asAnalysisQuality(candidate?.analysisQuality);
  const hasPlannerReadyDetail =
    waveformDetail.length > 0 &&
    quality.waveformDetail >= PLANNER_READY_MIN_WAVEFORM_DETAIL_QUALITY &&
    quality.beatGrid >= PLANNER_READY_MIN_BEAT_GRID_QUALITY;
  const upgradeWarnings =
    (sourceSchemaVersion < TRACK_ANALYSIS_SCHEMA_VERSION || !hasPlannerReadyDetail)
      ? Array.from(new Set([...analysisWarnings, 'analysis_upgrade_available' as const]))
      : analysisWarnings;

  return {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    trackId,
    generatedAt:
      typeof candidate?.generatedAt === 'string' && candidate.generatedAt.length > 0
        ? candidate.generatedAt
        : new Date().toISOString(),
    source:
      candidate?.source === 'metadata' ||
      candidate?.source === 'derived' ||
      candidate?.source === 'external'
        ? candidate.source
        : 'derived',
    fileRevision: asTrackFileRevision(candidate?.fileRevision),
    bpm: isFiniteNumber(candidate?.bpm) ? candidate.bpm : null,
    bpmConfidence: isFiniteNumber(candidate?.bpmConfidence)
      ? clamp(candidate.bpmConfidence, 0, 1)
      : confidence,
    beatGridSec: asNumberList(candidate?.beatGridSec),
    downbeatsSec: asNumberList(candidate?.downbeatsSec),
    barGrid: asBarMarkers(candidate?.barGrid),
    phraseMarkers: asPhraseMarkers(candidate?.phraseMarkers),
    introCueSec: isFiniteNumber(candidate?.introCueSec) ? candidate.introCueSec : null,
    outroCueSec: isFiniteNumber(candidate?.outroCueSec) ? candidate.outroCueSec : null,
    energyProfile: asNumberList(candidate?.energyProfile),
    waveformPeaks: asWaveformPeaks(candidate?.waveformPeaks),
    waveformDetail,
    spectralBands,
    transientMarkers,
    cueCandidates: asCueCandidates(candidate?.cueCandidates),
    musicalKey: asMusicalKey(candidate?.musicalKey),
    loudness: asLoudness(candidate?.loudness),
    stereo: asStereo(candidate?.stereo),
    analysisConfidence: clamp(confidence, 0, 1),
    analysisQuality: quality,
    analysisWarnings: upgradeWarnings
  };
};

export const hasPlannerReadyTrackAnalysis = (analysis: TrackAnalysis | null | undefined): boolean => {
  if (!analysis) {
    return false;
  }

  return (
    analysis.waveformDetail.length > 0 &&
    analysis.energyProfile.length > 0 &&
    analysis.barGrid.length > 0 &&
    analysis.analysisQuality.waveformDetail >= PLANNER_READY_MIN_WAVEFORM_DETAIL_QUALITY &&
    analysis.analysisQuality.beatGrid >= PLANNER_READY_MIN_BEAT_GRID_QUALITY &&
    analysis.bpmConfidence >= PLANNER_READY_MIN_BPM_CONFIDENCE &&
    !analysis.analysisWarnings.includes('analysis_upgrade_available') &&
    !analysis.analysisWarnings.includes('bpm_low_confidence') &&
    !analysis.analysisWarnings.includes('flat_energy')
  );
};
