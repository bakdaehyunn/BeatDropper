# ExecPlan: AI DJ Planner Slice 7

## Goal
- Add metadata to exported `MixPlan` files and surface that metadata in the planner debug drawer.

## Progress
- [x] Add export envelope metadata such as schema version, planner source, preset label, and export timestamp.
- [x] Show planner export/debug metadata in the utility drawer.
- [x] Keep export format renderer-local and backward-compatible with existing raw `MixPlan` payloads.

## Locked Decisions / Non-Goals
- Export metadata wraps the existing `mixPlan` instead of replacing it.
- Do not implement import/apply-from-file yet.
- Keep metadata descriptive and lightweight.

## Code Orientation
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
- Export envelope changes can confuse users if the UI does not clearly separate raw planner response from exported file format.
- Too much metadata in the debug drawer can reduce scanability.

## Backout
- Revert to raw `MixPlan` export and remove export metadata display.
