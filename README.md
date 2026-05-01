# BeatDropper

BeatDropper is a desktop DJ player for DJs who prepare local tracks and want help keeping the next mix ready.

Load a set, arrange the running order, start playback, and let an AI agent suggest how the next transition should land. BeatDropper keeps the playlist, current track, mix plan, and next track visible in one performance-focused workspace.

## What It Does

BeatDropper is built around the way a DJ works with prepared music:

- Load MP3/WAV tracks as a new set or add tracks to the current playlist.
- Reorder the set directly from the playlist.
- See BPM, length, cue information, and mix readiness while choosing the next track.
- Monitor what is playing now, how the AI plans to mix it, and what track comes next.
- Keep playback stable with validated mix plans and a built-in fallback transition path.

The goal is not to replace a DJ's taste. The goal is to give the DJ a focused assistant for transition timing, cue alignment, playlist flow, and repeatable mix decisions.

## Performance Workspace

The main screen is organized around the set:

- `Playlist`: the active running order for the set.
- `Now Playing`: current track, playback state, BPM, length, and outro cue.
- `AI Mix Plan`: transition window, next-track offset, transition style, confidence, and reasoning.
- `Next Track`: upcoming track, BPM, length, and intro cue.
- `Transport`: compact playback controls designed to stay out of the playlist's way.

The layout is playlist-first because the set order matters more than a source browser once the music is loaded.

## AI Agent Mixer

BeatDropper can ask an AI agent to plan the next transition. The agent receives the current track, next track, playback position, BPM/cue analysis, and mix style. It returns a structured MixPlan:

- when the current track should begin fading
- when the transition should end
- where the next track should start
- what transition style fits the pair
- whether tempo sync should be applied
- why that plan makes musical sense

Supported agent profiles:

- `Codex CLI`: uses the user's local Codex CLI login. BeatDropper does not ask for or store a Codex API key.
- `Local Heuristic`: runs a local deterministic planner for offline/fallback comparison.
- `Custom CLI`: lets a user point BeatDropper at another agent command that speaks the MixPlan contract.

The app includes connection checks so selecting an agent is not treated as enough. BeatDropper checks whether the CLI is available, whether it can return a valid MixPlan, and whether login/authentication is required.

## How The Technology Works

BeatDropper is an Electron desktop app with a React interface and a local audio engine.

- The renderer provides the DJ workspace, playlist management, transport controls, and planner review UI.
- The audio engine uses Web Audio for local playback, gain ramps, crossfades, and output metering.
- The main process owns local file access, track loading, persistent settings, track analysis lookup, and AI agent connection checks.
- AI planners are external CLI processes that exchange JSON through stdin/stdout.
- MixPlan responses are validated before they can affect playback.
- API keys are not stored by default. CLI agents use their own official authentication flow or environment configuration.

This keeps BeatDropper focused on DJ workflow and agent harnessing instead of becoming a credential manager.

## Run Locally

```bash
npm install
npm run dev
```

For WSLg or GPU-sensitive environments, launch with GPU acceleration disabled:

```bash
BEATDROPPER_DISABLE_GPU=1 BEATDROPPER_OPEN_DEVTOOLS=0 ELECTRON_DISABLE_GPU=1 npm run dev
```

## Validation

```bash
npm run test
npm run build
npm run test:e2e
npm run test:e2e:electron
```
