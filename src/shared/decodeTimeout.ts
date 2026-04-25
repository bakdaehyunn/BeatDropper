import { PlayerSettings } from './types';

export const MAX_DURATION_TIMEOUT_BONUS_MS = 1800;
export const MAX_SIZE_TIMEOUT_BONUS_MS = 1800;

export const estimateAdaptiveDecodeTimeoutMs = (
  settings: PlayerSettings,
  baseTimeoutMs: number,
  trackDurationSec: number,
  trackSizeBytes: number
): number => {
  const safeDurationSec = Math.max(0, trackDurationSec);
  const durationBonusMs = Math.min(
    MAX_DURATION_TIMEOUT_BONUS_MS,
    safeDurationSec * settings.decodeTimeoutDurationWeightMs
  );

  const safeSizeBytes = Math.max(0, trackSizeBytes);
  const sizeBonusMs = Math.min(
    MAX_SIZE_TIMEOUT_BONUS_MS,
    (safeSizeBytes / (1024 * 1024)) * settings.decodeTimeoutSizeWeightMs
  );

  return Math.round(baseTimeoutMs + durationBonusMs + sizeBonusMs);
};
