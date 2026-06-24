# AI Mixing Plan Acceptance Gate Slice 23

## Scope

Slice 23 adds a diagnostic-based acceptance gate between the AI planner result and the local fallback plan. The app no longer accepts an AI plan blindly when rendered quality and planner diagnostics show the fallback is safer for the same transition pair.

## What changed

- Added `MixPlanAcceptanceGate` in core so AI-vs-fallback selection is shared by the native app and native planner benchmarks.
- Accepted AI plans when diagnostics are equivalent, AI stronger, incomplete, or mixed with only non-critical differences.
- Accepted local fallback when diagnostics classify fallback as stronger, when AI rendered quality is `REJECT` while fallback is usable, or when material planning evidence favors fallback.
- Moved native app assignment through the acceptance decision before `currentMixPlan` is set.
- Preserved the rejected plan as comparison evidence in recent review history when both AI and fallback plans are available.
- Updated the native planner benchmark report to schema version `2`, adding `selectedPlan`, `rejectedPlan`, `selectedPlanRole`, and `acceptanceDecision`. The legacy `plan` field remains the local fallback benchmark plan for compatibility with existing fallback benchmark checks.
- Added focused gate tests for AI accepted, fallback accepted for weaker quality, fallback accepted for stronger fallback candidate mismatch, reject-quality AI fallback, and missing metrics not forcing fallback by themselves.

## Behavior boundary

The gate only chooses between an already validated AI plan and an already built local fallback comparison. It does not change planner prompt wording, planner contract fields, scheduler timing, transition execution, audio engine behavior, persistence schema, or imported artifact inputs.

## Verification focus

- Unit tests should prove the acceptance decision matrix independently of the native app model.
- Benchmark tests should prove selected/rejected outcome evidence is present and exactly one comparison row is selected.
- Native app source audit should confirm the gate runs before `currentMixPlan` assignment and that scheduler, `executeTransition`, and audio engine paths still consume only the selected plan.
- Benchmark JSON consumers should read schema version `2` for selected/rejected outcome fields; schema version `1` reports remain historical comparison-only output.
