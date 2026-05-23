import {
  buildMixPlanCacheKey,
  createMixPlanCacheEntry,
  isMixPlanCacheEntryUsable,
  summarizeMixPlanCache
} from '../../src/shared/mixPlanCache';
import type { MixPlanQualityResult } from '../../src/shared/mixPlanQuality';
import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION } from '../../src/shared/analysis';
import { DEFAULT_SETTINGS } from '../../src/shared/settings';
import { Track } from '../../src/shared/types';

const currentTrack: Track = {
  id: 'current',
  title: 'Current',
  durationSec: 180,
  format: 'mp3',
  bpm: 124
};

const nextTrack: Track = {
  id: 'next',
  title: 'Next',
  durationSec: 190,
  format: 'mp3',
  bpm: 126
};

const analysis = (trackId: string, generatedAt: string) =>
  sanitizeTrackAnalysis(trackId, {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    generatedAt,
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

const readyResult = {
  source: 'cli' as const,
  reason: null,
  request: {} as never,
  response: null,
  analysis: { current: null, next: null },
  plan: {
    transitionStartSec: 10,
    transitionEndSec: 16,
    nextTrackStartOffsetSec: 0,
    style: 'smooth_blend' as const,
    confidence: 0.8,
    reasoningSummary: null,
    tempoSync: { enabled: false, targetRate: null }
  }
};

const quality = (grade: MixPlanQualityResult['grade']): MixPlanQualityResult => ({
  score: grade === 'reject' ? 0.32 : 0.74,
  grade,
  shouldApply: grade !== 'reject',
  issues: [],
  metrics: [],
  summary: grade
});

describe('mixPlanCache', () => {
  it('changes keys when analysis or planner settings change', () => {
    const base = buildMixPlanCacheKey({
      currentTrack,
      nextTrack,
      currentAnalysis: analysis('current', '2026-01-01T00:00:00.000Z'),
      nextAnalysis: analysis('next', '2026-01-01T00:00:00.000Z'),
      settings: DEFAULT_SETTINGS
    });
    const changedAnalysis = buildMixPlanCacheKey({
      currentTrack,
      nextTrack,
      currentAnalysis: analysis('current', '2026-01-02T00:00:00.000Z'),
      nextAnalysis: analysis('next', '2026-01-01T00:00:00.000Z'),
      settings: DEFAULT_SETTINGS
    });
    const changedMode = buildMixPlanCacheKey({
      currentTrack,
      nextTrack,
      currentAnalysis: analysis('current', '2026-01-01T00:00:00.000Z'),
      nextAnalysis: analysis('next', '2026-01-01T00:00:00.000Z'),
      settings: {
        ...DEFAULT_SETTINGS,
        aiDjMode: 'adventurous'
      }
    });

    expect(changedAnalysis).not.toBe(base);
    expect(changedMode).not.toBe(base);
  });

  it('keeps ready entries usable and expires failed entries after cooldown', () => {
    const ready = createMixPlanCacheEntry({
      key: 'ready',
      currentTrackId: 'current',
      nextTrackId: 'next',
      createdAtMs: 1000,
      result: readyResult
    });
    const failed = createMixPlanCacheEntry({
      key: 'failed',
      currentTrackId: 'current',
      nextTrackId: 'next',
      createdAtMs: 1000,
      result: null,
      error: 'planner timeout'
    });

    expect(isMixPlanCacheEntryUsable(ready, 60_000, 5000)).toBe(true);
    expect(isMixPlanCacheEntryUsable(failed, 4000, 5000)).toBe(true);
    expect(isMixPlanCacheEntryUsable(failed, 7000, 5000)).toBe(false);
  });

  it('stores quality metadata and summarizes ready-plan grades', () => {
    const good = createMixPlanCacheEntry({
      key: 'good',
      currentTrackId: 'current',
      nextTrackId: 'next',
      createdAtMs: 1000,
      result: readyResult,
      quality: quality('good')
    });
    const reject = createMixPlanCacheEntry({
      key: 'reject',
      currentTrackId: 'current',
      nextTrackId: 'next',
      createdAtMs: 1000,
      result: readyResult,
      quality: quality('reject')
    });
    const unscored = createMixPlanCacheEntry({
      key: 'unscored',
      currentTrackId: 'current',
      nextTrackId: 'next',
      createdAtMs: 1000,
      result: readyResult
    });
    const failed = createMixPlanCacheEntry({
      key: 'failed',
      currentTrackId: 'current',
      nextTrackId: 'next',
      createdAtMs: 1000,
      result: null,
      error: 'planner timeout'
    });

    const summary = summarizeMixPlanCache(
      {
        good,
        reject,
        unscored,
        failed
      },
      ['pending-key']
    );

    expect(good.quality?.grade).toBe('good');
    expect(summary).toMatchObject({
      ready: 3,
      failed: 1,
      pending: 1,
      total: 4,
      quality: {
        excellent: 0,
        good: 1,
        usable: 0,
        weak: 0,
        reject: 1,
        unscored: 1
      }
    });
  });
});
