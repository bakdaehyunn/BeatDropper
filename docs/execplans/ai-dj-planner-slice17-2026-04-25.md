# ExecPlan: AI DJ Planner Slice 17

## Goal
- Make `safe`, `balanced`, and `adventurous` heuristic outputs more clearly differentiated on the same request.

## Progress
- [x] Refine heuristic style policy so `balanced` stays conservative on strong cue support while `adventurous` stays more aggressive.
- [x] Add explicit planner-script tests for mode-specific prompt guidance and heuristic differentiation.
- [x] Re-run validation and script syntax checks.

## Locked Decisions / Non-Goals
- Keep the planner request contract unchanged.
- Keep the tuning inside planner scripts only.
- Do not change `AudioEngine` or analysis generation in this slice.

## Code Orientation
- `scripts/heuristic-mix-planner.cjs`
- `tests/unit/plannerScripts.test.ts`

## Validation Commands
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
node --check scripts/codex-mix-planner.cjs
node --check scripts/heuristic-mix-planner.cjs
```

## Validation Results
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
node --check scripts/codex-mix-planner.cjs
node --check scripts/heuristic-mix-planner.cjs
```

- `npm run test`: passed (`20` files, `71` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed
- `node --check scripts/codex-mix-planner.cjs`: passed
- `node --check scripts/heuristic-mix-planner.cjs`: passed

## Risks
- Mode policies can still feel too subtle on some track pairs even if the tests show differentiation.
- More aggressive adventurous behavior may need later tuning against real-world logs.

## Backout
- Revert the latest heuristic style-policy adjustment and mode-differentiation tests.
