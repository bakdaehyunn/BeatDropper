# ExecPlan: AI DJ Planner Slice 4

## Goal
- Add planner observability so users can see the latest applied mix plan, recent fallback reason, and richer event details.
- Provide a second example planner script that exercises the CLI contract without requiring an external LLM.

## Progress
- [x] Add queue-panel observability UI for last applied plan and last fallback.
- [x] Render compact event detail summaries in the session log.
- [x] Add a local heuristic planner example script.
- [x] Document how to switch between Codex and heuristic planner adapters.

## Locked Decisions / Non-Goals
- Keep planner observability read-only in this slice.
- Prefer derived UI from existing player events instead of new persistence.
- Keep the heuristic planner simple and deterministic; it is a contract example, not a production DJ brain.

## Code Orientation
- `src/renderer/App.tsx`
- `src/renderer/styles/app.css`
- `scripts/heuristic-mix-planner.cjs`
- `README.md`

## Validation Commands
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
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

- `npm run test`: passed (`17` files, `57` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed
- both planner scripts passed `node --check`

## Risks
- Event-detail rendering can get noisy if too much raw metadata is surfaced.
- A simplistic heuristic example can be mistaken for the recommended production path unless docs are explicit.

## Backout
- Remove planner observability UI and the heuristic example script.
- Leave slices 1-3 planner integration intact.
