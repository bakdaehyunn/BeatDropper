# AI Mixing Review Artifact Compare Deltas Slice 20

## Scope

Slice 20 makes imported artifact comparison deltas more complete and review-safe. It tightens timing comparison and adds rendered-quality metric rows to the side-by-side imported artifact compare sheet.

## What changed

- Changed the comparison `Window` delta to include transition start, transition end, and duration differences.
- Added a separate `Duration` row for transition-window length comparison.
- Added rendered-quality metric rows for estimated peak, peak jump, RMS jump, and spectral masking.
- Added missing-metric fallback so metric rows show `--` instead of inventing a score delta.
- Kept the existing comparison row contract so the native comparison sheet renders the expanded rows without persistence or planner changes.

## Behavior boundary

Imported artifact comparison deltas remain review-only. They do not write imported artifacts into recent in-app mix review history, planner inputs, scheduler state, `executeTransition`, or `NativeAudioEngine`.

## Verification focus

- Unit tests should prove same-start/different-end windows no longer report `same`.
- Unit tests should prove duration, confidence, quality, and rendered metric deltas are formatted.
- Unit tests should prove missing rendered metrics fall back to `--`.
- Native build should prove the wider comparison delta column and expanded rows compile.
- Source audit should confirm comparison deltas remain isolated from planner and playback paths.

## Next candidates

- Add export of a comparison summary if side-by-side findings need to be shared outside the app.
- Add reviewer labels or annotation timestamps if multi-user imported review becomes useful.
- Add explicit reset for the saved review artifact folder preference if users need to clear stale directories.
