# ExecPlan: AI DJ Planner Slice 1

## Goal
- Introduce the shared contracts and storage boundaries needed for AI-assisted transition planning without changing live playback behavior yet.
- Lock the first integration surface to an agent-agnostic CLI contract.

## Progress
- [x] Add shared analysis and mix-plan types.
- [x] Add app settings fields for AI DJ mode and provider enablement.
- [x] Add main-process analysis cache storage and lookup path.
- [x] Add planner service interface plus a CLI planner adapter.
- [x] Add validation and fallback rules for unsafe planner output.
- [x] Add unit tests for contract validation and fallback behavior.

## Locked Decisions / Non-Goals
- Keep realtime audio execution in renderer.
- Keep planner process calls out of `AudioEngine`.
- Do not replace the current rule-based advisor in this slice.
- Do not add network-bound provider calls to tests in this slice.
- Use CLI JSON stdin/stdout as the first integration contract.

## Code Orientation
- `src/shared/types.ts`
- `src/shared/settings.ts`
- `src/shared/api.ts`
- `src/main/ipc.ts`
- `src/main/settingsStore.ts`
- `src/main/trackRegistry.ts`
- New `src/main/analysis/*`
- New `src/main/aiDj/*`
- New `src/shared/plannerContract.ts`

## Plan Of Work
1. Define `TrackAnalysis`, `MixPlan`, and AI DJ setting types in shared modules.
2. Extend persisted settings with AI DJ toggles, planner command config, and safe defaults.
3. Add a main-process analysis store keyed by `trackId`.
4. Add planner request and response contracts plus validation.
5. Add a CLI adapter that:
   - writes a planner request JSON payload to stdin
   - reads a planner response JSON payload from stdout
   - treats stderr/timeouts/non-JSON stdout as planner failure
6. Expose IPC methods for:
   - reading analysis for a track
   - requesting a candidate `MixPlan`
7. Add tests for:
   - settings sanitization
   - plan validation and clamping
   - IPC payload validation
   - CLI planner stdout parsing and timeout failure
   - fallback to rule-based mode when AI is disabled or invalid

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
```

- `npm run test`: passed (`16` files, `55` tests)
- `npm run build`: passed (`vite build` + `tsc -p tsconfig.electron.json`)

## Risks
- Contract design can sprawl if waveform-level data is mixed into first-slice types too early.
- UI and engine assumptions may drift if `MixPlan` is defined without enough execution detail.
- CLI contract drift can break third-party planner adapters unless schema versioning is explicit.

## Backout
- Remove AI DJ-specific shared types and IPC methods.
- Keep only the existing rule-based advisor and settings schema.
