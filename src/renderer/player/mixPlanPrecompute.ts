import { hasPlannerReadyTrackAnalysis, TrackAnalysis } from '../../shared/analysis';
import {
  buildMixPlanCacheKey,
  isMixPlanCacheEntryUsable,
  MixPlanCacheEntry,
  MixPlanCacheKeyInput,
  MixPlanCacheStore
} from '../../shared/mixPlanCache';
import { isPlannerCommandConfigured } from '../../shared/plannerContract';
import { PlayerSettings, Track } from '../../shared/types';

export interface MixPlanPrecomputePair {
  key: string;
  currentTrack: Track;
  nextTrack: Track;
  currentAnalysis: TrackAnalysis;
  nextAnalysis: TrackAnalysis;
}

export const MIX_PLAN_PRECOMPUTE_LOOKAHEAD_PAIRS = 3;

export interface BuildMixPlanPrecomputePairsInput {
  tracks: Track[];
  analysisByTrackId: Record<string, TrackAnalysis>;
  settings: PlayerSettings;
  cache: MixPlanCacheStore;
  inFlightKeys: string[];
  nowMs: number;
  startTrackId?: string | null;
  maxLookaheadPairs?: number;
  failedCooldownMs?: number;
}

const buildAdjacentPairs = (
  tracks: Track[],
  repeatAll: boolean,
  startTrackId?: string | null
): Array<[Track, Track]> => {
  const startIndex =
    typeof startTrackId === 'string'
      ? tracks.findIndex((track) => track.id === startTrackId)
      : -1;
  if (startIndex >= 0) {
    const pairs: Array<[Track, Track]> = [];
    const pairCount = repeatAll
      ? tracks.length
      : Math.max(0, tracks.length - 1 - startIndex);

    for (let offset = 0; offset < pairCount; offset += 1) {
      const currentIndex = (startIndex + offset) % tracks.length;
      const nextIndex =
        currentIndex + 1 < tracks.length
          ? currentIndex + 1
          : repeatAll
            ? 0
            : -1;
      if (nextIndex >= 0) {
        pairs.push([tracks[currentIndex], tracks[nextIndex]]);
      }
    }

    return pairs.filter(([current, next]) => current.id !== next.id);
  }

  const pairs: Array<[Track, Track]> = [];
  for (let index = 0; index + 1 < tracks.length; index += 1) {
    pairs.push([tracks[index], tracks[index + 1]]);
  }

  if (repeatAll && tracks.length > 1) {
    pairs.push([tracks[tracks.length - 1], tracks[0]]);
  }

  return pairs.filter(([current, next]) => current.id !== next.id);
};

export const buildMixPlanPrecomputePairs = (
  input: BuildMixPlanPrecomputePairsInput
): MixPlanPrecomputePair[] => {
  if (!input.settings.aiDjEnabled || !isPlannerCommandConfigured(input.settings)) {
    return [];
  }

  const inFlight = new Set(input.inFlightKeys);
  const maxLookaheadPairs =
    typeof input.maxLookaheadPairs === 'number' && Number.isFinite(input.maxLookaheadPairs)
      ? Math.max(0, Math.floor(input.maxLookaheadPairs))
      : null;
  const candidatePairs = buildAdjacentPairs(
    input.tracks,
    input.settings.repeatAll,
    input.startTrackId
  );
  const lookaheadPairs =
    maxLookaheadPairs === null ? candidatePairs : candidatePairs.slice(0, maxLookaheadPairs);

  return lookaheadPairs
    .map(([currentTrack, nextTrack]) => {
      const currentAnalysis = input.analysisByTrackId[currentTrack.id] ?? null;
      const nextAnalysis = input.analysisByTrackId[nextTrack.id] ?? null;
      if (!hasPlannerReadyTrackAnalysis(currentAnalysis) || !hasPlannerReadyTrackAnalysis(nextAnalysis)) {
        return null;
      }

      const keyInput: MixPlanCacheKeyInput = {
        currentTrack,
        nextTrack,
        currentAnalysis,
        nextAnalysis,
        settings: input.settings
      };
      const key = buildMixPlanCacheKey(keyInput);
      const cached = input.cache[key];
      if (
        inFlight.has(key) ||
        isMixPlanCacheEntryUsable(cached, input.nowMs, input.failedCooldownMs)
      ) {
        return null;
      }

      return {
        key,
        currentTrack,
        nextTrack,
        currentAnalysis,
        nextAnalysis
      };
    })
    .filter((pair): pair is MixPlanPrecomputePair => pair !== null);
};

export const findCachedMixPlanResult = (input: {
  currentTrack: Track;
  nextTrack: Track;
  currentAnalysis: TrackAnalysis | null;
  nextAnalysis: TrackAnalysis | null;
  settings: PlayerSettings;
  cache: MixPlanCacheStore;
  nowMs: number;
  failedCooldownMs?: number;
}): MixPlanCacheEntry | null => {
  const key = buildMixPlanCacheKey({
    currentTrack: input.currentTrack,
    nextTrack: input.nextTrack,
    currentAnalysis: input.currentAnalysis,
    nextAnalysis: input.nextAnalysis,
    settings: input.settings
  });
  const entry = input.cache[key];
  return isMixPlanCacheEntryUsable(entry, input.nowMs, input.failedCooldownMs) ? entry : null;
};
