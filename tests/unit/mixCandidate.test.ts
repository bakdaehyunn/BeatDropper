import { sanitizeTrackAnalysis } from '../../src/shared/analysis';
import { buildMixPairContext } from '../../src/shared/mixCandidate';
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

describe('buildMixPairContext', () => {
  it('ranks phrase-aware candidates with BPM and energy evidence', () => {
    const currentAnalysis = sanitizeTrackAnalysis('current', {
      bpm: 124,
      bpmConfidence: 0.8,
      introCueSec: 0,
      outroCueSec: 160,
      beatGridSec: [144, 145.9, 147.8, 149.7, 151.6, 153.5, 155.4, 157.3, 159.2],
      downbeatsSec: [144, 151.6, 159.2],
      barGrid: [
        { index: 18, startSec: 144, beatIndex: 72 },
        { index: 19, startSec: 151.6, beatIndex: 76 },
        { index: 20, startSec: 159.2, beatIndex: 80 }
      ],
      phraseMarkers: [
        { index: 0, startSec: 144, bars: 8, confidence: 0.82 },
        { index: 1, startSec: 159.2, bars: 8, confidence: 0.82 }
      ],
      transientMarkers: [
        { index: 0, timeSec: 159.2, strength: 0.84 }
      ],
      energyProfile: [0.9, 0.6, 0.4],
      analysisConfidence: 0.86,
      analysisQuality: {
        waveformDetail: 0.8,
        spectralBands: 0.75,
        transientMarkers: 0.7,
        beatGrid: 0.8
      },
      cueCandidates: [
        {
          id: 'outro',
          type: 'outro',
          startSec: 160,
          endSec: 180,
          confidence: 0.8,
          label: 'Outro'
        }
      ]
    });
    const nextAnalysis = sanitizeTrackAnalysis('next', {
      bpm: 126,
      bpmConfidence: 0.82,
      introCueSec: 8,
      beatGridSec: [0, 1.9, 3.8, 5.7, 7.6, 9.5],
      downbeatsSec: [0, 7.6],
      barGrid: [
        { index: 0, startSec: 0, beatIndex: 0 },
        { index: 1, startSec: 7.6, beatIndex: 4 }
      ],
      phraseMarkers: [
        { index: 0, startSec: 0, bars: 8, confidence: 0.82 },
        { index: 1, startSec: 7.6, bars: 8, confidence: 0.82 }
      ],
      transientMarkers: [
        { index: 0, timeSec: 7.6, strength: 0.84 }
      ],
      energyProfile: [0.2, 0.5, 0.75],
      analysisConfidence: 0.84,
      analysisQuality: {
        waveformDetail: 0.8,
        spectralBands: 0.75,
        transientMarkers: 0.7,
        beatGrid: 0.8
      },
      cueCandidates: [
        {
          id: 'first-downbeat',
          type: 'first_downbeat',
          startSec: 7.6,
          endSec: 12,
          confidence: 0.8,
          label: 'First downbeat'
        }
      ]
    });

    const context = buildMixPairContext({
      currentTrack,
      nextTrack,
      currentAnalysis,
      nextAnalysis
    });

    expect(context.recommendedCandidateId).toBe(context.candidates[0]?.id);
    expect(context.readiness).toBe('ready');
    expect(context.candidates[0]).toMatchObject({
      currentTrackId: 'current',
      nextTrackId: 'next',
      source: 'analysis',
      evidenceLevel: 'strong',
      requiresAnalysisUpgrade: false,
      bpmDelta: 2,
      tempoSyncRate: expect.any(Number),
      confidence: expect.any(Number)
    });
    expect(context.candidates[0]?.reason).toContain('BPM delta');
  });

  it('marks tail timing as fallback when analysis is not ready', () => {
    const context = buildMixPairContext({
      currentTrack,
      nextTrack,
      currentAnalysis: null,
      nextAnalysis: null
    });

    expect(context.readiness).toBe('analysis_pending');
    expect(context.recommendedCandidateId).toBeNull();
    expect(context.candidates[0]).toMatchObject({
      source: 'tail_fallback',
      evidenceLevel: 'fallback',
      requiresAnalysisUpgrade: true
    });
    expect(context.candidates[0]?.confidence).toBeLessThanOrEqual(0.42);
  });

  it('uses strong cue-only analysis before tail fallback while detailed waveform is pending', () => {
    const currentAnalysis = sanitizeTrackAnalysis('current', {
      bpm: 124,
      bpmConfidence: 0.7,
      outroCueSec: 160,
      analysisConfidence: 0.62,
      analysisQuality: {
        waveformDetail: 0,
        spectralBands: 0,
        transientMarkers: 0,
        beatGrid: 0.48
      },
      cueCandidates: [
        {
          id: 'outro',
          type: 'outro',
          startSec: 160,
          endSec: 180,
          confidence: 0.78,
          label: 'Outro'
        }
      ]
    });
    const nextAnalysis = sanitizeTrackAnalysis('next', {
      bpm: 126,
      bpmConfidence: 0.72,
      introCueSec: 8,
      analysisConfidence: 0.6,
      analysisQuality: {
        waveformDetail: 0,
        spectralBands: 0,
        transientMarkers: 0,
        beatGrid: 0.46
      },
      cueCandidates: [
        {
          id: 'first-downbeat',
          type: 'first_downbeat',
          startSec: 8,
          endSec: 12,
          confidence: 0.76,
          label: 'First downbeat'
        }
      ]
    });

    const context = buildMixPairContext({
      currentTrack,
      nextTrack,
      currentAnalysis,
      nextAnalysis
    });

    expect(context.readiness).toBe('ready');
    expect(context.recommendedCandidateId).toBe(context.candidates[0]?.id);
    expect(context.candidates[0]).toMatchObject({
      source: 'cue',
      evidenceLevel: 'strong',
      requiresAnalysisUpgrade: false,
      currentMixOutSec: 160,
      nextMixInSec: 8
    });
    expect(context.candidates[0]?.score).toBeGreaterThan(0.42);
  });
});
