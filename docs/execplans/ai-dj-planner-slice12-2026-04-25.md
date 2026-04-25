# ExecPlan: AI DJ Planner Slice 12

## Goal
- Export pairwise `MixPlan` comparison results as a shareable JSON artifact instead of leaving them only in the planner debug UI.

## Progress
- [x] Add a shared pairwise comparison/export contract and helper.
- [x] Reuse that helper in the renderer to copy/export comparison results.
- [x] Update docs to mention comparison artifact export.
- [x] Validate with tests and builds.

## Locked Decisions / Non-Goals
- Keep comparison export renderer-triggered and compare-only.
- Do not add import support for comparison artifacts in this slice.
- Reuse the existing imported-artifact workflow rather than adding a new storage layer.

## Code Orientation
- `src/shared/mixPlanComparison.ts`
- `src/renderer/App.tsx`
- `tests/unit/mixPlanComparison.test.ts`
- `README.md`
- `docs/PROJECT_OVERVIEW.md`

## Plan Of Work
1. Define shared types/builders for pairwise comparison rows and export envelope.
2. Replace renderer-local row assembly with the shared helper.
3. Add copy/export actions for the current comparison result.
4. Document that comparison artifacts are shareable JSON snapshots.

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

- `npm run test`: passed (`19` files, `63` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed

## Risks
- Comparison JSON can drift from the on-screen table if the renderer keeps custom formatting logic.
- Extra export buttons can crowd the planner debug drawer if labels are unclear.

## Backout
- Remove comparison export helper and UI actions.
- Fall back to on-screen comparison only.
