import { validateAndClampMixPlan } from '../../src/shared/mixPlan';

describe('validateAndClampMixPlan', () => {
  it('clamps timing, offset, confidence, and tempo sync rate into safe ranges', () => {
    const result = validateAndClampMixPlan(
      {
        transitionStartSec: 5,
        transitionEndSec: 40,
        nextTrackStartOffsetSec: -3,
        style: 'energy_swap',
        confidence: 4,
        tempoSync: {
          enabled: true,
          targetRate: 2
        }
      },
      {
        currentPlaybackElapsedSec: 18,
        currentTrackDurationSec: 30,
        nextTrackDurationSec: 200,
        maxFadeDurationSec: 8
      }
    );

    expect(result.reason).toBeNull();
    expect(result.plan).toMatchObject({
      transitionStartSec: 22,
      transitionEndSec: 30,
      nextTrackStartOffsetSec: 0,
      style: 'energy_swap',
      confidence: 1,
      tempoSync: {
        enabled: true,
        targetRate: 1.15
      }
    });
  });

  it('rejects missing timing fields', () => {
    const result = validateAndClampMixPlan(
      {
        nextTrackStartOffsetSec: 12
      },
      {
        currentPlaybackElapsedSec: 10,
        currentTrackDurationSec: 120,
        nextTrackDurationSec: 120,
        maxFadeDurationSec: 8
      }
    );

    expect(result.plan).toBeNull();
    expect(result.reason).toBe('mix_plan_missing_timing');
  });
});
