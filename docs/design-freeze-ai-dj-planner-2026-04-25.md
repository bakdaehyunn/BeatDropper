# Design Freeze: AI DJ Planner

## Scope
- Add an AI-assisted DJ planning layer to BeatDropper that decides how to transition from the current track to the next track.
- Keep audio playback deterministic by letting the audio engine execute a precomputed plan instead of asking AI in the realtime loop.
- Extend track analysis beyond raw BPM so the planner can choose transition timing, start offsets, and transition style.

## Option Review

### Decision 1: When should the AI planner be called?

#### Option A. Poll AI every 10 seconds during playback
- Why it exists: simplest mental model if AI is treated like a live DJ operator.
- Pros: can react to changing queue order or manual jumps.
- Cons: nondeterministic latency, repeated cost, network dependence, and poor timing precision inside the audio loop.

#### Option B. Analyze tracks ahead of time and ask AI once per upcoming transition
- Why it exists: keeps the realtime engine stable while still allowing AI-driven decisions.
- Pros: bounded latency, deterministic playback, easier caching, easy fallback to rule-based planning.
- Cons: needs new analysis cache and planner interfaces.

#### Option C. Keep transitions fully rule-based
- Why it exists: lowest complexity and highest runtime predictability.
- Pros: no external dependency, simplest testing story.
- Cons: does not deliver an AI DJ experience.

### Locked Decision 1
- Choose Option B.
- AI runs before the transition window, not as a periodic polling loop during playback.

### Decision 2: Where should AI planning live?

#### Option A. Renderer only
- Why it exists: the audio engine already lives in renderer.
- Pros: shortest path to playback state.
- Cons: harder secret handling, harder caching, and too much coupling between UI/audio code and provider logic.

#### Option B. Main process planner service with renderer requests
- Why it exists: main already owns settings and track file access.
- Pros: better boundary for provider config, analysis cache persistence, and IPC contracts.
- Cons: needs new IPC for planning and analysis reads.

#### Option C. External CLI sidecar only
- Why it exists: convenient for batch analysis and future automation.
- Pros: reusable from scripts and CI.
- Cons: poor fit for interactive transition planning on its own.

### Locked Decision 2
- Choose Option B for the planner service.

### Decision 3: How should external AI agents integrate?

#### Option A. CLI-first planner adapter
- Why it exists: each user may prefer a different subscribed AI agent or local model.
- Pros: agent-agnostic, easy to swap, works with Codex CLI and other local wrappers, no BeatDropper-side provider SDK lock-in.
- Cons: stdout/stderr discipline and JSON schema validation become critical.

#### Option B. HTTP-first provider integration
- Why it exists: convenient when the planner is hosted as a service.
- Pros: central deployment and language-agnostic network access.
- Cons: less convenient for personal local agent setups and introduces service/network requirements.

#### Option C. In-process provider SDK integration
- Why it exists: shortest path for a single provider.
- Pros: direct control and fewer moving parts for one vendor.
- Cons: vendor lock-in and poor portability across users with different subscriptions.

### Locked Decision 3
- Choose Option A.
- BeatDropper will define a CLI JSON contract for planner requests and responses.
- `Codex` is one adapter target, not the product contract.

### Decision 4: How should exported `MixPlan` files be re-used?

#### Option A. Apply imported files directly to playback
- Why it exists: fastest path to a visible "load saved plan" feature.
- Pros: can override planner output without calling an agent again.
- Cons: risky boundary because imported files become runtime control input and need stronger validation, track identity checks, and UI affordances.

#### Option B. Import exported files only for debug comparison
- Why it exists: lets users compare planner outputs and share artifacts without giving imported JSON any authority over playback.
- Pros: safe, renderer-local, useful for tuning, and compatible with the current export/debug workflow.
- Cons: does not yet allow manual replay or forced transition plans.

#### Option C. Do not support reading exported files
- Why it exists: keeps the product simpler until a full artifact workflow is designed.
- Pros: zero new surface area.
- Cons: leaves exported files as one-way artifacts with limited practical value.

### Locked Decision 4
- Choose Option B.
- Imported export files are for debug comparison only.
- No imported file may drive `AudioEngine` execution in this slice.

### Decision 5: What should the first planner quality pass optimize?

#### Option A. Improve planner policy using the current request fields
- Why it exists: the planner already receives BPM, cue/downbeat summaries, playback state, and mode.
- Pros: fastest path to better transitions without changing contracts or analysis storage.
- Cons: quality still depends on the limits of current analysis fidelity.

#### Option B. Expand analysis inputs first
- Why it exists: richer musical structure can improve planner decisions.
- Pros: raises the quality ceiling longer-term.
- Cons: slower path because it changes analysis generation and likely needs new validation and observability.

