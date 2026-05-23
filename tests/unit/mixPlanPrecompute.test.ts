import {
  buildMixPlanPrecomputePairs,
  findCachedMixPlanResult
} from '../../src/renderer/player/mixPlanPrecompute';
import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION } from '../../src/shared/analysis';
import {
  buildMixPlanCacheKey,
  createMixPlanCacheEntry,
  MixPlanCacheStore
} from '../../src/shared/mixPlanCache';
import { DEFAULT_SETTINGS, HEURISTIC_AGENT_PROFILE_ID } from '../../src/shared/settings';
import { Track } from '../../src/shared/types';

const tracks: Track[] = [
  { id: 'a', title: 'A', durationSec: 180, format: 'mp3', bpm: 124 },
  { id: 'b', title: 'B', durationSec: 190, format: 'mp3', bpm: 126 },
  { id: 'c', title: 'C', durationSec: 200, format: 'mp3', bpm: 128 }
];

const plannerReadyAnalysis = (trackId: string) =>
  sanitizeTrackAnalysis(trackId, {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    generatedAt: `2026-01-01T00:00:0${trackId}.000Z`,
    bpm: 124,
    bpmConfidence: 0.9,
    waveformDetail: [{ timeSec: 0, peak: 0.4, rms: 0.2, min: -0.2, max: 0.4 }],
    energyProfile: [0.2, 0.5, 0.4],
    barGrid: [{ index: 0, startSec: 0, beatIndex: 0 }],
    analysisQuality: {
      waveformDetail: 0.4,
      spectralBands: 0.4,
      transientMarkers: 0.2,
      beatGrid: 0.8
    }
  });

const settings = {
  ...DEFAULT_SETTINGS,
  aiDjEnabled: true,
  activeAiAgentProfileId: HEURISTIC_AGENT_PROFILE_ID
};

describe('mixPlanPrecompute', () => {
  it('selects planner-ready adjacent pairs and honors repeat-all', () => {
    const pairs = buildMixPlanPrecomputePairs({
      tracks,
      analysisByTrackId: Object.fromEntries(
        tracks.map((track) => [track.id, plannerReadyAnalysis(track.id)])
      ),
      settings,
      cache: {},
      inFlightKeys: [],
      nowMs: 1000
    });

    expect(pairs.map((pair) => `${pair.currentTrack.id}->${pair.nextTrack.id}`)).toEqual([
      'a->b',
      'b->c',
      'c->a'
    ]);
  });

  it('prioritizes lookahead pairs from the active track and caps the window', () => {
    const pairs = buildMixPlanPrecomputePairs({
      tracks,
      analysisByTrackId: Object.fromEntries(
        tracks.map((track) => [track.id, plannerReadyAnalysis(track.id)])
      ),
      settings,
      cache: {},
      inFlightKeys: [],
      nowMs: 1000,
      startTrackId: 'b',
      maxLookaheadPairs: 2
    });

    expect(pairs.map((pair) => `${pair.currentTrack.id}->${pair.nextTrack.id}`)).toEqual([
      'b->c',
      'c->a'
    ]);
  });

  it('does not include past pairs when repeat-all is disabled', () => {
    const pairs = buildMixPlanPrecomputePairs({
      tracks,
      analysisByTrackId: Object.fromEntries(
        tracks.map((track) => [track.id, plannerReadyAnalysis(track.id)])
      ),
      settings: {
        ...settings,
        repeatAll: false
      },
      cache: {},
      inFlightKeys: [],
      nowMs: 1000,
      startTrackId: 'b',
      maxLookaheadPairs: 3
    });

    expect(pairs.map((pair) => `${pair.currentTrack.id}->${pair.nextTrack.id}`)).toEqual([
      'b->c'
    ]);
  });

  it('skips pairs without planner-ready analysis and entries in failed cooldown', () => {
    const readyById = {
      a: plannerReadyAnalysis('a'),
      b: plannerReadyAnalysis('b')
    };
    const key = buildMixPlanCacheKey({
      currentTrack: tracks[0],
      nextTrack: tracks[1],
      currentAnalysis: readyById.a,
      nextAnalysis: readyById.b,
      settings
    });
    const cache: MixPlanCacheStore = {
      [key]: createMixPlanCacheEntry({
        key,
        currentTrackId: 'a',
        nextTrackId: 'b',
        createdAtMs: 1000,
        result: null,
        error: 'planner timeout'
      })
    };

    const pairs = buildMixPlanPrecomputePairs({
      tracks,
      analysisByTrackId: readyById,
      settings,
      cache,
      inFlightKeys: [],
      nowMs: 2000,
      failedCooldownMs: 5000
    });

    expect(pairs).toEqual([]);
  });

  it('finds matching cached entries for a pair', () => {
    const currentAnalysis = plannerReadyAnalysis('a');
    const nextAnalysis = plannerReadyAnalysis('b');
    const key = buildMixPlanCacheKey({
      currentTrack: tracks[0],
      nextTrack: tracks[1],
      currentAnalysis,
      nextAnalysis,
      settings
    });
    const entry = createMixPlanCacheEntry({
      key,
      currentTrackId: 'a',
      nextTrackId: 'b',
      createdAtMs: 1000,
      result: null,
      error: 'planner timeout'
    });

    expect(
      findCachedMixPlanResult({
        currentTrack: tracks[0],
        nextTrack: tracks[1],
        currentAnalysis,
        nextAnalysis,
        settings,
        cache: { [key]: entry },
        nowMs: 2000,
        failedCooldownMs: 5000
      })
    ).toBe(entry);
  });
});
