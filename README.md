# BeatDropper

BeatDropper is a desktop DJ player for DJs who prepare local tracks and want help keeping the next mix ready.

Load a set, arrange the running order, start playback, and let Codex help plan how the next transition should land. BeatDropper keeps the track monitor, playlist, library, preparation tools, and mix plan focused around a native macOS workflow.

## What It Does

BeatDropper is built around the way a DJ works with prepared music:

- Load MP3/WAV tracks as a new set or add tracks to the current playlist.
- Reorder the set directly from the playlist.
- See BPM, length, cue information, and mix readiness while choosing the next track.
- Monitor what is playing now, how the AI plans to mix it, and what track comes next.
- Use phrase-aligned DJ transitions: 0–1-bar hard cuts, 4-bar energy swaps, 8-bar smooth blends, and optional safe 16-bar blends.
- Keep playback stable with one validated beat/bar policy shared by AI planning, local fallback, and manual Next.

The goal is not to replace a DJ's taste. The goal is to give the DJ a focused assistant for transition timing, cue alignment, playlist flow, and repeatable mix decisions.

## Native Workspaces

BeatDropper is organized around two native macOS workspaces:

- `Playing`: performance mode organized as current deck → transition decision → next deck, with stacked waveforms, a compact set-flow queue, and evidence available through the inspector.
- `Creative`: preparation mode for waveform/cue editing, BPM-backed beat-grid correction, saved sets, library search, and set energy flow.

Both modes share one persistent bottom transport for the current track, progress, previous/play/next controls, AI Mix state, and master output. The product UI remains native SwiftUI; no browser or secondary desktop runtime is part of the app repository.

The library and saved sets are user-taste surfaces. AI is used for transition timing, fade style, tempo-sync strategy, and mix evidence, not for choosing the user's taste.

## AI Agent Mixer

BeatDropper can ask an AI agent to plan the next transition. The agent receives the current track, next track, playback position, BPM/cue analysis, and mix style. It returns a structured MixPlan:

- when the current track should begin fading
- when the transition should end
- where the next track should start
- what transition style fits the pair
- whether tempo sync should be applied
- the selected bar count and whether timing came from the beat grid or a low-confidence seconds fallback
- why that plan makes musical sense

Supported planner path:

- `Codex`: uses the user's local Codex CLI login. BeatDropper does not ask for or store a Codex API key.

If Codex or the planner bridge is unavailable, BeatDropper falls back to a deterministic local planner so playback can remain usable.

## How The Technology Works

BeatDropper is now a native macOS app backed by SwiftUI, AppKit, AVAudioEngine, local JSON persistence, and a bundled Node-based planner bridge.

- The native app provides the Playing and Creative workspaces, playlist management, library browsing, transport controls, and planner review UI.
- The audio engine uses AVAudioEngine for local playback, gain ramps, crossfades, and output metering.
- The native core owns local file access, persistent library state, settings, analysis cache, DSP analysis, planner evidence, and fallback planning.
- The Codex planner bridge exchanges JSON through stdin/stdout and validates the returned `MixPlan`.
- MixPlan responses are validated before they can affect playback.
- Reliable BPM/bar grids are converted into synchronized 4/4 transition windows; unsuitable tempo gaps are shortened to energy swaps or hard cuts, while low-confidence grids retain the configured seconds fallback.
- API keys are not stored by default. Codex uses its own official authentication flow.

The production application is native-only. SwiftUI and AppKit own the interface, AVAudioEngine owns playback, and Swift core modules own persistence, analysis, and planning contracts.

## Run Locally

```bash
npm install
npm run native:run
```

Build and package the native app:

```bash
npm run native:build
npm run native:package
```

## Validation

```bash
npm run native:test
npm run native:accessibility:check
npm run native:macos-shell:check
npm run native:benchmark:analysis
npm run native:benchmark:planner
```

`npm test` validates the remaining Node-based planner, benchmark, calibration, and security tooling.
