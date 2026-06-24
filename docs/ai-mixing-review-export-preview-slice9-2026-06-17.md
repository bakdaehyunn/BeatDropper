# AI Mixing Review Export Preview Slice 9

## Scope

Slice 9 adds a read-only preview step before writing recent AI-vs-fallback mix review notes as Markdown or JSON. The preview uses the same export document and renderer that the save action writes.

## What changed

- Added a native export preview model containing the selected format, rendered content, and review count.
- Changed the Recent Mix Reviews export menu so Markdown and JSON actions open a preview sheet instead of saving immediately.
- Added a read-only, selectable, monospaced preview surface with Close and Export actions.
- Kept the save-panel action behind the preview sheet's Export button.

## Behavior boundary

The preview only renders recent review history text for inspection. It does not write files, read exported data back into BeatDropper, change planner selection, change scheduler timing, call `executeTransition`, or affect `NativeAudioEngine` playback.

## Verification focus

- Native build should prove the preview sheet and format-aware export path compile.
- Export renderer tests should continue proving Markdown and JSON content preserve AI/fallback review details.
- Source audit should confirm the save action is reached from the preview sheet and export code remains outside playback paths.

## Next candidates

- Add copy-to-clipboard from the preview sheet.
- Add preview filtering for the latest selected track pair.
- Add import/readback for exported notes as review-only artifacts.
