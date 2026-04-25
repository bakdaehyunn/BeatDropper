# GitHub Readiness Checklist

## Goal

Prepare BeatDropper for public GitHub sharing as a portfolio project, not as a finished commercial product.

## Before Push

- Confirm `README.md` still matches the current product state.
- Add at least one screenshot or short GIF of:
  - track queue
  - AI DJ planner settings
  - planner debug / compare view
- Decide whether `package.json` should remain `"private": true`.
- Check `.gitignore` covers local build output, logs, temp exports, and OS junk.
- Confirm no secrets or local tokens are committed.
- Remove obviously accidental local artifacts before commit.

## Validation

Run:

```bash
npm run test
npm run build
npm run build:main
```

Optional but useful:

```bash
npm run test:e2e
npm run test:e2e:electron
node scripts/evaluate-planner-modes.cjs
```

## Git Hygiene

- Prefer a feature branch such as `feat/ai-dj-planner`.
- Push with a draft PR instead of direct `main` push.
- Keep the PR description focused on:
  - problem
  - architecture choice
  - planner contract
  - validation run
  - known limits

## Portfolio Positioning

Lead with these points:

- agent-agnostic CLI planner contract
- deterministic runtime with fallback
- export/import/compare tooling for planner review
- mode-aware planner quality tuning
- fixture-based regression approach

Do not oversell:

- beat detection quality
- production audio polish
- distribution readiness
- large-scale library testing

## Recommended Repo Metadata

- Short description:
  `Electron DJ-style local player prototype with an agent-agnostic AI mix planner`
- Suggested topics:
  - `electron`
  - `typescript`
  - `react`
  - `webaudio`
  - `music`
  - `ai`
  - `llm`
  - `desktop-app`

## Nice-To-Have Before Public Share

- add a short architecture diagram
- add a 30-60 second demo clip
- add a few sample planner artifacts under a safe demo folder if they help explain the workflow
- add a short "Known limits" section to the GitHub release or PR

## Recommended Positioning Statement

BeatDropper is best presented as an exploration of safe AI-assisted transition planning in a desktop audio player, not as a finished DJ product.
