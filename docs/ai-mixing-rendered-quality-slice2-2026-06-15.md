# AI Mixing Rendered Quality Slice 2

## Purpose

Slice 2 adds an offline rendered-transition quality estimate for planned crossfades. It uses existing `TrackAnalysis` waveform and spectral summaries plus the planned equal-power transition envelope to estimate audio risks before any future DSP executor applies mix controls.

## What It Measures

- `clipping_risk`: estimated summed transition peak exceeds the safe ceiling.
- `peak_jump`: estimated transition peak rises sharply relative to the surrounding current/next reference points.
- `rms_jump`: estimated transition RMS rises sharply relative to surrounding current/next reference points.
- `spectral_masking_risk`: current and next tracks overlap heavily in coarse low/mid/high bands during the crossfade.
- `missing_analysis`: one or both track analyses are unavailable, so fallback waveform points were used.

## Execution Boundary

This slice does not change `NativeAudioEngine`, deck scheduling, crossfade execution, EQ, filters, limiter behavior, LUFS analysis, stem separation, key detection, or realtime AI behavior. The analyzer is a pure `BeatDropperCore` estimate that can feed future planner gating, debug UI, or benchmark tooling.

## Implementation Notes

- The analyzer samples the planned transition window and applies `CrossfadeMath.equalPowerGains`.
- Optional `MixPlan.mixControls.gain` trims are included in the estimate because they are already validated metadata.
- Peak is estimated conservatively by summing outgoing and incoming peak envelopes.
- RMS is estimated by root-sum-square of outgoing and incoming RMS envelopes.
- Spectral masking uses coarse low/mid/high overlap weighted toward low and mid bands.

## Future Use

1. Attach rendered-quality reports to planner/fallback events for debug review.
2. Add benchmark cases that compare candidate plans by rendered-quality score.
3. Gate risky plans before playback once product UX defines how aggressive rejection should be.
4. Add actual rendered audio validation after native DSP execution exists.
