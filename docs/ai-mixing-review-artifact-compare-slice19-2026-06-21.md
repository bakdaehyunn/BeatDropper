# AI Mixing Review Artifact Compare Slice 19

## Scope

Slice 19 adds review-only side-by-side comparison for two imported mix review artifacts that include the selected current-to-next pair.

## What changed

- Added core comparison helpers for pair eligibility, selected-pair detail lookup, plan field rows, and deltas.
- Added native comparison selection state capped to two imported artifacts from the visible, selected-pair-matched artifact list.
- Added a compact imported artifact comparison sheet showing metadata, annotations, AI plan rows, fallback plan rows, and deltas.
- Added graceful metadata-only fallback when one or both artifacts do not have structured JSON pair details.

## Behavior boundary

Imported artifact comparison does not write imported artifacts into recent in-app mix review history, planner inputs, scheduler state, `executeTransition`, or `NativeAudioEngine`. It only displays review-only differences between imported artifacts.

## Verification focus

- Unit tests should prove comparison eligibility, selected-pair detail selection, delta formatting, and missing-detail fallback.
- Native build should prove the comparison controls and sheet compile.
- Source audit should confirm comparison state remains isolated from planner and playback paths.

## Next candidates

- Add explicit reset for the saved review artifact folder preference if users need to clear stale directories.
- Add reviewer labels or annotation timestamps if multi-user imported review becomes useful.
- Add export of a comparison summary if side-by-side findings need to be shared outside the app.
