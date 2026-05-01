import { TrackAnalysis } from './analysis';
import { MixPlan } from './mixPlan';
import { AiDjMode, PlayerSettings, Track } from './types';
import { isAiAgentProfileConfigured, resolveActiveAiAgentProfile } from './settings';

export const PLANNER_SCHEMA_VERSION = 1;

export interface PlannerCliConfig {
  command: string;
  args: string[];
  timeoutMs: number;
  profileId?: string;
  profileName?: string;
}

export interface PlannerTrackSnapshot {
  id: string;
  title: string;
  durationSec: number;
  bpm: number | null;
}

export interface PlannerPlaybackSnapshot {
  elapsedSec: number;
  remainingSec: number;
}

export interface PlannerSettingsSnapshot {
  fadeDurationSec: number;
  aiDjMode: AiDjMode;
}

export interface PlannerRequest {
  schemaVersion: typeof PLANNER_SCHEMA_VERSION;
  currentTrack: PlannerTrackSnapshot;
  nextTrack: PlannerTrackSnapshot;
  currentPlayback: PlannerPlaybackSnapshot;
  analysis: {
    current: TrackAnalysis | null;
    next: TrackAnalysis | null;
  };
  settings: PlannerSettingsSnapshot;
}

export interface PlannerResponse {
  schemaVersion: typeof PLANNER_SCHEMA_VERSION;
  mixPlan: MixPlan | null;
  error: string | null;
}

export interface RequestMixPlanInput {
  currentTrack: Track;
  nextTrack: Track;
  currentPlayback: {
    elapsedSec: number;
  };
  settingsOverride?: Partial<PlayerSettings>;
}

export interface RequestMixPlanResult {
  plan: MixPlan | null;
  source: 'cli' | 'fallback';
  reason: string | null;
  request: PlannerRequest;
  response: PlannerResponse | null;
  analysis: {
    current: TrackAnalysis | null;
    next: TrackAnalysis | null;
  };
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

export const toPlannerCliConfig = (
  settings: Pick<
    PlayerSettings,
    | 'plannerCommand'
    | 'plannerArgs'
    | 'plannerTimeoutMs'
    | 'aiAgentProfiles'
    | 'activeAiAgentProfileId'
  >
): PlannerCliConfig => {
  const activeProfile = resolveActiveAiAgentProfile(settings);
  if (activeProfile) {
    return {
      command: activeProfile.command.trim(),
      args: activeProfile.args,
      timeoutMs: activeProfile.timeoutMs,
      profileId: activeProfile.id,
      profileName: activeProfile.name
    };
  }

  return {
    command: settings.plannerCommand.trim(),
    args: settings.plannerArgs,
    timeoutMs: settings.plannerTimeoutMs
  };
};

export const buildPlannerTrackSnapshot = (track: Track): PlannerTrackSnapshot => {
  return {
    id: track.id,
    title: track.title,
    durationSec: track.durationSec,
    bpm: typeof track.bpm === 'number' && Number.isFinite(track.bpm) ? track.bpm : null
  };
};

export const buildPlannerRequest = (input: {
  currentTrack: Track;
  nextTrack: Track;
  elapsedSec: number;
  currentAnalysis: TrackAnalysis | null;
  nextAnalysis: TrackAnalysis | null;
  settings: Pick<PlayerSettings, 'fadeDurationSec' | 'aiDjMode'>;
}): PlannerRequest => {
  const remainingSec = Math.max(0, input.currentTrack.durationSec - input.elapsedSec);
  return {
    schemaVersion: PLANNER_SCHEMA_VERSION,
    currentTrack: buildPlannerTrackSnapshot(input.currentTrack),
    nextTrack: buildPlannerTrackSnapshot(input.nextTrack),
    currentPlayback: {
      elapsedSec: input.elapsedSec,
      remainingSec
    },
    analysis: {
      current: input.currentAnalysis,
      next: input.nextAnalysis
    },
    settings: {
      fadeDurationSec: input.settings.fadeDurationSec,
      aiDjMode: input.settings.aiDjMode
    }
  };
};

export const parsePlannerResponseJson = (
  payload: string
): { response: PlannerResponse | null; reason: string | null } => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(payload);
  } catch {
    return { response: null, reason: 'planner_response_invalid_json' };
  }

  if (!isRecord(parsed)) {
    return { response: null, reason: 'planner_response_not_object' };
  }

  if (parsed.schemaVersion !== PLANNER_SCHEMA_VERSION) {
    return { response: null, reason: 'planner_response_invalid_schema_version' };
  }

  const mixPlan =
    parsed.mixPlan === null || isRecord(parsed.mixPlan)
      ? (parsed.mixPlan as MixPlan | null)
      : null;
  if (parsed.mixPlan !== null && mixPlan === null) {
    return { response: null, reason: 'planner_response_invalid_mix_plan_shape' };
  }

  if (parsed.error !== null && typeof parsed.error !== 'string' && parsed.error !== undefined) {
    return { response: null, reason: 'planner_response_invalid_error' };
  }

  return {
    response: {
      schemaVersion: PLANNER_SCHEMA_VERSION,
      mixPlan,
      error: typeof parsed.error === 'string' ? parsed.error : null
    },
    reason: null
  };
};

export const isPlannerCommandConfigured = (
  settings: Pick<
    PlayerSettings,
    'plannerCommand' | 'aiAgentProfiles' | 'activeAiAgentProfileId'
  >
): boolean => {
  const activeProfile = resolveActiveAiAgentProfile(settings);
  if (activeProfile) {
    return isAiAgentProfileConfigured(activeProfile);
  }

  return settings.plannerCommand.trim().length > 0;
};

export const isFinitePlaybackElapsed = (value: unknown): value is number => {
  return isFiniteNumber(value);
};
