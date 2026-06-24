# AI Mixing Review Import Readback Slice 12

## Scope

Slice 12 adds import/readback for exported mix review notes as review-only artifacts. Imported notes are shown in the inspector and can be opened in a read-only preview.

## What changed

- Added an in-memory imported mix review artifact model for JSON and Markdown/text note files.
- Added an Import action to the Mix Review Notes inspector group.
- JSON exports are decoded back through the mix review export schema and re-rendered as JSON for review.
- Markdown/text exports are kept as read-only note content with review/schema counts read from the exported note header when present.
- Added an imported artifact list and read-only preview sheet.

## Behavior boundary

Imported review artifacts are not appended to recent in-app review history, planner inputs, scheduler state, `executeTransition`, or `NativeAudioEngine`. They are read-only reference notes for review.

## Verification focus

- Native build should prove JSON/Markdown import, artifact preview, and open-panel wiring compile.
- Existing export renderer tests should continue proving Markdown and JSON exported note content preserves AI/fallback review details.
- Source audit should confirm imported artifacts are isolated from planner selection and playback paths.

## Next candidates

- Persist imported review artifacts between app launches.
- Add imported-artifact filtering by track pair.
- Add a saved export/import folder preference.
