# ExecPlan: AI DJ Planner Slice 2

## Goal
- Connect planner results to the renderer playback engine so `MixPlan` can change transition timing, next-track start offset, and tempo sync behavior at runtime.

## Progress
- [x] Add a renderer-side planner request dependency to `AudioEngine`.
- [x] Request a planner result after next-track predecode and before the transition window closes.
- [x] Reschedule pending crossfade timing when a valid `MixPlan` arrives.
- [x] Execute `nextTrackStartOffsetSec` and planner-provided tempo sync in the transition path.
- [x] Emit planner-applied and planner-fallback player events for visibility.
- [x] Add integration coverage for AI-plan execution and fallback behavior.

## Locked Decisions / Non-Goals
- Keep the planner call off the realtime sample loop.
- Reuse the existing scheduler by rescheduling future callbacks after predecode.
- Keep manual skip and hard-switch recovery paths rule-based in this slice.
- Do not add new UI controls for AI planner settings in this slice.

## Code Orientation
- `src/renderer/player/audioEngine.ts`
- `src/renderer/player/transitionScheduler.ts`
- `src/renderer/App.tsx`
- `src/shared/types.ts`
- `tests/integration/audioEngine.*`

## Plan Of Work
1. Add an optional `requestMixPlan` dependency to `AudioEngine`.
2. During `handlePredecode`, request a planner result using current playback elapsed time.
3. Convert a validated relative `MixPlan` into an execution plan with absolute transition timestamps.
4. If the plan is valid, clear and rebuild remaining scheduler callbacks with planner timing.
5. Update transition execution to:
   - start the next source at `nextTrackStartOffsetSec`
   - prefer planner-provided tempo sync rate when available
6. Emit explicit events when a planner plan is applied or rejected.
7. Extend integration tests to cover successful AI plan execution and fallback.

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
- Planner latency can arrive too close to the transition window, causing an immediate crossfade start.
- Rescheduling after predecode can duplicate callbacks if token checks or scheduler clearing are wrong.

## Backout
- Remove renderer planner dependency and execution-plan rescheduling.
- Leave Slice 1 contracts intact and return to rule-based transition timing.
