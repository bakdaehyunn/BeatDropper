export const TRACK_ANALYSIS_SCHEMA_VERSION = 1;

export type TrackAnalysisSource = 'metadata' | 'derived' | 'external';

export interface TrackAnalysis {
  schemaVersion: typeof TRACK_ANALYSIS_SCHEMA_VERSION;
  trackId: string;
  generatedAt: string;
  source: TrackAnalysisSource;
  bpm: number | null;
  beatGridSec: number[];
  downbeatsSec: number[];
  introCueSec: number | null;
  outroCueSec: number | null;
  energyProfile: number[];
  analysisConfidence: number;
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

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

export const sanitizeTrackAnalysis = (
  trackId: string,
  candidate?: Partial<TrackAnalysis> | null
): TrackAnalysis => {
  const confidence = isFiniteNumber(candidate?.analysisConfidence)
    ? candidate.analysisConfidence
    : 0;

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
    beatGridSec: asNumberList(candidate?.beatGridSec),
    downbeatsSec: asNumberList(candidate?.downbeatsSec),
    introCueSec: isFiniteNumber(candidate?.introCueSec) ? candidate.introCueSec : null,
    outroCueSec: isFiniteNumber(candidate?.outroCueSec) ? candidate.outroCueSec : null,
    energyProfile: asNumberList(candidate?.energyProfile),
    analysisConfidence: clamp(confidence, 0, 1)
  };
};
