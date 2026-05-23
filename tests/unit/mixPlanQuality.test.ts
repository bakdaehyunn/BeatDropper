import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION, TrackAnalysis } from '../../src/shared/analysis';
import { evaluateMixPlanQuality } from '../../src/shared/mixPlanQuality';
import { DEFAULT_SETTINGS } from '../../src/shared/settings';
import { Track } from '../../src/shared/types';

const currentTrack: Track = {
  id: 'current',
  title: 'Current',
  durationSec: 192,
  format: 'mp3',
  bpm: 124
};

const nextTrack: Track = {
  id: 'next',
  title: 'Next',
  durationSec: 196,
  format: 'mp3',
  bpm: 126
};

const bars = (startSec: number, count: number, intervalSec: number, firstIndex = 0) =>
  Array.from({ length: count }, (_item, index) => ({
    index: firstIndex + index,
    startSec: startSec + index * intervalSec,
    beatIndex: (firstIndex + index) * 4
  }));

const buildAnalysis = (
  trackId: string,
  input: {
    bpm: number;
    bars: ReturnType<typeof bars>;
    cueSec: number;
    cueType: 'outro' | 'first_downbeat';
    energyProfile: number[];
  }
): TrackAnalysis =>
  sanitizeTrackAnalysis(trackId, {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    bpm: input.bpm,
    bpmConfidence: 0.88,
    beatGridSec: input.bars.flatMap((bar) => [
      bar.startSec,
      bar.startSec + 1,
      bar.startSec + 2,
      bar.startSec + 3
    ]),
    downbeatsSec: input.bars.map((bar) => bar.startSec),
    barGrid: input.bars,
    phraseMarkers: input.bars
      .filter((bar) => bar.index % 8 === 0)
      .map((bar, index) => ({
        index,
        startSec: bar.startSec,
        bars: 8,
        confidence: 0.84
      })),
    introCueSec: input.cueType === 'first_downbeat' ? input.cueSec : 0,
    outroCueSec: input.cueType === 'outro' ? input.cueSec : null,
    energyProfile: input.energyProfile,
    waveformDetail: [{ timeSec: input.cueSec, peak: 0.7, rms: 0.45, min: -0.4, max: 0.7 }],
    transientMarkers: [{ index: 0, timeSec: input.cueSec, strength: 0.82 }],
    cueCandidates: [
      {
        id: input.cueType,
        type: input.cueType,
        startSec: input.cueSec,
        endSec: input.cueSec + 8,
        confidence: 0.86,
        label: input.cueType
      }
    ],
    analysisConfidence: 0.86,
    analysisQuality: {
      waveformDetail: 0.8,
      spectralBands: 0.7,
      transientMarkers: 0.8,
      beatGrid: 0.86
    }
  });

describe('evaluateMixPlanQuality', () => {
  it('scores phrase-aware tempo-synced plans as applicable', () => {
    const currentAnalysis = buildAnalysis('current', {
      bpm: 124,
      bars: bars(128, 5, 8, 12),
      cueSec: 160,
      cueType: 'outro',
      energyProfile: [0.78, 0.68, 0.44, 0.38]
    });
    const nextAnalysis = buildAnalysis('next', {
      bpm: 126,
      bars: bars(0, 5, 8, 0),
      cueSec: 0,
      cueType: 'first_downbeat',
      energyProfile: [0.5, 0.62, 0.72, 0.8]
    });

    const result = evaluateMixPlanQuality({
      plan: {
        transitionStartSec: 160,
        transitionEndSec: 168,
        nextTrackStartOffsetSec: 0,
        style: 'smooth_blend',
        confidence: 0.86,
        reasoningSummary: 'outro to first downbeat',
        tempoSync: {
          enabled: true,
          targetRate: 124 / 126
        },
        currentBarIndex: 16,
        nextBarIndex: 0,
        phraseAlignment: 'aligned',
        energyStrategy: 'lift'
      },
      currentTrack,
      nextTrack,
      currentAnalysis,
      nextAnalysis,
      settings: DEFAULT_SETTINGS,
      currentPlaybackElapsedSec: 120
    });

    expect(result.shouldApply).toBe(true);
    expect(result.grade).toMatch(/excellent|good/);
    expect(result.score).toBeGreaterThan(0.8);
    expect(result.issues).toEqual([]);
  });

  it('flags plans that miss outro, intro, bar, phrase, tempo, and fade constraints', () => {
    const currentAnalysis = buildAnalysis('current', {
      bpm: 124,
      bars: bars(128, 5, 8, 16),
      cueSec: 160,
      cueType: 'outro',
      energyProfile: [0.8, 0.72, 0.42, 0.34]
    });
    const nextAnalysis = buildAnalysis('next', {
      bpm: 126,
      bars: bars(0, 5, 8, 0),
      cueSec: 0,
      cueType: 'first_downbeat',
      energyProfile: [0.2, 0.3, 0.88, 0.94]
    });

    const result = evaluateMixPlanQuality({
      plan: {
        transitionStartSec: 51.3,
        transitionEndSec: 52.1,
        nextTrackStartOffsetSec: 91.4,
        style: 'smooth_blend',
        confidence: 0.24,
        reasoningSummary: null,
        tempoSync: {
          enabled: true,
          targetRate: 1.15
        },
        phraseAlignment: 'aligned',
        energyStrategy: 'drop'
      },
      currentTrack,
      nextTrack,
      currentAnalysis,
      nextAnalysis,
      settings: DEFAULT_SETTINGS,
      currentPlaybackElapsedSec: 40
    });

    expect(result.shouldApply).toBe(false);
    expect(result.grade).toMatch(/weak|reject/);
    expect(result.score).toBeLessThan(0.45);
    expect(result.issues.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        'fade_window_too_short',
        'current_timing_before_outro',
        'next_timing_far_from_intro',
        'bar_alignment_off',
        'phrase_alignment_mismatch',
        'tempo_sync_mismatch'
      ])
    );
  });

  it('does not reject a bounded plan solely because detailed analysis is unavailable', () => {
    const result = evaluateMixPlanQuality({
      plan: {
        transitionStartSec: 176,
        transitionEndSec: 184,
        nextTrackStartOffsetSec: 0,
        style: 'smooth_blend',
        confidence: 0.58,
        reasoningSummary: null,
        tempoSync: {
          enabled: false,
          targetRate: null
        },
        phraseAlignment: null,
        energyStrategy: null
      },
      currentTrack,
      nextTrack,
      currentAnalysis: null,
      nextAnalysis: null,
      settings: {
        ...DEFAULT_SETTINGS,
        aiDjMode: 'adventurous'
      },
      currentPlaybackElapsedSec: 90
    });

    expect(result.shouldApply).toBe(true);
    expect(result.issues.some((issue) => issue.severity === 'critical')).toBe(false);
  });
});
