# AI Mixing Review JSON Export Slice 8

## Scope

Slice 8 adds JSON export alongside the existing Markdown audition notes for recent AI-vs-fallback mix review diffs. Both formats are generated from the same in-memory review history export document.

## What changed

- Added pretty-printed, sorted-key JSON rendering for the BeatDropperCore mix review export document.
- Added a native export format selector so the Recent Mix Reviews inspector menu can write Markdown or JSON.
- Kept the exported JSON schema aligned with the Markdown source data: schema version, export time, track pair, AI planner plan, optional local fallback plan, timing/candidate/style/confidence values, rendered quality metrics, and quality issues.
- Added unit coverage that JSON output decodes back to the export contract with AI and fallback review details intact.

## Behavior boundary

The JSON export path only writes a user-selected file. Exported review data is not read back into planner selection, scheduler timing, `executeTransition`, or `NativeAudioEngine` playback.

## Verification focus

- Unit tests should prove JSON round-trips through `MixReviewExportDocument`.
- Native build and tests should prove both export formats compile through the app target.
- Source audit should confirm export code is only invoked from review UI and does not affect playback paths.

## Next candidates

- Add a small export preview before writing files.
- Add import/readback for exported notes as review-only artifacts.
- Add an opt-in quality gate only after explicit approval.
