# AI Mixing Review Export Slice 7

## Scope

Slice 7 exports recent AI-vs-fallback mix review diffs as offline audition notes. The export is a Markdown file generated from the current in-memory review history.

## What changed

- Added a BeatDropperCore mix review export contract and Markdown renderer.
- Added native app mapping from recent mix review events to export notes.
- Added an inspector `Export` action in the Recent Mix Reviews section.
- Exported notes include track pair, event time, AI planner values, local fallback values, timing/candidate/style/confidence deltas, rendered-quality metric deltas, and quality issues.

## Behavior boundary

The export path only writes a user-selected Markdown file. Exported review data is not read back into planner selection, scheduler timing, `executeTransition`, or `NativeAudioEngine` playback.

## Verification focus

- Unit tests should prove Markdown notes include AI/fallback rows and issue notes.
- Native build and tests should prove the save-panel action and export formatter compile.
- Source audit should confirm export code is only invoked from review UI and does not affect playback paths.

## Next candidates

- Add JSON export alongside Markdown for downstream analysis.
- Add import/readback for exported notes as review-only artifacts.
- Add an opt-in quality gate only after explicit approval.
