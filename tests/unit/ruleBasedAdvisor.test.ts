import { DEFAULT_SETTINGS } from '../../src/shared/settings';
import { RuleBasedAdvisor } from '../../src/renderer/player/ruleBasedAdvisor';
import { TransitionContext } from '../../src/shared/types';

const buildContext = (durationSec: number): TransitionContext => ({
  current: {
    id: 'current',
    title: 'Current',
    durationSec,
    format: 'mp3'
  },
  next: {
    id: 'next',
    title: 'Next',
    durationSec: 200,
    format: 'mp3'
  },
  currentStartAt: 10,
  currentEndAt: 10 + durationSec
});

describe('RuleBasedAdvisor', () => {
  it('calculates crossfade as end - fadeDuration', () => {
    const advisor = new RuleBasedAdvisor();
    const plan = advisor.plan(buildContext(120), {
      ...DEFAULT_SETTINGS,
      fadeDurationSec: 8
    });

    expect(plan.crossfadeEndAt).toBe(130);
    expect(plan.crossfadeStartAt).toBe(122);
  });

  it('caps fade duration for short tracks', () => {
    const advisor = new RuleBasedAdvisor();
    const plan = advisor.plan(buildContext(2), {
      ...DEFAULT_SETTINGS,
      fadeDurationSec: 8
    });

    expect(plan.crossfadeEndAt).toBe(12);
    expect(plan.crossfadeStartAt).toBeGreaterThan(10);
    expect(plan.crossfadeStartAt).toBeLessThanOrEqual(11.5);
  });
});
