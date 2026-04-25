# ExecPlan: AI DJ Planner Slice 8

## Goal
- Promote `MixPlan` export from a renderer-local object shape to a shared contract/helper and document the export envelope explicitly.

## Progress
- [x] Add a shared `MixPlan` export envelope contract and builder.
- [x] Refactor renderer export/debug metadata to use the shared helper.
- [x] Document the envelope format in README and overview docs.
- [x] Validate with tests and builds.

## Locked Decisions / Non-Goals
- Keep export as a file-generation feature only.
- Do not implement import/apply-from-file in this slice.
- Keep the envelope backward-compatible with the current metadata shape: exported file still contains `planner` and `mixPlan`.

## Code Orientation
- `src/shared/mixPlanExport.ts`
- `src/renderer/App.tsx`
- `README.md`
- `docs/PROJECT_OVERVIEW.md`
- `tests/unit/mixPlanExport.test.ts`

## Plan Of Work
1. Define the shared export envelope types and builder helper.
2. Replace renderer-local export envelope assembly with the shared helper.
3. Reuse the same shared metadata shape for the planner debug drawer.
4. Document the JSON format and note that import is not implemented.

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

- `npm run test`: passed (`18` files, `59` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed

## Risks
- Export metadata can drift again if renderer keeps its own parallel shape.
- README examples can get stale unless they match the shared contract.

## Backout
- Remove `src/shared/mixPlanExport.ts`.
- Revert `App.tsx` to inline export/debug metadata assembly.
- Remove the README export-format section.
