import { buildAnalysisInspectorSummary } from '../../src/renderer/player/analysisInspector';
import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION } from '../../src/shared/analysis';

const buildAnalysis = (overrides = {}) =>
  sanitizeTrackAnalysis('track-a', {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    bpm: 124,
    bpmConfidence: 0.82,
    beatGridSec: [0, 0.48, 0.97, 1.45],
    downbeatsSec: [0],
    barGrid: [
      { index: 0, startSec: 0, beatIndex: 0 },
      { index: 8, startSec: 15.48, beatIndex: 32 }
    ],
    phraseMarkers: [
      { index: 0, startSec: 0, bars: 8, confidence: 0.68 },
      { index: 1, startSec: 15.48, bars: 8, confidence: 0.82 }
    ],
    transientMarkers: [
      { index: 0, timeSec: 0, strength: 0.88 },
      { index: 1, timeSec: 15.48, strength: 0.76 }
    ],
    energyProfile: [0.2, 0.8, 0.7],
    waveformDetail: [
      { timeSec: 0, peak: 0.8, rms: 0.4, min: -0.8, max: 0.8 }
    ],
    spectralBands: [{ timeSec: 0, low: 0.6, mid: 0.7, high: 0.5 }],
    cueCandidates: [
      {
        id: 'first-downbeat',
        type: 'first_downbeat',
        startSec: 0,
        endSec: 4,
        confidence: 0.74,
        label: 'First downbeat'
      },
      {
        id: 'outro',
        type: 'outro',
        startSec: 174,
        endSec: 190,
        confidence: 0.7,
        label: 'Outro mix-out'
      }
    ],
    analysisConfidence: 0.86,
    analysisQuality: {
      waveformDetail: 0.72,
      spectralBands: 0.7,
      transientMarkers: 0.66,
      beatGrid: 0.78
    },
    ...overrides
  });

describe('buildAnalysisInspectorSummary', () => {
  it('returns a pending summary when analysis is missing', () => {
    const summary = buildAnalysisInspectorSummary(null);

    expect(summary.status).toBe('pending');
    expect(summary.plannerReady).toBe(false);
    expect(summary.issues.map((issue) => issue.id)).toContain('analysis_missing');
  });

  it('summarizes planner-ready phrase and cue confidence', () => {
    const summary = buildAnalysisInspectorSummary(buildAnalysis());

    expect(summary.status).toBe('planner_ready');
    expect(summary.plannerReady).toBe(true);
    expect(summary.phraseMarkers).toBe(2);
    expect(summary.phraseAverageConfidence).toBeCloseTo(0.75);
    expect(summary.phraseMaxConfidence).toBe(0.82);
    expect(summary.strongPhraseMarkers).toBe(2);
    expect(summary.cueConfidenceMin).toBe(0.7);
    expect(summary.issues).toEqual([]);
  });

  it('flags weak analysis signals that slow real-track inspection', () => {
    const summary = buildAnalysisInspectorSummary(
      buildAnalysis({
        bpmConfidence: 0.32,
        phraseMarkers: [{ index: 0, startSec: 0, bars: 8, confidence: 0.42 }],
        cueCandidates: [
          {
            id: 'outro',
            type: 'outro',
            startSec: 170,
            endSec: 190,
            confidence: 0.44,
            label: 'Outro mix-out'
          }
        ],
        analysisQuality: {
          waveformDetail: 0.1,
          spectralBands: 0.7,
          transientMarkers: 0.4,
          beatGrid: 0.2
        }
      })
    );

    expect(summary.status).toBe('needs_upgrade');
    expect(summary.plannerReady).toBe(false);
    expect(summary.issues.map((issue) => issue.id)).toEqual(
      expect.arrayContaining([
        'waveform_detail_low',
        'beat_grid_low',
        'bpm_confidence_low',
        'phrase_confidence_low',
        'cue_confidence_low'
      ])
    );
  });
});
