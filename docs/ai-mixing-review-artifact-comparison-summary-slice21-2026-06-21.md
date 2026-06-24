# AI Mixing Review Artifact Comparison Summary Slice 21

## Scope

Slice 21 improves the imported artifact comparison review surface by making long timing deltas easier to scan and adding a review-only Markdown summary for the current selected imported artifact comparison.

## What changed

- Stacked labeled window delta parts in the comparison sheet so values like `start +0:04 end +0:08 dur +0:04` no longer depend on one narrow line.
- Added Copy Summary and Export Summary actions to the imported artifact comparison sheet.
- Added a core Markdown summary renderer for comparison metadata, annotations, selected pair, AI rows, fallback rows, timing deltas, confidence, quality, and rendered metric deltas.
- Escaped Markdown table cells so filenames or annotations with pipes and newlines do not break exported tables.
- Kept the summary path review-only; it reads the current comparison and writes clipboard or Markdown output only.

## Behavior boundary

Imported artifact comparison summaries do not affect playback, planner inputs, scheduler state, audio rendering, transition execution, imported artifact persistence schema, or recent in-app mix review history.

## Verification focus

- Unit tests should prove long window deltas include start, end, and duration components.
- Unit tests should prove summary metadata and annotations render.
- Unit tests should prove timing, confidence, quality, and rendered metric rows appear in the summary.
- Unit tests should prove missing metric values fall back to `--`.
- Unit tests should prove Markdown table pipes and newlines are escaped.
- Native build, accessibility, macOS shell, and source audit checks should confirm the UI and export surface compile and remain isolated from planner and playback paths.

## Next candidates

- Add optional side labels or reviewer aliases for imported artifacts if multiple reviewers use the same comparison workflow.
- Add a non-persistent preview of the generated summary before export if users need to inspect large comparisons before saving.
- Add a folder reset affordance if saved artifact directories become stale or confusing.
