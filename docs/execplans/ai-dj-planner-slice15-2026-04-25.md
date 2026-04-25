# ExecPlan: AI DJ Planner Slice 15

## Goal
- Add a direct review view that compares the selected imported comparison snapshot against the current live pairwise comparison.

## Progress
- [x] Add renderer-side live-vs-imported comparison view state/rows.
- [x] Show both comparison metadata and row deltas in the planner debug drawer.
- [x] Keep the new review flow compare-only and session-local.
- [x] Update docs and validate with tests/builds.

## Locked Decisions / Non-Goals
- Do not modify playback or planner execution based on imported comparison snapshots.
- Reuse existing live comparison and imported comparison state.
- Do not export this new review view in this slice.

## Code Orientation
- `src/renderer/App.tsx`
- `src/renderer/styles/app.css`
- `README.md`
- `docs/PROJECT_OVERVIEW.md`

## Plan Of Work
1. Build a live comparison envelope from the current pairwise compare state when available.
2. Align imported-vs-live comparison rows by metric label.
3. Add a review panel that shows live/imported pairwise metadata and row-by-row differences.
4. Update docs and validate.

## Validation Commands
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
```

## Validation Results
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
```

- `npm run test`: passed (`19` files, `66` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed

## Risks
- The planner drawer can become visually dense if the new review panel is not clearly separated.
- Live/imported comparisons may refer to different track pairs, so the UI must make the compared subjects explicit.

## Backout
- Remove the live-vs-imported review panel and related row alignment logic.
- Fall back to separate live comparison and imported comparison review sections.
