# AI Mixing Review Artifact Folder Preference Slice 18

## Scope

Slice 18 adds a saved export/import folder preference for mix review artifacts. The preference only affects the starting directory for mix review note export and import panels.

## What changed

- Added `mixReviewArtifactFolderPath` to native player settings.
- Preserved the folder path through settings sanitize, save/load, backup fallback, and Electron settings migration.
- Used the saved folder as the initial directory for mix review export and import panels when it still exists.
- Updated the preference after successful mix review export or import.

## Behavior boundary

The saved folder preference does not write imported artifacts into recent in-app mix review history, planner inputs, scheduler state, `executeTransition`, or `NativeAudioEngine`. It only changes the file-panel starting folder for review artifact import/export.

## Verification focus

- Unit tests should prove the folder path defaults to nil, trims non-empty paths, drops empty paths, and migrates from Electron settings.
- Native build should prove the export/import panel wiring compiles.
- Source audit should confirm the preference remains isolated from review file panels and settings persistence.

## Next candidates

- Add side-by-side compare between two imported artifacts for the same pair.
- Add annotation timestamps or reviewer labels if multi-user review becomes useful.
- Add an explicit reset action for the review artifact folder preference if needed.
