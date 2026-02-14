import {
  PlayerSettings,
  TransitionAdvisor,
  TransitionContext,
  TransitionPlan
} from '../../shared/types';

const MIN_FADE_SEC = 0.5;
const END_SAFETY_SEC = 0.2;

export class RuleBasedAdvisor implements TransitionAdvisor {
  plan(ctx: TransitionContext, settings: PlayerSettings): TransitionPlan {
    const allowedFade = Math.max(MIN_FADE_SEC, ctx.current.durationSec - END_SAFETY_SEC);
    const fadeDuration = Math.min(settings.fadeDurationSec, allowedFade);
    const crossfadeEndAt = ctx.currentEndAt;
    const crossfadeStartAt = Math.max(
      ctx.currentStartAt + 0.05,
      crossfadeEndAt - fadeDuration
    );

    return {
      crossfadeStartAt,
      crossfadeEndAt
    };
  }
}
