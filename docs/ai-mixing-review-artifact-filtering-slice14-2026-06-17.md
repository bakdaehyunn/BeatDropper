# AI Mixing Review Artifact Filtering Slice 14

## Scope

Slice 14 adds track-pair filtering for imported mix review artifacts. Imported artifacts remain read-only references and filtering only changes which imported artifacts are shown in the inspector.

## What changed

- Added track-pair metadata to persisted imported artifact state.
- Added a core pair extractor for BeatDropper JSON exports and BeatDropper-generated Markdown headings.
- Added a selected-pair filter projection for imported artifacts in the native app model.
- Added a compact inspector toggle to show all imported artifacts or only artifacts matching the selected current-to-next pair.
- Kept imported artifacts capped to the 12 most recent imports.

## Behavior boundary

Filtering does not write imported artifacts into recent in-app mix review history, planner inputs, scheduler state, `executeTransition`, or `NativeAudioEngine`. It only changes the read-only imported artifact list shown in the inspector.

## Verification focus

- Unit tests should prove JSON and Markdown pair extraction, deduping, and old persisted artifact decoding.
- Store tests should prove track-pair metadata survives save/load.
- Native build should prove the inspector and app-model filter wiring compiles.
- Source audit should confirm the filter is isolated from planner and playback paths.

## Next candidates

- Add pair chips or search across imported artifact pairs.
- Add review-only annotations on imported artifacts.
- Add a saved export/import folder preference.
