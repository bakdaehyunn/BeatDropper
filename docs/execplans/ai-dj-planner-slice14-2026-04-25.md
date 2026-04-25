# ExecPlan: AI DJ Planner Slice 14

## Goal
- Re-import exported pairwise comparison artifacts into the planner debug session so review can continue later without rebuilding the comparison by hand.

## Progress
- [x] Add a shared parser for comparison export artifacts.
- [x] Add renderer session state and UI for imported comparison artifacts.
- [x] Keep older comparison exports readable when context is missing.
- [x] Update docs and validate with tests/builds.

## Locked Decisions / Non-Goals
- Imported comparison artifacts are review-only and do not affect playback or planner execution.
- Keep imported comparison artifacts renderer-local and session-scoped.
- Do not merge imported comparison artifacts back into the live pairwise comparison builder in this slice.

## Code Orientation
- `src/shared/mixPlanComparison.ts`
- `src/renderer/App.tsx`
- `src/renderer/styles/app.css`
- `tests/unit/mixPlanComparison.test.ts`
- `README.md`
- `docs/PROJECT_OVERVIEW.md`

## Plan Of Work
1. Add parsing/validation for comparison export envelopes.
2. Add a hidden file input and session list for imported comparison artifacts.
3. Show selected imported comparison JSON and row table in the debug drawer.
4. Document that imported comparison artifacts are review snapshots only.

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
- Planner debug can get crowded if imported comparison and live comparison controls are not clearly separated.
- Parsing must accept older comparison artifacts without context while still rejecting malformed rows.

## Backout
- Remove the comparison-artifact parser and import UI.
- Fall back to export-only pairwise comparison artifacts.
