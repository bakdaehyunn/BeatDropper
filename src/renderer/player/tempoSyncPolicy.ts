const MIN_BPM = 60;
const MAX_BPM = 200;
const DEFAULT_MIN_RATE = 0.94;
const DEFAULT_MAX_RATE = 1.06;
const DEFAULT_MAX_RESIDUAL_MISMATCH_PCT = 4;

export interface TempoSyncOptions {
  minRate?: number;
  maxRate?: number;
  maxResidualMismatchPct?: number;
}

interface TempoSyncBase {
  desiredRate: number;
  targetRate: number;
  residualMismatchPct: number;
}

export interface TempoSyncApplied extends TempoSyncBase {
  mode: 'apply';
}

export interface TempoSyncSkipped extends TempoSyncBase {
  mode: 'skip';
  reason: 'missing_bpm' | 'invalid_bpm' | 'residual_too_high';
}

export type TempoSyncDecision = TempoSyncApplied | TempoSyncSkipped;

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const isBpmValid = (value: number): boolean => {
  return Number.isFinite(value) && value >= MIN_BPM && value <= MAX_BPM;
};

export const resolveTempoSyncDecision = (
  currentBpm: number | null | undefined,
  nextBpm: number | null | undefined,
  options?: TempoSyncOptions
): TempoSyncDecision => {
  const minRate = options?.minRate ?? DEFAULT_MIN_RATE;
  const maxRate = options?.maxRate ?? DEFAULT_MAX_RATE;
  const maxResidualMismatchPct =
    options?.maxResidualMismatchPct ?? DEFAULT_MAX_RESIDUAL_MISMATCH_PCT;

  if (currentBpm == null || nextBpm == null) {
    return {
      mode: 'skip',
      reason: 'missing_bpm',
      desiredRate: 1,
      targetRate: 1,
      residualMismatchPct: 0
    };
  }

  if (!isBpmValid(currentBpm) || !isBpmValid(nextBpm)) {
    return {
      mode: 'skip',
      reason: 'invalid_bpm',
      desiredRate: 1,
      targetRate: 1,
      residualMismatchPct: 0
    };
  }

  const desiredRate = currentBpm / nextBpm;
  const targetRate = clamp(desiredRate, minRate, maxRate);
  const compensatedNextBpm = nextBpm * targetRate;
  const residualMismatchPct =
    Math.abs(currentBpm - compensatedNextBpm) / currentBpm * 100;

  if (residualMismatchPct > maxResidualMismatchPct) {
    return {
      mode: 'skip',
      reason: 'residual_too_high',
      desiredRate,
      targetRate,
      residualMismatchPct
    };
  }

  return {
    mode: 'apply',
    desiredRate,
    targetRate,
    residualMismatchPct
  };
};
