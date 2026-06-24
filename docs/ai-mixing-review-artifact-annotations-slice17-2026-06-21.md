# AI Mixing Review Artifact Annotations Slice 17

## Scope

Slice 17 adds review-only annotations to imported mix review artifacts. Annotations are editable notes on imported artifacts and are saved with the artifact store.

## What changed

- Added a persisted `reviewAnnotation` field to imported artifact state.
- Added a small annotation character cap at the artifact store boundary.
- Added native model helpers for reading and updating imported artifact annotations.
- Added a review annotation editor to the imported artifact detail panel.
- Added an annotated indicator on imported artifact rows.
- Included annotations in imported artifact search.

## Behavior boundary

Annotations do not write imported artifacts into recent in-app mix review history, planner inputs, scheduler state, `executeTransition`, or `NativeAudioEngine`. They only save review-only notes on imported artifacts.

## Verification focus

- Unit tests should prove annotations persist, decode backward compatibly, are capped, and participate in artifact search.
- Native build should prove the annotation editor and model wiring compiles.
- Source audit should confirm annotations remain isolated from planner and playback paths.

## Next candidates

- Add a saved export/import folder preference.
- Add side-by-side compare between two imported artifacts for the same pair.
- Add annotation timestamps or reviewer labels if multi-user review becomes useful.
