import { PlayerSettings } from './types';

export const DEFAULT_SETTINGS: PlayerSettings = {
  fadeDurationSec: 8,
  masterGain: 0.9,
  predecodeLeadSec: 20,
  repeatAll: true,
  decodeTimeoutDurationWeightMs: 20,
  decodeTimeoutSizeWeightMs: 200,
  aiDjEnabled: false,
  aiDjMode: 'safe',
  plannerCommand: '',
  plannerArgs: [],
  plannerTimeoutMs: 4000
};

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const isStringArray = (value: unknown): value is string[] => {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
};

export const sanitizeSettings = (
  candidate?: Partial<PlayerSettings>
): PlayerSettings => {
  const merged = {
    ...DEFAULT_SETTINGS,
    ...(candidate ?? {})
  } as Partial<PlayerSettings>;

  const fadeDurationSec = isFiniteNumber(merged.fadeDurationSec)
    ? merged.fadeDurationSec
    : DEFAULT_SETTINGS.fadeDurationSec;
  const masterGain = isFiniteNumber(merged.masterGain)
    ? merged.masterGain
    : DEFAULT_SETTINGS.masterGain;
  const predecodeLeadSec = isFiniteNumber(merged.predecodeLeadSec)
    ? merged.predecodeLeadSec
    : DEFAULT_SETTINGS.predecodeLeadSec;
  const repeatAll =
    typeof merged.repeatAll === 'boolean'
      ? merged.repeatAll
      : DEFAULT_SETTINGS.repeatAll;
  const decodeTimeoutDurationWeightMs = isFiniteNumber(
    merged.decodeTimeoutDurationWeightMs
  )
    ? merged.decodeTimeoutDurationWeightMs
    : DEFAULT_SETTINGS.decodeTimeoutDurationWeightMs;
  const decodeTimeoutSizeWeightMs = isFiniteNumber(merged.decodeTimeoutSizeWeightMs)
    ? merged.decodeTimeoutSizeWeightMs
    : DEFAULT_SETTINGS.decodeTimeoutSizeWeightMs;
  const aiDjEnabled =
    typeof merged.aiDjEnabled === 'boolean'
      ? merged.aiDjEnabled
      : DEFAULT_SETTINGS.aiDjEnabled;
  const aiDjMode =
    merged.aiDjMode === 'safe' ||
    merged.aiDjMode === 'balanced' ||
    merged.aiDjMode === 'adventurous'
      ? merged.aiDjMode
      : DEFAULT_SETTINGS.aiDjMode;
  const plannerCommand =
    typeof merged.plannerCommand === 'string'
      ? merged.plannerCommand
      : DEFAULT_SETTINGS.plannerCommand;
  const plannerArgs = isStringArray(merged.plannerArgs)
    ? merged.plannerArgs
    : DEFAULT_SETTINGS.plannerArgs;
  const plannerTimeoutMs = isFiniteNumber(merged.plannerTimeoutMs)
    ? merged.plannerTimeoutMs
    : DEFAULT_SETTINGS.plannerTimeoutMs;

  return {
    fadeDurationSec: clamp(fadeDurationSec, 2, 20),
    masterGain: clamp(masterGain, 0, 1),
    predecodeLeadSec: clamp(predecodeLeadSec, 3, 40),
    repeatAll,
    decodeTimeoutDurationWeightMs: clamp(decodeTimeoutDurationWeightMs, 0, 80),
    decodeTimeoutSizeWeightMs: clamp(decodeTimeoutSizeWeightMs, 0, 1200),
    aiDjEnabled,
    aiDjMode,
    plannerCommand: plannerCommand.trim(),
    plannerArgs,
    plannerTimeoutMs: clamp(plannerTimeoutMs, 500, 30_000)
  };
};
