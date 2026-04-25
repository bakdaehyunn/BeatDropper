# ExecPlan: AI DJ Planner Slice 13

## Goal
- Add track identity and analysis metadata to exported `MixPlan` and pairwise comparison artifacts so shared JSON keeps enough context for later review.

## Progress
- [x] Extend `MixPlan` export envelopes with optional track/analysis context.
- [x] Include subject context in comparison export envelopes.
- [x] Keep older export files readable when context is missing.
- [x] Update docs and validate with tests/builds.

## Locked Decisions / Non-Goals
- New context is additive and backward-compatible.
- Imported artifacts without context remain valid and compare-only.
- Do not add playback-safe import or new persistence in this slice.

## Code Orientation
- `src/shared/mixPlanExport.ts`
- `src/shared/mixPlanComparison.ts`
- `src/renderer/App.tsx`
- `tests/unit/mixPlanExport.test.ts`
- `tests/unit/mixPlanComparison.test.ts`

## Plan Of Work
1. Define a shared export context summary for track identity and analysis counts/confidence.
2. Attach local planner-request context to new `MixPlan` exports when available.
3. Carry subject context into comparison export envelopes.
4. Document the enriched artifacts and keep parsing backward-compatible.

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

- `npm run test`: passed (`19` files, `64` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed

## Risks
- Context parsing can get too permissive and hide malformed artifacts.
- UI code can drift again if context summaries are rebuilt ad hoc in the renderer.

## Backout
- Remove the new export context fields and helper functions.
- Revert tests/docs to metadata-free comparison artifacts.
