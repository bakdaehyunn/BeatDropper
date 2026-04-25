# ExecPlan: AI DJ Planner Slice 16

## Goal
- Improve planner quality by making the Codex prompt and local heuristic planner mode-aware, cue-aware, and less tail-only.

## Progress
- [x] Add stronger mode/cue guidance to the Codex sample wrapper prompt.
- [x] Upgrade the heuristic planner to use cue/downbeat/beat-grid hints and mode-specific policy.
- [x] Add focused tests for planner script helpers and mode behavior.
- [x] Validate with tests and build checks.

## Locked Decisions / Non-Goals
- Reuse the existing planner request contract.
- Do not change `AudioEngine` execution behavior in this slice.
- Do not expand analysis generation/storage yet.

## Code Orientation
- `scripts/codex-mix-planner.cjs`
- `scripts/heuristic-mix-planner.cjs`
- `tests/unit/plannerScripts.test.ts`
- `docs/design-freeze-ai-dj-planner-2026-04-25.md`

## Plan Of Work
1. Refactor planner scripts to expose helper functions for tests.
2. Add mode-aware prompt guidance for `safe`, `balanced`, and `adventurous`.
3. Improve the heuristic planner to choose transition windows, start offsets, style, and tempo sync using existing cues and mode policy.
4. Add script-focused tests and run validation.

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

- `npm run test`: passed (`20` files, `69` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed
- `node --check scripts/codex-mix-planner.cjs`: passed
- `node --check scripts/heuristic-mix-planner.cjs`: passed

## Risks
- Overly opinionated prompt rules can reduce Codex flexibility.
- Heuristic mode policies can become inconsistent with later AI outputs if they are not documented clearly.

## Backout
- Revert both planner scripts to the simpler policy.
- Remove the planner-script unit tests.
