import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION } from '../../src/shared/analysis';
import { buildPlannerRequest } from '../../src/shared/plannerContract';
import { Track } from '../../src/shared/types';

const currentTrack: Track = {
  id: 'current',
  title: 'Current',
  durationSec: 120,
  format: 'mp3',
  bpm: 124
};

const nextTrack: Track = {
  id: 'next',
  title: 'Next',
  durationSec: 128,
  format: 'mp3',
  bpm: 126
};

describe('buildPlannerAnalysisSummary', () => {
  it('adds compact DSP evidence to planner requests', () => {
    const currentAnalysis = sanitizeTrackAnalysis('current', {
      schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
      bpm: 124,
      bpmConfidence: 0.86,
      beatGridSec: [80, 81.94, 83.87, 85.81],
      downbeatsSec: [80],
      barGrid: [
        { index: 10, startSec: 80, beatIndex: 40 },
        { index: 11, startSec: 87.74, beatIndex: 44 }
      ],
      phraseMarkers: [
        { index: 0, startSec: 64, bars: 8, confidence: 0.62 },
        { index: 1, startSec: 80, bars: 8, confidence: 0.88 }
      ],
      introCueSec: 0,
      outroCueSec: 88,
      energyProfile: [0.8, 0.7, 0.45, 0.34, 0.28, 0.24],
      waveformDetail: [{ timeSec: 80, peak: 0.7, rms: 0.4, min: -0.5, max: 0.7 }],
      spectralBands: [{ timeSec: 80, low: 0.7, mid: 0.45, high: 0.3 }],
      transientMarkers: [
        { index: 0, timeSec: 80, strength: 0.7 },
        { index: 1, timeSec: 88, strength: 0.5 }
      ],
      cueCandidates: [
        {
          id: 'outro',
          type: 'outro',
          startSec: 88,
          endSec: 112,
          confidence: 0.82,
          label: 'Outro mix-out'
        }
      ],
      analysisConfidence: 0.84,
      analysisQuality: {
        waveformDetail: 0.82,
        spectralBands: 0.8,
        transientMarkers: 0.72,
        beatGrid: 0.86
      }
    });
    const nextAnalysis = sanitizeTrackAnalysis('next', {
      schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
      bpm: 126,
      bpmConfidence: 0.84,
      beatGridSec: [0, 1.9, 3.8, 5.7],
      downbeatsSec: [0],
      barGrid: [{ index: 0, startSec: 0, beatIndex: 0 }],
      phraseMarkers: [{ index: 0, startSec: 0, bars: 8, confidence: 0.78 }],
      introCueSec: 0,
      energyProfile: [0.2, 0.24, 0.35, 0.48, 0.62, 0.74],
      waveformDetail: [{ timeSec: 0, peak: 0.7, rms: 0.4, min: -0.5, max: 0.7 }],
      spectralBands: [{ timeSec: 0, low: 0.4, mid: 0.7, high: 0.5 }],
      transientMarkers: [{ index: 0, timeSec: 0, strength: 0.76 }],
      cueCandidates: [
        {
          id: 'first-downbeat',
          type: 'first_downbeat',
          startSec: 0,
          endSec: 4,
          confidence: 0.8,
          label: 'First downbeat'
        }
      ],
      analysisConfidence: 0.82,
      analysisQuality: {
        waveformDetail: 0.82,
        spectralBands: 0.8,
        transientMarkers: 0.72,
        beatGrid: 0.86
      }
    });

    const request = buildPlannerRequest({
      currentTrack,
      nextTrack,
      elapsedSec: 72,
      currentAnalysis,
      nextAnalysis,
      settings: {
        fadeDurationSec: 8,
        aiDjMode: 'balanced'
      }
    });

    expect(request.analysisSummary?.current).toMatchObject({
      plannerReady: true,
      bpm: 124,
      energyTrend: { direction: 'falling' },
      transients: { count: 2, strongCount: 1 },
      beatStability: {
        score: expect.any(Number),
        label: 'stable'
      },
      cues: {
        outro: {
          startSec: 88,
          confidence: 0.82
        }
      }
    });
    expect(request.analysisSummary?.current?.phrases.strongestBoundaries[0]).toMatchObject({
      startSec: 80,
      confidence: 0.88
    });
    expect(request.analysisSummary?.next).toMatchObject({
      plannerReady: true,
      energyTrend: { direction: 'rising' },
      cues: {
        firstDownbeat: {
          startSec: 0,
          confidence: 0.8
        }
      }
    });
  });
});
