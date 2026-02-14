import { PlayerSettings } from './types';

export const DEFAULT_SETTINGS: PlayerSettings = {
  fadeDurationSec: 8,
  masterGain: 0.9,
  predecodeLeadSec: 20,
  repeatAll: true
};

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

export const sanitizeSettings = (
  candidate?: Partial<PlayerSettings>
): PlayerSettings => {
  const merged: PlayerSettings = {
    ...DEFAULT_SETTINGS,
    ...candidate
  };

  return {
    fadeDurationSec: clamp(merged.fadeDurationSec, 2, 20),
    masterGain: clamp(merged.masterGain, 0, 1),
    predecodeLeadSec: clamp(merged.predecodeLeadSec, 3, 40),
    repeatAll: merged.repeatAll
  };
};
