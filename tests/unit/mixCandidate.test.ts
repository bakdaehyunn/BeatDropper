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
      energyProfile: [0.9, 0.6, 0.4],
      analysisConfidence: 0.86,
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
      energyProfile: [0.2, 0.5, 0.75],
      analysisConfidence: 0.84,
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
    expect(context.candidates[0]).toMatchObject({
      currentTrackId: 'current',
      nextTrackId: 'next',
      bpmDelta: 2,
      tempoSyncRate: expect.any(Number),
      confidence: expect.any(Number)
    });
    expect(context.candidates[0]?.reason).toContain('BPM delta');
  });
});
