import { TrackAnalysis } from './analysis';
import type { MixPlanQualityGrade, MixPlanQualityResult } from './mixPlanQuality';
import { RequestMixPlanResult } from './plannerContract';
import { resolveActiveAiAgentProfile } from './settings';
import { PlayerSettings, Track } from './types';

export const MIX_PLAN_FAILED_CACHE_COOLDOWN_MS = 30_000;

export type MixPlanCacheEntryStatus = 'ready' | 'failed';

export interface MixPlanCacheEntry {
  key: string;
  currentTrackId: string;
  nextTrackId: string;
  status: MixPlanCacheEntryStatus;
  createdAtMs: number;
  result: RequestMixPlanResult | null;
  quality: MixPlanQualityResult | null;
  error: string | null;
}

export type MixPlanCacheStore = Record<string, MixPlanCacheEntry>;

export interface MixPlanCacheKeyInput {
  currentTrack: Track;
  nextTrack: Track;
  currentAnalysis: TrackAnalysis | null;
  nextAnalysis: TrackAnalysis | null;
  settings: Pick<
    PlayerSettings,
    | 'aiAgentProfiles'
    | 'activeAiAgentProfileId'
    | 'aiDjMode'
    | 'fadeDurationSec'
    | 'plannerCommand'
    | 'plannerArgs'
    | 'plannerTimeoutMs'
  >;
}

const analysisFingerprint = (analysis: TrackAnalysis | null) => {
  if (!analysis) {
    return null;
  }

  return {
    schemaVersion: analysis.schemaVersion,
    generatedAt: analysis.generatedAt,
    source: analysis.source,
    bpm: analysis.bpm,
    bpmConfidence: analysis.bpmConfidence,
    analysisConfidence: analysis.analysisConfidence
  };
};

const trackFingerprint = (track: Track) => ({
  id: track.id,
  durationSec: track.durationSec,
  bpm: typeof track.bpm === 'number' && Number.isFinite(track.bpm) ? track.bpm : null
});

const plannerFingerprint = (settings: MixPlanCacheKeyInput['settings']) => {
  const activeProfile = resolveActiveAiAgentProfile(settings);
  if (activeProfile) {
    return {
      profileId: activeProfile.id,
      name: activeProfile.name,
      command: activeProfile.command,
      args: activeProfile.args,
      timeoutMs: activeProfile.timeoutMs,
      enabled: activeProfile.enabled
    };
  }

  return {
    profileId: null,
    name: null,
    command: settings.plannerCommand,
    args: settings.plannerArgs,
    timeoutMs: settings.plannerTimeoutMs,
    enabled: settings.plannerCommand.trim().length > 0
  };
};

export const buildMixPlanCacheKey = (input: MixPlanCacheKeyInput): string => {
  return JSON.stringify({
    schema: 1,
    currentTrack: trackFingerprint(input.currentTrack),
    nextTrack: trackFingerprint(input.nextTrack),
    currentAnalysis: analysisFingerprint(input.currentAnalysis),
    nextAnalysis: analysisFingerprint(input.nextAnalysis),
    planner: plannerFingerprint(input.settings),
    settings: {
      aiDjMode: input.settings.aiDjMode,
      fadeDurationSec: input.settings.fadeDurationSec
    }
  });
};

export const createMixPlanCacheEntry = (input: {
  key: string;
  currentTrackId: string;
  nextTrackId: string;
  result: RequestMixPlanResult | null;
  quality?: MixPlanQualityResult | null;
  error?: string | null;
  createdAtMs: number;
}): MixPlanCacheEntry => {
  const hasPlan = input.result?.plan !== null && input.result?.plan !== undefined;
  return {
    key: input.key,
    currentTrackId: input.currentTrackId,
    nextTrackId: input.nextTrackId,
    status: hasPlan ? 'ready' : 'failed',
    createdAtMs: input.createdAtMs,
    result: input.result,
    quality: input.quality ?? null,
    error: input.error ?? input.result?.reason ?? null
  };
};

export const isMixPlanCacheEntryUsable = (
  entry: MixPlanCacheEntry | null | undefined,
  nowMs: number,
  failedCooldownMs = MIX_PLAN_FAILED_CACHE_COOLDOWN_MS
): entry is MixPlanCacheEntry => {
  if (!entry) {
    return false;
  }

  if (entry.status === 'ready') {
    return true;
  }

  return nowMs - entry.createdAtMs < failedCooldownMs;
};

export const summarizeMixPlanCache = (
  cache: MixPlanCacheStore,
  inFlightKeys: string[] = []
) => {
  const entries = Object.values(cache);
  const quality: Record<MixPlanQualityGrade, number> & { unscored: number } = {
    excellent: 0,
    good: 0,
    usable: 0,
    weak: 0,
    reject: 0,
    unscored: 0
  };
  for (const entry of entries) {
    if (entry.status !== 'ready') {
      continue;
    }
    if (entry.quality) {
      quality[entry.quality.grade] += 1;
    } else {
      quality.unscored += 1;
    }
  }

  return {
    ready: entries.filter((entry) => entry.status === 'ready').length,
    failed: entries.filter((entry) => entry.status === 'failed').length,
    pending: inFlightKeys.length,
    total: entries.length,
    quality
  };
};
