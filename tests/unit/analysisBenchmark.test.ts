import {
  evaluateAnalysisBenchmarkFixture,
  evaluateAnalysisBenchmarkSuite,
  evaluateTrackAnalysisBenchmark,
  DEFAULT_ANALYSIS_BENCHMARK_THRESHOLDS
} from '../../src/shared/analysisBenchmark';
import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION } from '../../src/shared/analysis';

const buildAnalysis = (input?: {
  bpm?: number;
  firstDownbeatSec?: number;
  outroSec?: number | null;
  barOffsetSec?: number;
  phraseMarkers?: number[];
}) => {
  const barOffsetSec = input?.barOffsetSec ?? 0;
  return sanitizeTrackAnalysis('track-1', {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    bpm: input?.bpm ?? 124,
    bpmConfidence: 0.88,
    beatGridSec: Array.from({ length: 32 }, (_item, index) => barOffsetSec + index * 2),
    downbeatsSec: Array.from({ length: 8 }, (_item, index) => barOffsetSec + index * 8),
    barGrid: Array.from({ length: 8 }, (_item, index) => ({
      index,
      startSec: barOffsetSec + index * 8,
      beatIndex: index * 4
    })),
    phraseMarkers: (input?.phraseMarkers ?? [32, 64]).map((startSec, index) => ({
      index,
      startSec,
      bars: 8,
      confidence: 0.82
    })),
    introCueSec: 0,
    outroCueSec: input?.outroSec ?? 96,
    energyProfile: [0.8, 0.68, 0.5, 0.42, 0.34, 0.26],
    waveformDetail: [{ timeSec: 0, peak: 0.8, rms: 0.42, min: -0.6, max: 0.8 }],
    spectralBands: [{ timeSec: 0, low: 0.6, mid: 0.42, high: 0.3 }],
    transientMarkers: [{ index: 0, timeSec: input?.firstDownbeatSec ?? 0, strength: 0.8 }],
    cueCandidates: [
      {
        id: 'first-downbeat',
        type: 'first_downbeat',
        startSec: input?.firstDownbeatSec ?? 0,
        endSec: (input?.firstDownbeatSec ?? 0) + 4,
        confidence: 0.84,
        label: 'First downbeat'
      },
      ...(input?.outroSec === null
        ? []
        : [
            {
              id: 'outro',
              type: 'outro' as const,
              startSec: input?.outroSec ?? 96,
              endSec: 112,
              confidence: 0.82,
              label: 'Outro mix-out'
            }
          ])
    ],
    analysisConfidence: 0.86,
    analysisQuality: {
      waveformDetail: 0.82,
      spectralBands: 0.76,
      transientMarkers: 0.78,
      beatGrid: 0.84
    }
  });
};

describe('evaluateTrackAnalysisBenchmark', () => {
  it('passes close BPM, cue, bar, phrase, and planner-ready checkpoints', () => {
    const result = evaluateTrackAnalysisBenchmark({
      analysis: buildAnalysis({ firstDownbeatSec: 0, outroSec: 96 }),
      expected: {
        bpm: 124.4,
        firstDownbeatSec: 0,
        outroCueSec: 96.3,
        barGridSec: [0, 8, 16, 24, 32, 40, 48, 56],
        phraseBoundarySec: [32, 64],
        plannerReady: true
      }
    });

    expect(result.grade).toBe('pass');
    expect(result.score).toBeGreaterThan(0.95);
    expect(result.issues).toEqual([]);
    expect(result.metrics.bpmError).toBeCloseTo(0.4);
    expect(result.metrics.outro?.distanceSec).toBeCloseTo(0.3);
    expect(result.metrics.barGrid.averageDriftSec).toBe(0);
    expect(result.metrics.plannerReadyMatch).toBe(true);
  });

  it('fails when core timing checkpoints drift beyond thresholds', () => {
    const result = evaluateTrackAnalysisBenchmark({
      analysis: buildAnalysis({
        bpm: 131,
        firstDownbeatSec: 7,
        outroSec: 84,
        barOffsetSec: 2,
        phraseMarkers: []
      }),
      expected: {
        bpm: 124,
        firstDownbeatSec: 0,
        outroCueSec: 96,
        barGridSec: [0, 8, 16, 24, 32, 40, 48, 56],
        phraseBoundarySec: [32, 64],
        plannerReady: true
      }
    });

    expect(result.grade).toBe('fail');
    expect(result.score).toBeLessThan(0.55);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        'bpm_error_high',
        'first_downbeat_far',
        'outro_far',
        'bar_grid_drift_high',
        'phrase_missing'
      ])
    );
  });

  it('can use stricter thresholds for regression sweeps', () => {
    const result = evaluateTrackAnalysisBenchmark({
      analysis: buildAnalysis({ firstDownbeatSec: 0.6, outroSec: 96.6, barOffsetSec: 0.6 }),
      expected: {
        firstDownbeatSec: 0,
        outroCueSec: 96
      },
      thresholds: {
        ...DEFAULT_ANALYSIS_BENCHMARK_THRESHOLDS,
        cueWarnDistanceSec: 0.25,
        cueFailDistanceSec: 1
      }
    });

    expect(result.grade).toBe('warn');
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining(['first_downbeat_far', 'outro_far'])
    );
  });

  it('keeps real-track snapshot metadata separate from synthetic fixtures', () => {
    const fixtureResult = evaluateAnalysisBenchmarkFixture({
      id: 'private-snapshot-a',
      title: 'Private snapshot A',
      kind: 'snapshot',
      tags: ['house', 'downbeat'],
      trackReference: {
        source: 'private-library',
        title: 'Private reference',
        notes: 'Local-only captured TrackAnalysis JSON.'
      },
      expectedGrade: 'pass',
      expected: {
        bpm: 124,
        firstDownbeatSec: 0,
        outroCueSec: 96,
        barGridSec: [0, 8, 16, 24],
        phraseBoundarySec: [32],
        plannerReady: true
      },
      analysis: buildAnalysis({ firstDownbeatSec: 0, outroSec: 96 })
    });
    const suite = evaluateAnalysisBenchmarkSuite([
      {
        id: 'synthetic-a',
        title: 'Synthetic A',
        kind: 'synthetic',
        expectedGrade: 'pass',
        expected: {
          bpm: 124,
          firstDownbeatSec: 0,
          outroCueSec: 96,
          plannerReady: true
        },
        analysis: buildAnalysis({ firstDownbeatSec: 0, outroSec: 96 })
      },
      {
        id: 'private-snapshot-a',
        title: 'Private snapshot A',
        kind: 'snapshot',
        expectedGrade: 'pass',
        expected: {
          bpm: 124,
          firstDownbeatSec: 0,
          outroCueSec: 96,
          plannerReady: true
        },
        analysis: buildAnalysis({ firstDownbeatSec: 0, outroSec: 96 })
      }
    ]);

    expect(fixtureResult.kind).toBe('snapshot');
    expect(fixtureResult.tags).toEqual(['house', 'downbeat']);
    expect(fixtureResult.trackReference?.source).toBe('private-library');
    expect(suite.byKind.map((summary) => summary.kind)).toEqual(['synthetic', 'snapshot']);
    expect(suite.byKind.find((summary) => summary.kind === 'snapshot')?.total).toBe(1);
  });
});
