# ExecPlan: AI DJ Planner Slice 5

## Goal
- Expose copyable planner debug payloads in the UI so users can inspect the last planner request and response directly.

## Progress
- [x] Include planner request and response payloads in planner-applied and planner-fallback events.
- [x] Add a debug section in the settings drawer for the latest planner request/response JSON.
- [x] Add copy actions for planner request and response payloads.
- [x] Document the new debug path in project docs if needed.

## Locked Decisions / Non-Goals
- Keep debug payloads in-memory and event-derived; do not add new persistence in this slice.
- Show only the most recent planner request/response pair.
- Do not add raw payloads to the main queue panel; keep them in the utility drawer.

## Code Orientation
- `src/renderer/player/audioEngine.ts`
- `src/renderer/App.tsx`
- `src/renderer/styles/app.css`

## Validation Commands
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
```

## Validation Results
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
```

- `npm run test`: passed (`17` files, `57` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed

## Risks
- Large payloads could make the drawer noisy if formatting is not constrained.
- Clipboard APIs can fail in some runtimes, so copy actions need a small fallback path.

## Backout
- Remove planner debug payload rendering from the drawer.
- Keep planner event summaries and core planner execution intact.
