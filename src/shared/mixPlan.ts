export type MixStyle = 'smooth_blend' | 'energy_swap' | 'hard_cut';

export interface MixTempoSyncPlan {
  enabled: boolean;
  targetRate: number | null;
}

export interface MixPlan {
  transitionStartSec: number;
  transitionEndSec: number;
  nextTrackStartOffsetSec: number;
  style: MixStyle;
  confidence: number;
  reasoningSummary: string | null;
  tempoSync: MixTempoSyncPlan;
}

export interface MixPlanValidationContext {
  currentPlaybackElapsedSec: number;
  currentTrackDurationSec: number;
  nextTrackDurationSec: number;
  maxFadeDurationSec: number;
}

export interface MixPlanValidationResult {
  plan: MixPlan | null;
  reason: string | null;
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

export const validateAndClampMixPlan = (
  candidate: unknown,
  context: MixPlanValidationContext
): MixPlanValidationResult => {
  if (!isRecord(candidate)) {
    return { plan: null, reason: 'mix_plan_not_object' };
  }

  if (
    !isFiniteNumber(candidate.transitionStartSec) ||
    !isFiniteNumber(candidate.transitionEndSec) ||
    !isFiniteNumber(candidate.nextTrackStartOffsetSec)
  ) {
    return { plan: null, reason: 'mix_plan_missing_timing' };
  }

  const currentTrackDurationSec = Math.max(0, context.currentTrackDurationSec);
  const nextTrackDurationSec = Math.max(0, context.nextTrackDurationSec);
  const maxFadeDurationSec = Math.max(0.25, context.maxFadeDurationSec);
  const elapsedSec = clamp(
    context.currentPlaybackElapsedSec,
    0,
    currentTrackDurationSec
  );

  let transitionStartSec = clamp(
    candidate.transitionStartSec,
    elapsedSec,
    currentTrackDurationSec
  );
  let transitionEndSec = clamp(
    candidate.transitionEndSec,
    transitionStartSec,
    currentTrackDurationSec
  );

  if (transitionEndSec - transitionStartSec > maxFadeDurationSec) {
    transitionStartSec = Math.max(elapsedSec, transitionEndSec - maxFadeDurationSec);
  }

  if (transitionEndSec - transitionStartSec < 0.05) {
    return { plan: null, reason: 'mix_plan_window_too_small' };
  }

  const nextTrackStartOffsetSec = clamp(
    candidate.nextTrackStartOffsetSec,
    0,
    nextTrackDurationSec
  );

  const style =
    candidate.style === 'smooth_blend' ||
    candidate.style === 'energy_swap' ||
    candidate.style === 'hard_cut'
      ? candidate.style
      : 'smooth_blend';

  const confidence = isFiniteNumber(candidate.confidence)
    ? clamp(candidate.confidence, 0, 1)
    : 0.5;

  const reasoningSummary =
    typeof candidate.reasoningSummary === 'string'
      ? candidate.reasoningSummary
      : null;

  let tempoSync: MixTempoSyncPlan = {
    enabled: false,
    targetRate: null
  };
  if (isRecord(candidate.tempoSync) && candidate.tempoSync.enabled === true) {
    const targetRate = isFiniteNumber(candidate.tempoSync.targetRate)
      ? clamp(candidate.tempoSync.targetRate, 0.85, 1.15)
      : null;
    tempoSync = {
      enabled: targetRate !== null,
      targetRate
    };
  }

  return {
    plan: {
      transitionStartSec,
      transitionEndSec,
      nextTrackStartOffsetSec,
      style,
      confidence,
      reasoningSummary,
      tempoSync
    },
    reason: null
  };
};
