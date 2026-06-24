# AI Mixing Planner Quality Diagnostics Slice 22

## Scope

Slice 22 pivots the review artifact work back toward core AI mixing quality. It adds tested diagnostics that classify where an AI planner plan is weaker than the local fallback baseline for the same transition pair.

## What changed

- Added a core `MixReviewPlannerDiagnostics` classifier for AI-vs-fallback plan comparison.
- Classified planner weaknesses for timing, candidate choice, confidence, rendered quality, rendered metric scores, and missing rendered metric evidence.
- Attached diagnostic summaries to native planner benchmark results so benchmark output can explain why an AI fixture is weaker, stronger, mixed, equivalent, or incomplete against fallback.
- Added diagnostics to the native planner benchmark text and JSON reports.
- Added focused tests for timing weakness, quality weakness, candidate mismatch, confidence weakness, and missing metric evidence.

## Behavior boundary

Diagnostics are evidence only. They do not change planner prompts, planner scoring, transition execution, scheduler timing, audio engine behavior, playback behavior, imported artifact persistence schema, or whether imported artifacts become planner inputs.

## Verification focus

- Unit tests should prove weakness classification for timing, candidate choice, confidence, quality, and missing rendered metrics.
- Benchmark tests should prove default benchmark cases carry diagnostics alongside rendered-quality comparisons.
- Native build and full native tests should prove the benchmark report additions compile without changing planner behavior.
- Source audit should confirm diagnostics remain outside playback and prompt contract paths.

## Next candidates

- Use repeated `timing_worse` diagnostics to tune candidate timing selection or fallback-to-AI acceptance gates.
- Use repeated `candidate_mismatch` diagnostics to improve stale recommendation rejection in the planner.
- Use `metric_worse` diagnostics to identify whether peak, RMS, or masking should drive a planner quality penalty.
