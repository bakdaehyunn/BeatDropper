# AI Mixing AI Vs Fallback Comparison Slice 5

## Scope

Slice 5 compares accepted AI planner output against local fallback output in the native review path and planner benchmarks. The comparison is diagnostic only.

## What changed

- Successful CLI planner results now carry a shadow local fallback plan for review.
- `PlannedMixReview` and recent review events retain the shadow fallback timing, style, confidence, candidate ID, and rendered quality.
- The Mix Pair Inspector shows active and recent AI-vs-fallback quality comparisons.
- Native planner benchmarks include an AI fixture plan and a local fallback plan for every default case.
- Planner benchmark text output prints `quality ai` and `quality fallback` rows with a score delta.
- Planner benchmark JSON includes `aiPlannerPlan` and role-labeled `qualityComparisons`.

## Behavior boundary

The shadow fallback plan is never assigned to `currentMixPlan` after a successful CLI plan. Scheduler decisions, `executeTransition`, and `NativeAudioEngine` playback still read only the accepted plan.

## Verification focus

- Native planner benchmark tests should require both `ai_planner` and `local_fallback` comparison rows.
- Planner benchmark text and JSON reports should expose the AI-vs-fallback rows.
- Source audit should confirm `shouldApply` and shadow fallback quality are not used as playback gates.

## Next candidates

- Export recent review history for offline audition notes.
- Add a side-by-side diff view for timing, candidate, and rendered-quality metrics.
- Add a user-approved quality gate only after comparison data has been reviewed.
