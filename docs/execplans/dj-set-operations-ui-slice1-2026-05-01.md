# DJ Set Operations UI Slice 1 - ExecPlan

## Goal
Build the main set-operations UI using existing track, analysis, and mix-plan data.

## Checklist
- [x] Add analysis state and load existing `TrackAnalysis` for playlist rows.
- [x] Rebuild the main layout as source bar, Now/Mix/Next cockpit, and playlist table.
- [x] Keep current playlist controls functional.
- [x] Validate with tests and visual screenshot.

## Locked Decisions
- Use only current app contracts; no saved playlist or new analysis model.
- Planner debug stays in Settings & Logs, not the main cockpit.
- Missing data displays as `--` or fallback text.

## Affected Areas
- Renderer state and JSX in `src/renderer/App.tsx`.
- Renderer layout CSS in `src/renderer/styles/app.css`.
- Tests only if existing mocks require new API surface.

## Validation
- `npm run test`
- Playwright screenshot at 1220x874 with mock tracks.
- Manual Electron run with GPU disabled.

## Backout
Revert the renderer JSX/CSS slice and keep earlier IPC/window/playback fixes intact.
