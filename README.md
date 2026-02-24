# BeatDropper

BeatDropper is a desktop MVP that automatically transitions local tracks with DJ-style crossfade near track end.

You pick tracks, BeatDropper drops the beat.

## MVP scope

- Electron desktop app (cross-platform)
- Local audio file playback only (`.mp3`, `.wav`)
- Sequential playlist with optional `repeat all`
- Default 8-second crossfade (`2..20` configurable)
- Rule-based transition timing: `crossfadeStart = trackEnd - fadeDuration`
- Decode fallback when next track decode is late

## Tech stack

- Electron + TypeScript
- React + Vite
- Web Audio API (`AudioContext`, dual-deck gain ramps)
- `music-metadata` for local file metadata parsing
- Vitest + Playwright for test coverage

## License strategy

This MVP avoids GPL/AGPL dependencies so commercial distribution remains straightforward.

## Run

```bash
npm install
npm run dev
```


## VS Code quick start

Open this folder in VS Code and use preconfigured tasks:

- `BeatDropper: dev`
- `BeatDropper: test`
- `BeatDropper: test:e2e`

Project analysis notes are available in `docs/PROJECT_OVERVIEW.md`.

## Build

```bash
npm run build
```

## Test

```bash
npm run test
npm run test:e2e
```


## Security checks

Security checks are standard release hygiene for all projects, not a signal of individual capability.

- Keep credentials out of git. Use `.env` locally and commit only `.env.example`.
- Run local scan before push:

```bash
npm run security:scan
```

- Run full security gate (scan + tests):

```bash
npm run security:check
```

## Directory overview

- `src/main`: Electron main process, IPC handlers, track loading, settings persistence
- `src/preload`: contextBridge API
- `src/renderer`: React UI + player engine modules
- `src/shared`: shared types and settings schema
- `tests`: unit, integration, and e2e smoke coverage
