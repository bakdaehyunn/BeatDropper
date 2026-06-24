# AI Mixing Review Selected Pair Export Preview Slice 11

## Scope

Slice 11 adds preview filtering for the latest selected track pair in the mix review export preview. The preview can still show all recent reviews, or it can render only the newest review event matching the currently selected playlist track and its next available track.

## What changed

- Added an explicit export preview scope for all recent reviews versus the latest selected pair.
- Added `All Recent` and `Latest Selected Pair` choices before selecting Markdown or JSON preview output.
- Disabled the selected-pair preview scope when there is no matching recent review event.
- Made the preview Export action write the exact preview content, so filtered Markdown and JSON previews export the same filtered text the user inspected.

## Behavior boundary

Selected-pair filtering only narrows the review events rendered into the preview. It does not write files until the preview sheet's Export action, read exported data back into BeatDropper, change planner selection, change scheduler timing, call `executeTransition`, or affect `NativeAudioEngine` playback.

## Verification focus

- Native build should prove the scoped preview menu and filtered export path compile.
- Export renderer tests should continue proving Markdown and JSON content preserve AI/fallback review details.
- Source audit should confirm selected-pair filtering is only used by review preview/export UI and remains outside playback paths.

## Next candidates

- Add import/readback for exported notes as review-only artifacts.
- Add a saved export destination preference.
- Add an opt-in quality gate only after explicit approval.
