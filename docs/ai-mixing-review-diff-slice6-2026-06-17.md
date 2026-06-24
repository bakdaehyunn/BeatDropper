# AI Mixing Review Diff Slice 6

## Scope

Slice 6 adds a side-by-side review diff for AI planner output versus local fallback output. The diff is shown in the native Mix Pair Inspector and remains diagnostic only.

## What changed

- Active AI mix reviews now show AI and fallback values side by side.
- The diff includes transition window, next-in offset, candidate ID, style, confidence, rendered quality, and rendered-quality metrics.
- Recent review events now show compact AI/Fallback quality scores and score delta.
- The view keeps the existing active plan summary and top issues, then adds the diff for comparison.

## Behavior boundary

The diff does not change planner selection, scheduler timing, `executeTransition`, or `NativeAudioEngine` playback. It reads the accepted plan and the shadow fallback comparison only for review.

## Verification focus

- Native build should prove the SwiftUI diff compiles.
- Native UI/static checks should still pass after adding denser inspector rows.
- Source audit should confirm fallback comparison data is displayed only in inspector/review surfaces.

## Next candidates

- Add a one-click export for recent review diffs.
- Add benchmark JSON summaries for AI-vs-fallback timing and metric deltas.
- Use review data to design an opt-in quality gate only after explicit approval.
