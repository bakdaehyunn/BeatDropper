# ExecPlan: AI DJ Planner Slice 3

## Goal
- Make the CLI-first AI DJ path usable end-to-end by exposing planner settings in the UI and shipping a sample Codex planner wrapper script.

## Progress
- [x] Add AI DJ planner settings controls to the renderer utility drawer.
- [x] Preserve planner command, args, mode, timeout, and enablement through the existing settings flow.
- [x] Add a sample `codex exec` planner wrapper script that consumes planner JSON stdin and emits planner JSON stdout.
- [x] Document how to point BeatDropper at the sample wrapper or another agent CLI.
- [x] Update tests to cover the expanded preload/settings surface where needed.

## Locked Decisions / Non-Goals
- Keep the primary planner contract at stdin/stdout JSON.
- Do not add secret entry fields to the BeatDropper UI in this slice.
- Treat the sample Codex wrapper as an example adapter, not a required runtime dependency.
- Avoid hardcoding one provider into renderer logic.

## Code Orientation
- `src/renderer/App.tsx`
- `src/renderer/styles/app.css`
- `src/shared/settings.ts`
- `tests/e2e-electron/ipc.spec.ts`
- `scripts/*`
- `README.md`

## Plan Of Work
1. Add an AI DJ section to the settings drawer with:
   - enabled toggle
   - mode selector
   - planner command input
   - planner args input
   - timeout input
2. Add helper parsing for planner args text in the renderer.
3. Add a Codex sample planner wrapper script under `scripts/`.
4. Document example settings for:
   - Codex wrapper
   - alternate agent wrappers following the same contract
5. Extend tests or Electron smoke checks to cover the new persisted settings/API surface.

## Validation Commands
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
node --check scripts/codex-mix-planner.cjs
```

## Validation Results
```bash
cd /home/dh/workspace/BeatDropper
npm run test
npm run build
npm run build:main
node --check scripts/codex-mix-planner.cjs
```

- `npm run test`: passed (`17` files, `57` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)
- `npm run build:main`: passed
- `node --check scripts/codex-mix-planner.cjs`: passed

## Risks
- Persisting planner args from a plain text field can be error-prone without a simple, predictable parser.
- A sample wrapper that assumes too much about one CLI can drift if the upstream CLI flags change.

## Backout
- Remove the UI controls and sample wrapper script.
- Keep the underlying planner engine support from slices 1 and 2 intact.
