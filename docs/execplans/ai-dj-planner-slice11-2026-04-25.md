# ExecPlan: AI DJ Planner Slice 11

## Goal
- Let the user compare a selected imported artifact against either the latest local `MixPlan` or another imported artifact in the current session.

## Progress
- [x] Add compare-target selection state for planner debug.
- [x] Show pairwise comparison details for `selected artifact -> target`.
- [x] Keep comparison controls coherent when artifacts are removed or absent.
- [x] Update docs and validate with tests/builds.

## Locked Decisions / Non-Goals
- Keep comparison renderer-local and compare-only.
- Reuse the current imported artifact list instead of adding a new persistence layer.
- Do not add playback apply, artifact history persistence, or automatic track matching.

## Code Orientation
- `src/renderer/App.tsx`
- `src/renderer/styles/app.css`
- `README.md`
- `docs/PROJECT_OVERVIEW.md`

## Plan Of Work
1. Add comparison-target state with a special local-plan option.
2. Compute comparison metadata and deltas for local-vs-imported or imported-vs-imported.
3. Add UI controls and a compact comparison panel to planner debug.
4. Refresh docs to mention direct artifact-to-artifact comparison.

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
- Comparison UI can become cluttered if labels do not clearly separate primary vs target.
- Removing the active or target artifact must not leave the drawer in an invalid state.

## Backout
- Remove compare-target selection and the pairwise comparison panel.
- Fall back to the Slice 10 model where imported artifacts compare only against the latest local plan.
