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
        label: 'First downbeat',
        origin: 'derived'
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
              label: 'Outro mix-out',
              origin: 'derived' as const
            }
          ])
    ],
    analysisConfidence: 0.86,
    analysisQuality: {
      waveformDetail: 0.82,
      spectralBands: 0.76,
      transientMarkers: 0.78,
      beatGrid: 0.84,
      harmonicKey: 0.45
    },
    musicalKey: {
      tonic: 'C',
      mode: 'minor',
      confidence: 0.45,
      chromaEnergy: 128
    },
    loudness: {
      integratedRMSDb: -10.2,
      integratedLUFS: -9.8,
      peakDb: -0.7,
      truePeakDb: -0.55,
      headroomDb: 0.7,
      crestFactorDb: 9.5,
      dynamicRangeDb: 12.8,
      loudnessRangeLU: 4.1,
      measurement: 'ebu_r128_k_weighted_gated_mono',
      confidence: 0.82
    },
    stereo: {
      channelCount: 2,
      leftPeakDb: -0.7,
      rightPeakDb: -1.1,
      leftRMSDb: -10.1,
      rightRMSDb: -10.6,
      stereoWidth: 0.32,
      phaseCorrelation: 0.72,
      midSideBalance: 2.15,
      confidence: 0.86
    },
    analysisWarnings: []
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

  it('checks schema v7 key loudness stereo cue and readiness calibration', () => {
    const result = evaluateTrackAnalysisBenchmark({
      analysis: buildAnalysis({ firstDownbeatSec: 0, outroSec: 96 }),
      expected: {
        bpm: 124,
        firstDownbeatSec: 0,
        outroCueSec: 96,
        barGridSec: [0, 8, 16, 24, 32, 40, 48, 56],
        phraseBoundarySec: [32, 64],
        plannerReady: true,
        musicalKey: {
          tonic: 'C',
          mode: 'minor',
          minConfidence: 0.4
        },
        loudness: {
          integratedRMSDb: -10.2,
          integratedLUFS: -9.8,
          peakDb: -0.7,
          truePeakDb: -0.55,
          minHeadroomDb: 0.5,
          minConfidence: 0.7
        },
        stereo: {
          channelCount: 2,
          minStereoWidth: 0.2,
          maxStereoWidth: 0.8,
          minPhaseCorrelation: 0.4,
          maxMidSideBalance: 4,
          minConfidence: 0.7
        },
        cueCandidates: [
          { type: 'first_downbeat', startSec: 0, minConfidence: 0.7, origin: 'derived' },
          { type: 'outro', startSec: 96, minConfidence: 0.7, origin: 'derived' }
        ],
        mixReadiness: {
          minAnalysisConfidence: 0.78,
          minHarmonicKeyQuality: 0.4,
          minLoudnessConfidence: 0.7,
          forbiddenWarnings: ['key_unavailable', 'loudness_low_confidence']
        }
      }
    });

    expect(result.grade).toBe('pass');
    expect(result.metrics.musicalKey?.matched).toBe(true);
    expect(result.metrics.loudness?.integratedRMSDeltaDb).toBe(0);
    expect(result.metrics.loudness?.integratedLUFSDelta).toBe(0);
    expect(result.metrics.loudness?.truePeakDeltaDb).toBe(0);
    expect(result.metrics.loudness?.measurement).toBe('ebu_r128_k_weighted_gated_mono');
    expect(result.metrics.stereo?.actualChannelCount).toBe(2);
    expect(result.metrics.stereo?.stereoWidth).toBe(0.32);
    expect(result.metrics.stereo?.phaseCorrelation).toBe(0.72);
    expect(result.metrics.cueCandidates).toHaveLength(2);
    expect(result.metrics.mixReadiness?.forbiddenWarningsPresent).toEqual([]);
  });

  it('warns when schema v7 calibration evidence is weak but present', () => {
    const weak = sanitizeTrackAnalysis('track-1', {
      ...buildAnalysis({ firstDownbeatSec: 0, outroSec: 96 }),
      musicalKey: {
        tonic: 'D',
        mode: 'minor',
        confidence: 0.3,
        chromaEnergy: 20
      },
      loudness: {
        integratedRMSDb: -14,
        integratedLUFS: -13.5,
        peakDb: -0.1,
        truePeakDb: -0.02,
        headroomDb: 0.1,
        crestFactorDb: 13.9,
        dynamicRangeDb: 8,
        loudnessRangeLU: 3.2,
        measurement: 'ebu_r128_k_weighted_gated_mono',
        confidence: 0.5
      },
      stereo: {
        channelCount: 2,
        leftPeakDb: -0.2,
        rightPeakDb: -0.4,
        leftRMSDb: -12,
        rightRMSDb: -12.2,
        stereoWidth: 0.05,
        phaseCorrelation: 0.1,
        midSideBalance: 8,
        confidence: 0.5
      },
      analysisQuality: {
        waveformDetail: 0.82,
        spectralBands: 0.76,
        transientMarkers: 0.78,
        beatGrid: 0.84,
        harmonicKey: 0.3
      },
      analysisWarnings: ['key_low_confidence', 'headroom_low']
    });

    const result = evaluateTrackAnalysisBenchmark({
      analysis: weak,
      expected: {
        musicalKey: { tonic: 'C', mode: 'minor', minConfidence: 0.4 },
        loudness: {
          integratedRMSDb: -10.2,
          integratedLUFS: -9.8,
          peakDb: -0.7,
          truePeakDb: -0.55,
          minHeadroomDb: 0.5,
          minConfidence: 0.7
        },
        stereo: {
          channelCount: 2,
          minStereoWidth: 0.2,
          minPhaseCorrelation: 0.4,
          maxMidSideBalance: 4,
          minConfidence: 0.7
        },
        mixReadiness: {
          minHarmonicKeyQuality: 0.4,
          minLoudnessConfidence: 0.7,
          forbiddenWarnings: ['headroom_low']
        }
      }
    });

    expect(result.grade).toBe('fail');
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        'key_mismatch',
        'key_confidence_low',
        'loudness_rms_delta_high',
        'loudness_lufs_delta_high',
        'headroom_low',
        'stereo_width_low',
        'stereo_phase_correlation_low',
        'stereo_mid_side_balance_high',
        'stereo_confidence_low',
        'forbidden_warning_present'
      ])
    );
  });

  it('uses editable ground-truth labels over stale fixture expectations', () => {
    const fixtureResult = evaluateAnalysisBenchmarkFixture({
      id: 'editable-labels',
      title: 'Editable labels fixture',
      kind: 'snapshot',
      expected: {
        bpm: 130,
        firstDownbeatSec: 12
      },
      groundTruthLabels: {
        schemaVersion: 1,
        reviewedBy: 'user',
        reviewedAt: '2026-07-02T00:00:00.000Z',
        expected: {
          bpm: 124,
          firstDownbeatSec: 0,
          loudness: {
            integratedLUFS: -9.8,
            truePeakDb: -0.55,
            minConfidence: 0.7
          }
        }
      },
      analysis: buildAnalysis({ firstDownbeatSec: 0 })
    });

    expect(fixtureResult.grade).toBe('pass');
    expect(fixtureResult.metrics.bpmError).toBe(0);
    expect(fixtureResult.metrics.firstDownbeat?.distanceSec).toBe(0);
    expect(fixtureResult.metrics.loudness?.integratedLUFSDelta).toBe(0);
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
