# AI Mixing Review Artifact Persistence Slice 13

## Scope

Slice 13 persists imported mix review artifacts between app launches. Imported artifacts remain review-only references and are restored separately from recent in-app mix review history.

## What changed

- Added a BeatDropperCore mix review artifact store backed by `mix-review-artifacts.json`.
- Added primary-file plus backup-file load behavior for imported artifact state.
- Restored imported artifacts during native app model initialization.
- Saved imported artifacts after successful import/readback.
- Kept the persisted artifact list capped to the 12 most recent imported artifacts.

## Behavior boundary

Persisted imported artifacts are not written into recent mix review history, planner inputs, scheduler state, `executeTransition`, or `NativeAudioEngine`. Restore only repopulates the read-only imported artifact list shown in the inspector.

## Verification focus

- Unit tests should prove imported artifacts save, load, fall back to backup, and are capped.
- Native build should prove the app model restore/save wiring compiles.
- Source audit should confirm persistence remains isolated from planner and playback paths.

## Next candidates

- Add imported-artifact filtering by track pair.
- Add a saved export/import folder preference.
- Add review-only annotations on imported artifacts.
