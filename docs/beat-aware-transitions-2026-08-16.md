# Beat-Aware Native Transitions — 2026-08-16

## Runtime policy

`BeatAlignedTransitionPolicy` is the single timing authority for Codex plans, native fallback plans, and manual Next. It runs after planner validation and before a plan can be scheduled or executed.

- hard cut: 1 bar when an aligned bar window exists; a 0-bar technical cut is reserved for a reliable grid with no remaining aligned runway
- energy swap: 4 bars
- smooth blend: 8 bars
- safe extended blend: 16 bars only for an aligned smooth plan when both grids have at least 0.75 quality and the transition is no longer than 32 seconds

Durations come from the measured 4/4 bar grid. The plan records `transitionBarCount`, `transitionTimingSource`, and `synchronizedBPM`; these fields are optional so older planner JSON remains decodable.

## Grid and tempo safety

A grid is trusted only when both tracks have finite BPM, BPM confidence of at least 0.55, overall analysis confidence of at least 0.45, beat-grid quality of at least 0.45, at least four ordered bar markers, stable bar intervals, and BPM/grid agreement within 12%.

Compatible grids use an incoming playback rate between 0.85 and 1.15. OUT and IN are snapped to bar indices with the same eight-bar phrase phase. If tempo synchronization is unsuitable, a moderate gap is reduced to a four-bar energy swap and a large gap to a one-bar hard cut. The configured seconds fade is used only when the BPM/grid reliability gate fails.

Manual Next uses the same policy with a manual intent: it queues the first compatible upcoming bar instead of waiting for the planned outro or starting between beats. Pause/resume preserves that scheduled plan.

## Playback and UI invariants

The native audio engine owns `activeTransitionPlan` for the full crossfade, including pause/resume and audio-device recovery. The Playing workspace reads the active plan before the next scheduled plan, so it continues to show style, bars, duration, source, OUT, and IN while both deck playheads move. Completion, cancellation, and stop clear the incoming position and active plan.

## Verification evidence

- Swift: 151 tests across 26 suites passed.
- Focused policy coverage: 4/8/16-bar math, synchronized tempo, phrase alignment, moderate and extreme BPM gaps, low-confidence fallback, manual Next, and legacy JSON decoding.
- Planner benchmark: six deterministic cases passed, covering 16/8/4/1-bar and seconds-fallback behavior.
- Node tooling: 22 tests across five files passed.
- Native accessibility: 49 checks passed; macOS shell: 15 checks passed.
- Packaged playback: two transitions, live incoming positions, transition pause/resume, device recovery, DSP plan retention, and clean stop passed.
- Extended packaged session: 12 tracks analyzed and six planned transitions completed before returning to Idle.
- Complete local preflight: all 16 steps passed, including Swift/tooling gates, accessibility, macOS shell, packaging, app/DMG/installed smoke, open-import, playback, normal/extended session, large-library stress, release readiness with allowed credential blockers, and parity.

The remaining release-only blockers are external Developer ID signing, Apple notarization, and clean-machine Gatekeeper acceptance. Local ad-hoc app, ZIP, and DMG packaging pass codesign and DMG verification.