#### Option C. Focus on execution polish first
- Why it exists: tighter fade curves and scheduling can improve perceived quality.
- Pros: helps even with mediocre plans.
- Cons: does not solve weak planner decisions or poor cue selection.

### Locked Decision 5
- Choose Option A.
- The first quality pass will make the Codex prompt and local heuristic planner mode-aware and more cue-aware before expanding the analysis contract.

## Locked Decisions
- `AudioEngine` remains deterministic and executes `MixPlan`; it does not call any agent directly.
- Track analysis is separated from AI planning.
- AI planning happens once per candidate transition, typically after next-track predecode succeeds.
- A hard safety layer clamps AI output and falls back to the existing rule-based advisor when data is missing or the plan is invalid.
- First release targets local files only and single-step `current -> next` transitions.
- Planner integration must be optional. BeatDropper still works without AI credentials or without any external agent configured.
- The primary extension point is a CLI planner contract using JSON stdin/stdout.
- Exported planner artifacts may be re-imported for debugging, but not for playback override unless a later design explicitly expands that scope.
- The first planner quality pass must prefer better policy over wider contracts: use the current request fields more intelligently before adding new analysis schema.

## Non-Goals
- Streaming service integration.
- Full DJ workstation features such as manual cue editing, waveform editing, or multi-band FX chains.
- Letting AI issue low-level audio commands on every frame.
- Perfect musical intelligence on day one such as robust key detection, phrase-aware EQ automation, or genre-specific transition recipes.

## Current Implementation Vs Target

### Current
- `trackLibrary` imports title, duration, and optional metadata BPM.
- `bpmEstimator` can estimate BPM from decoded audio.
- `ruleBasedAdvisor` picks `crossfadeStartAt = trackEnd - fadeDuration`.
- `AudioEngine` can apply playback-rate tempo sync and execute a dual-deck crossfade.
- Next track always starts at offset `0`.

### Target
- `trackLibrary` and/or analysis services produce `TrackAnalysis` records with fields such as:
  - `bpm`
  - `beatGrid`
  - `downbeats`
  - `introCueSec`
  - `outroCueSec`
  - `energyProfile`
  - `analysisConfidence`
- A main-process `AiDjPlannerService` receives:
  - current playback state
  - current track analysis
  - next track analysis
  - user settings and AI DJ mode
- The service invokes a configured external planner command and receives a `MixPlan`, for example:
  - `transitionStartSec`
  - `transitionEndSec`
  - `nextTrackStartOffsetSec`
  - `style`
  - `tempoSync.targetRate`
  - `reasoningSummary`
- Renderer requests the plan before the transition window and passes the validated plan to `AudioEngine`.
- `AudioEngine` executes the plan and emits events describing whether the plan came from AI or fallback logic.

## Proposed Runtime Flow
1. Import track and store registry entry as today.
2. Build or load `TrackAnalysis` for the current and next track.
3. When predecode completes for the next track, invoke the configured planner CLI once with a JSON request.
4. Validate and clamp the plan.
5. If valid, schedule the transition from the plan.
6. If invalid or unavailable, fall back to the existing rule-based transition path.

## New Core Types
- `TrackAnalysis`
- `MixPlan`
- `MixStyle`
- `AiDjMode`
- `PlannerRequest`
- `PlannerResponse`
- `PlannerCliConfig`

## Suggested Module Boundaries
- `src/main/analysis/trackAnalysisStore.ts`
- `src/main/analysis/trackAnalysisService.ts`
- `src/main/aiDj/aiDjPlannerService.ts`
- `src/main/aiDj/cliPlannerAdapter.ts`
- `src/shared/mixPlan.ts`
- `src/shared/analysis.ts`
- `src/shared/plannerContract.ts`
- `src/renderer/player/beatAwareAdvisor.ts`

## Risks
- Beat and phrase extraction accuracy may be weak on some files if the first implementation uses only lightweight heuristics.
- AI output may be musically plausible but operationally invalid unless strict schema validation is applied.
- CLI latency can miss the transition window unless planning happens early enough and results are cached.
- Some external agents may emit prose or logs on stdout unless the contract is enforced strictly.

## Follow-Up Items
- Decide whether first analysis storage should be JSON files under app data or a single SQLite database.
- Decide whether the first AI release should use only BPM/cue summaries or include denser beat-grid data.
- Decide whether user-facing modes should be simple presets such as `safe`, `balanced`, `adventurous`.
- Define the initial planner CLI envelope and timeout policy.
- Decide whether a later slice should add track identity binding and playback-safe validation for imported artifacts.
