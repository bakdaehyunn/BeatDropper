import { AiAgentProfile, PlayerSettings } from './types';

export const CODEX_AGENT_PROFILE_ID = 'codex';

export const BUILT_IN_AI_AGENT_PROFILES: AiAgentProfile[] = [
  {
    id: CODEX_AGENT_PROFILE_ID,
    name: 'Codex',
    kind: 'cli',
    command: 'node',
    args: ['scripts/codex-mix-planner.cjs'],
    timeoutMs: 20_000,
    enabled: true
  }
];

const DEFAULT_ACTIVE_AI_AGENT_PROFILE =
  BUILT_IN_AI_AGENT_PROFILES.find((profile) => profile.id === CODEX_AGENT_PROFILE_ID) ??
  BUILT_IN_AI_AGENT_PROFILES[0];

export const DEFAULT_SETTINGS: PlayerSettings = {
  fadeDurationSec: 8,
  masterGain: 0.9,
  predecodeLeadSec: 20,
  repeatAll: true,
  decodeTimeoutDurationWeightMs: 20,
  decodeTimeoutSizeWeightMs: 200,
  aiDjEnabled: false,
  aiDjMode: 'safe',
  aiAgentProfiles: BUILT_IN_AI_AGENT_PROFILES,
  activeAiAgentProfileId: DEFAULT_ACTIVE_AI_AGENT_PROFILE.id,
  plannerCommand: DEFAULT_ACTIVE_AI_AGENT_PROFILE.command,
  plannerArgs: DEFAULT_ACTIVE_AI_AGENT_PROFILE.args,
  plannerTimeoutMs: DEFAULT_ACTIVE_AI_AGENT_PROFILE.timeoutMs
};

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const cloneProfile = (profile: AiAgentProfile): AiAgentProfile => ({
  ...profile,
  args: [...profile.args]
});

const getDefaultCodexProfile = (): AiAgentProfile => cloneProfile(DEFAULT_ACTIVE_AI_AGENT_PROFILE);

const mergeAiAgentProfiles = (): AiAgentProfile[] => {
  return [getDefaultCodexProfile()];
};

export const isAiAgentProfileConfigured = (profile: AiAgentProfile | null): boolean => {
  return Boolean(profile?.enabled && profile.command.trim().length > 0);
};

export const resolveActiveAiAgentProfile = (
  settings: Pick<PlayerSettings, 'aiAgentProfiles' | 'activeAiAgentProfileId'>
): AiAgentProfile | null => {
  return (
    settings.aiAgentProfiles.find((profile) => profile.id === CODEX_AGENT_PROFILE_ID) ??
    getDefaultCodexProfile()
  );
};

const selectActiveAiAgentProfileId = (
  profiles: AiAgentProfile[]
): string => {
  return (
    profiles.find((profile) => profile.id === CODEX_AGENT_PROFILE_ID)?.id ??
    DEFAULT_SETTINGS.activeAiAgentProfileId
  );
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
  const aiAgentProfiles = mergeAiAgentProfiles();
  const activeAiAgentProfileId = selectActiveAiAgentProfileId(aiAgentProfiles);
  const activeAiAgentProfile =
    aiAgentProfiles.find((profile) => profile.id === activeAiAgentProfileId) ??
    DEFAULT_ACTIVE_AI_AGENT_PROFILE;

  return {
    fadeDurationSec: clamp(fadeDurationSec, 2, 20),
    masterGain: clamp(masterGain, 0, 1),
    predecodeLeadSec: clamp(predecodeLeadSec, 3, 40),
    repeatAll,
    decodeTimeoutDurationWeightMs: clamp(decodeTimeoutDurationWeightMs, 0, 80),
    decodeTimeoutSizeWeightMs: clamp(decodeTimeoutSizeWeightMs, 0, 1200),
    aiDjEnabled,
    aiDjMode,
    aiAgentProfiles,
    activeAiAgentProfileId,
    plannerCommand: activeAiAgentProfile.command.trim(),
    plannerArgs: [...activeAiAgentProfile.args],
    plannerTimeoutMs: activeAiAgentProfile.timeoutMs
  };
};
