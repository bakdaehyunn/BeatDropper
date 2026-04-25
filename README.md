# BeatDropper

BeatDropper is an Electron desktop app for local music playback with automatic DJ-style transitions.

It plays a queue of local tracks, prepares the next deck before the current song ends, and applies crossfades or AI-assisted transition plans through a deterministic audio engine.

## Overview

BeatDropper is built around two ideas:

- local-first playback for `.mp3` and `.wav`
- a transition system that can stay rule-based or accept a validated `MixPlan` from an external AI planner

In the default path, BeatDropper computes a safe crossfade near the end of the current track. In AI DJ mode, it sends a planner request to an external CLI, validates the response, and executes the resulting `MixPlan` only if it is safe.

## Core Features

- Local audio file playback (`.mp3`, `.wav`)
- Sequential queue playback with optional `repeat all`
- Configurable crossfade duration
- Next-track predecode and decode fallback handling
- BPM and transition support inside the playback engine
- External AI DJ planner support over CLI JSON `stdin/stdout`
- Planner debug, export/import, and comparison tools

## How It Works

### Playback flow

1. BeatDropper loads local tracks and builds a queue.
2. The current track plays on one deck while the next track is prepared on another deck.
3. Near the transition point, BeatDropper either:
   - uses its built-in rule-based transition path, or
   - requests a `MixPlan` from an external planner CLI
4. The audio engine applies fade timing, next-track start offset, and tempo sync from the accepted plan.

### AI DJ planner flow

1. BeatDropper builds planner request JSON from current track state, next track state, playback timing, and available analysis hints.
2. An external CLI reads that request from `stdin`.
3. The CLI returns planner response JSON on `stdout`.
4. BeatDropper validates and clamps the response into a safe `MixPlan`.
5. If planner execution fails or the plan is invalid, BeatDropper falls back to the rule-based transition path.

The planner interface is agent-agnostic. Codex is one example, but any CLI can integrate if it follows the same contract.

## Architecture

- `src/main`
  Electron main process, planner invocation, settings persistence, track analysis, IPC.
- `src/preload`
  Safe bridge API between main and renderer.
- `src/renderer`
  React UI and Web Audio playback engine.
- `src/shared`
  Shared contracts for planner request/response, `MixPlan`, export envelopes, and comparison artifacts.
- `scripts`
  Example planner wrappers and evaluation helpers.
- `tests`
  Unit, integration, and e2e coverage.

## Quick Start

```bash
npm install
npm run dev
```

## Validation

```bash
npm run test
npm run build
npm run build:main
```

Optional:

```bash
npm run test:e2e
npm run test:e2e:electron
node scripts/evaluate-planner-modes.cjs
```

## AI DJ Planner

BeatDropper can call any external planner CLI that accepts planner request JSON on `stdin` and returns planner response JSON on `stdout`.

### Sample Codex wrapper

- Script: `scripts/codex-mix-planner.cjs`
- Recommended command: `node`
- Recommended args:

```text
scripts/codex-mix-planner.cjs
```

- Recommended timeout: `20000`

Optional environment:

- `BEATDROPPER_CODEX_MODEL=gpt-5.5`

### Local heuristic planner

For offline testing without any external AI:

- Script: `scripts/heuristic-mix-planner.cjs`
- Recommended command: `node`
- Recommended args:

```text
scripts/heuristic-mix-planner.cjs
```

To inspect mode differences on the bundled planner corpus:

```bash
node scripts/evaluate-planner-modes.cjs
```

## Planner Review Tools

BeatDropper can export and re-import:

- accepted `MixPlan` envelopes
- pairwise comparison artifacts
- imported comparison snapshots for later review

The current debug workflow is review-only. Imported artifacts do not override live playback.

## Current Status

Working now:

- queue playback and crossfade transitions
- AI DJ planner request/response execution path
- planner debug and artifact comparison workflow
- bundled Codex wrapper and heuristic planner

Known gaps:

- production-grade beat grid and phrase analysis
- key and energy-aware transition quality
- distribution packaging and updater workflow
- broader real-world tuning across larger music libraries

## Documentation

Project analysis notes are available in `docs/PROJECT_OVERVIEW.md`.

If you plan to publish this repository, use `docs/github-readiness-checklist-2026-04-25.md` as a pre-push checklist.
