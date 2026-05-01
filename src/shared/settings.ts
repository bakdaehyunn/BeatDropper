import { AiAgentProfile, PlayerSettings } from './types';

export const CODEX_AGENT_PROFILE_ID = 'codex';
export const HEURISTIC_AGENT_PROFILE_ID = 'local-heuristic';
export const CUSTOM_AGENT_PROFILE_ID = 'custom-cli';

export const BUILT_IN_AI_AGENT_PROFILES: AiAgentProfile[] = [
  {
    id: CODEX_AGENT_PROFILE_ID,
    name: 'Codex CLI',
    kind: 'cli',
    command: 'node',
    args: ['scripts/codex-mix-planner.cjs'],
    timeoutMs: 20_000,
    enabled: true
  },
  {
    id: HEURISTIC_AGENT_PROFILE_ID,
    name: 'Local Heuristic',
    kind: 'cli',
    command: 'node',
    args: ['scripts/heuristic-mix-planner.cjs'],
    timeoutMs: 4000,
    enabled: true
  },
  {
    id: CUSTOM_AGENT_PROFILE_ID,
    name: 'Custom CLI',
    kind: 'cli',
    command: '',
    args: [],
    timeoutMs: 4000,
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

const isStringArray = (value: unknown): value is string[] => {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const sanitizePlannerArgs = (value: unknown): string[] => {
  return isStringArray(value) ? value.map((item) => item.trim()).filter(Boolean) : [];
};

const isSameCommandShape = (
  profile: Pick<AiAgentProfile, 'command' | 'args'>,
  command: string,
  args: string[]
): boolean => {
  return (
    profile.command === command &&
    profile.args.length === args.length &&
    profile.args.every((arg, index) => arg === args[index])
  );
};

const cloneProfile = (profile: AiAgentProfile): AiAgentProfile => ({
  ...profile,
  args: [...profile.args]
});

const sanitizeAiAgentProfile = (
  value: unknown,
  fallback?: AiAgentProfile
): AiAgentProfile | null => {
  if (!isRecord(value)) {
    return fallback ? cloneProfile(fallback) : null;
  }

  const idSource = typeof value.id === 'string' ? value.id.trim() : fallback?.id ?? '';
  if (!idSource) {
    return null;
  }

  const nameSource =
    typeof value.name === 'string' && value.name.trim().length > 0
      ? value.name.trim()
      : fallback?.name ?? idSource;
  const command =
    typeof value.command === 'string'
      ? value.command.trim()
      : fallback?.command ?? '';
  const args =
    'args' in value
      ? sanitizePlannerArgs(value.args)
      : fallback
        ? [...fallback.args]
        : [];
  const timeoutMs = isFiniteNumber(value.timeoutMs)
    ? value.timeoutMs
    : fallback?.timeoutMs ?? DEFAULT_SETTINGS.plannerTimeoutMs;
  const enabled =
    typeof value.enabled === 'boolean' ? value.enabled : fallback?.enabled ?? true;

  return {
    id: idSource,
    name: nameSource,
    kind: 'cli',
    command,
    args,
    timeoutMs: clamp(timeoutMs, 500, 30_000),
    enabled
  };
};

const mergeAiAgentProfiles = (
  candidateProfiles: unknown,
  legacyCommand: string,
  legacyArgs: string[],
  legacyTimeoutMs: number
): AiAgentProfile[] => {
  const byId = new Map<string, AiAgentProfile>();

  for (const profile of BUILT_IN_AI_AGENT_PROFILES) {
    byId.set(profile.id, cloneProfile(profile));
  }

  if (Array.isArray(candidateProfiles)) {
    for (const value of candidateProfiles) {
      const id = isRecord(value) && typeof value.id === 'string' ? value.id.trim() : '';
      const fallback = id ? byId.get(id) : undefined;
      const profile = sanitizeAiAgentProfile(value, fallback);
      if (profile) {
        byId.set(profile.id, profile);
      }
    }
  } else if (legacyCommand) {
    const matchingBuiltIn = BUILT_IN_AI_AGENT_PROFILES.find((profile) =>
      isSameCommandShape(profile, legacyCommand, legacyArgs)
    );
    if (matchingBuiltIn) {
      byId.set(matchingBuiltIn.id, {
        ...cloneProfile(matchingBuiltIn),
        timeoutMs: legacyTimeoutMs
      });
    } else {
      byId.set(CUSTOM_AGENT_PROFILE_ID, {
        id: CUSTOM_AGENT_PROFILE_ID,
        name: 'Custom CLI',
        kind: 'cli',
        command: legacyCommand,
        args: legacyArgs,
        timeoutMs: legacyTimeoutMs,
        enabled: true
      });
    }
  }

  return Array.from(byId.values());
};

export const isAiAgentProfileConfigured = (profile: AiAgentProfile | null): boolean => {
  return Boolean(profile?.enabled && profile.command.trim().length > 0);
};

export const resolveActiveAiAgentProfile = (
  settings: Pick<PlayerSettings, 'aiAgentProfiles' | 'activeAiAgentProfileId'>
): AiAgentProfile | null => {
  const active =
    settings.aiAgentProfiles.find(
      (profile) => profile.id === settings.activeAiAgentProfileId
    ) ?? null;
  if (active) {
    return active;
  }

  return settings.aiAgentProfiles.find(isAiAgentProfileConfigured) ?? null;
};

const selectActiveAiAgentProfileId = (
  profiles: AiAgentProfile[],
  candidateActiveId: unknown,
  legacyCommand: string,
  legacyArgs: string[]
): string => {
  if (typeof candidateActiveId === 'string' && profiles.some((profile) => profile.id === candidateActiveId.trim())) {
    return candidateActiveId.trim();
  }

  if (legacyCommand) {
    const matchingProfile = profiles.find((profile) =>
      isSameCommandShape(profile, legacyCommand, legacyArgs)
    );
    if (matchingProfile) {
      return matchingProfile.id;
    }
  }

  return DEFAULT_SETTINGS.activeAiAgentProfileId;
};

export const sanitizeSettings = (
  candidate?: Partial<PlayerSettings>
): PlayerSettings => {
  const explicitProfiles = candidate && 'aiAgentProfiles' in candidate
    ? candidate.aiAgentProfiles
    : undefined;
  const explicitActiveProfileId = candidate && 'activeAiAgentProfileId' in candidate
    ? candidate.activeAiAgentProfileId
    : undefined;
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
    ? sanitizePlannerArgs(merged.plannerArgs)
    : DEFAULT_SETTINGS.plannerArgs;
  const plannerTimeoutMs = isFiniteNumber(merged.plannerTimeoutMs)
    ? merged.plannerTimeoutMs
    : DEFAULT_SETTINGS.plannerTimeoutMs;
  const clampedPlannerTimeoutMs = clamp(plannerTimeoutMs, 500, 30_000);
  const aiAgentProfiles = mergeAiAgentProfiles(
    explicitProfiles,
    plannerCommand.trim(),
    plannerArgs,
    clampedPlannerTimeoutMs
  );
  const activeAiAgentProfileId = selectActiveAiAgentProfileId(
    aiAgentProfiles,
    explicitActiveProfileId,
    plannerCommand.trim(),
    plannerArgs
  );
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
