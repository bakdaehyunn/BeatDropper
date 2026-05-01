export const TRACK_ANALYSIS_SCHEMA_VERSION = 3;

export type TrackAnalysisSource = 'metadata' | 'derived' | 'external';
export type CueCandidateType =
  | 'intro'
  | 'first_downbeat'
  | 'outro'
  | 'low_energy_break'
  | 'high_energy_drop';
export type AnalysisWarning =
  | 'bpm_unavailable'
  | 'bpm_low_confidence'
  | 'beat_grid_estimated'
  | 'short_track'
  | 'flat_energy'
  | 'analysis_upgrade_available';

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
}

export interface TrackAnalysis {
  schemaVersion: typeof TRACK_ANALYSIS_SCHEMA_VERSION;
  trackId: string;
  generatedAt: string;
  source: TrackAnalysisSource;
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
  analysisConfidence: number;
  analysisQuality: AnalysisQuality;
  analysisWarnings: AnalysisWarning[];
}

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
        label: typeof item.label === 'string' && item.label.length > 0 ? item.label : type
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
    item === 'beat_grid_estimated' ||
    item === 'short_track' ||
    item === 'flat_energy' ||
    item === 'analysis_upgrade_available'
  );
};

const asAnalysisQuality = (value: unknown): AnalysisQuality => {
  if (!isRecord(value)) {
    return {
      waveformDetail: 0,
      spectralBands: 0,
      transientMarkers: 0,
      beatGrid: 0
    };
  }

  return {
    waveformDetail: isFiniteNumber(value.waveformDetail) ? clamp(value.waveformDetail, 0, 1) : 0,
    spectralBands: isFiniteNumber(value.spectralBands) ? clamp(value.spectralBands, 0, 1) : 0,
    transientMarkers: isFiniteNumber(value.transientMarkers) ? clamp(value.transientMarkers, 0, 1) : 0,
    beatGrid: isFiniteNumber(value.beatGrid) ? clamp(value.beatGrid, 0, 1) : 0
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
  const upgradeWarnings =
    sourceSchemaVersion < TRACK_ANALYSIS_SCHEMA_VERSION && waveformDetail.length === 0
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
    analysisConfidence: clamp(confidence, 0, 1),
    analysisQuality: asAnalysisQuality(candidate?.analysisQuality),
    analysisWarnings: upgradeWarnings
  };
};
