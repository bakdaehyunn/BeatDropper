# ExecPlan: AI DJ Planner Slice 18

## Goal
- Add a representative planner-request corpus and a mode-regression harness so planner quality can be tuned even when real exported requests are not available.

## Progress
- [x] Add representative planner request fixture files.
- [x] Add a small evaluation script that prints mode outputs for the fixture corpus.
- [x] Add regression tests that assert mode differences on the fixture corpus.
- [x] Validate with tests and script checks.

## Locked Decisions / Non-Goals
- Keep the current planner request contract unchanged.
- Do not fabricate new runtime telemetry or persistence just for tuning.
- Use representative fixtures until real exported requests accumulate.

## Code Orientation
- `tests/fixtures/planner-requests/*.json`
- `scripts/evaluate-planner-modes.cjs`
- `tests/unit/plannerModeRegression.test.ts`

## Plan Of Work
1. Capture a small but diverse planner-request corpus.
2. Add an offline evaluator for `safe`, `balanced`, and `adventurous`.
3. Add tests that lock the expected mode differences on the corpus.
4. Run validation and leave the harness ready for future real requests.

## Validation Commands
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
node --check scripts/evaluate-planner-modes.cjs
node scripts/evaluate-planner-modes.cjs
```

## Validation Results
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
node --check scripts/evaluate-planner-modes.cjs
node scripts/evaluate-planner-modes.cjs
```

- `npm run test`: passed (`21` files, `74` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed
- `node --check scripts/evaluate-planner-modes.cjs`: passed
- `node scripts/evaluate-planner-modes.cjs`: passed

## Risks
- Representative fixtures can drift from real-world usage if they are not refreshed later with real exported requests.
- Overfitting heuristic policy to a tiny fixture set can hide other failure modes.

## Backout
- Remove the fixture corpus, evaluation script, and regression test.
- Fall back to ad hoc manual spot checks.
