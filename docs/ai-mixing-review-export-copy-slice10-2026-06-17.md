# AI Mixing Review Export Copy Slice 10

## Scope

Slice 10 adds copy-to-clipboard from the read-only mix review export preview for both Markdown and JSON notes. Copy uses the already-rendered preview content.

## What changed

- Added a native clipboard helper for mix review export previews.
- Added a `Copy Markdown` or `Copy JSON` action to the preview sheet.
- Kept file writing behind the preview sheet's separate Export action.
- Kept Markdown and JSON copy output aligned with the same export document used for file export.

## Behavior boundary

Copy only writes preview text to the macOS pasteboard. It does not write files, read exported data back into BeatDropper, change planner selection, change scheduler timing, call `executeTransition`, or affect `NativeAudioEngine` playback.

## Verification focus

- Native build should prove the pasteboard helper and preview action compile.
- Export renderer tests should continue proving Markdown and JSON content preserve AI/fallback review details.
- Source audit should confirm copy is only reachable from the preview sheet and remains outside playback paths.

## Next candidates

- Add preview filtering for the latest selected track pair.
- Add import/readback for exported notes as review-only artifacts.
- Add an opt-in quality gate only after explicit approval.
