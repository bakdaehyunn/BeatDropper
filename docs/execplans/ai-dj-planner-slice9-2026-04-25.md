# ExecPlan: AI DJ Planner Slice 9

## Goal
- Add a safe import path for exported `MixPlan` envelopes so users can compare shared artifacts in the planner debug drawer without affecting playback.

## Progress
- [x] Lock import scope to debug comparison only.
- [x] Add a shared parser for exported `MixPlan` envelopes.
- [x] Add renderer UI to import one envelope JSON file and show comparison/debug details.
- [x] Update docs and validate with tests/builds.

## Locked Decisions / Non-Goals
- Imported files are informational only in this slice.
- Do not route imported files into `AudioEngine`.
- Do not add persistent storage for imported artifacts.

## Code Orientation
- `docs/design-freeze-ai-dj-planner-2026-04-25.md`
- `src/shared/mixPlanExport.ts`
- `src/renderer/App.tsx`
- `README.md`
- `docs/PROJECT_OVERVIEW.md`
- `tests/unit/mixPlanExport.test.ts`

## Plan Of Work
1. Extend the shared export contract with parse/validation helpers.
2. Add a renderer-only file import flow using a hidden file input.
3. Show imported artifact metadata and a compact comparison against the latest local `MixPlan`.
4. Document that imported files are debug-only and not playback overrides.

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

- `npm run test`: passed (`18` files, `61` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed

## Risks
- Import UI can imply playback authority if the copy is not explicit enough.
- Weak parsing would let malformed JSON appear as valid comparison data.

## Backout
- Remove the import button and comparison UI.
- Remove export-envelope parsing helpers.
- Revert the docs to export-only wording.
