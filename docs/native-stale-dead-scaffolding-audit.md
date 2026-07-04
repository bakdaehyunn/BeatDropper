# Native Stale/Dead/Scaffolding Code Audit

Generated: 2026-07-04

Scope: macOS native-process perspective. This audit checks whether BeatDropper still has stale, dead, or scaffolding code that should be removed before the native process is treated as the primary app path.

## Conclusion

No safe-to-delete native runtime source was identified in this pass. The remaining Electron/web footprint is stale from a future native-only perspective, but it is intentionally retained until the documented Electron retirement gates pass.

The retirement metadata needed one update: newly added native validation assets must be kept and checked during retirement planning:

- `scripts/validate-loudness-reference.cjs`
- `scripts/validate-native-real-folder.cjs`
- `native/Sources/BeatDropperNativeLoudnessValidation/`
- `native:validate:loudness-reference`
- `native:validate:real-folder`

The same metadata pass also confirmed native package scripts with non-obvious backing files:

- `scripts/check-native-macos-shell.cjs`
- `scripts/create-analysis-benchmark-fixture.cjs`
- `native:macos-shell:check`
- `native:benchmark:analysis:create`

## Safe Cleanup Now

None for source/runtime code.

Optional local-only cleanup, if a clean workspace is desired:

- `dist/`
- `dist-electron/`
- `test-results/`
- generated reports and release artifacts under `native/dist/`

These are generated artifacts, not stale source. Do not use their presence as evidence that runtime code is dead.

## Intentionally Retained Until Electron Retirement

Do not remove these until `native:release`, strict release verification, Gatekeeper evidence, `native:parity -- --pre-retirement`, and `native:retire:check` prove retirement is safe:

- `src/main`
- `src/preload`
- `src/renderer`
- `src/shared`
- Electron tests and configs
- Electron/React/Vite package dependencies
- Electron package scripts
- Electron-to-native migration code in the native core

Reason: the repo documents Electron as the reference path during the native transition, and the retirement readiness gate is currently expected to block while release/notarization and remaining Electron-footprint checks are incomplete.

## Generated/Local Artifacts Only

These paths can be cleaned locally when they are not needed for evidence review, but they should not be confused with source cleanup:

- `dist`
- `dist-electron`
- `test-results`
- `native/dist/*.json`
- `native/dist/BeatDropper.app`
- `native/dist/BeatDropper.zip`
- `native/dist/BeatDropper.dmg`

## Risky Or Needs Approval

- Deleting any Electron/web source, tests, deps, or scripts before the retirement gate passes.
- Removing Electron migration logic before existing Electron-origin user state is no longer supported.
- Removing `scripts/heuristic-mix-planner.cjs` or `scripts/evaluate-planner-modes.cjs`; these are older planner utilities, but they are still referenced by tests/docs or historical validation paths.
- Removing release/preflight scripts that look auxiliary; many are used as evidence producers for native parity and retirement gates.
- Rewording or removing the `MixControlPlan.conservativeDefaults` "planning metadata only" quality note. It looks scaffold-like, but it is part of the current mix-control contract and is covered by native fallback/planner parity tests.

## Audit Commands

Required goal verification:

```sh
npm run native:retire:plan -- --no-checks
npm run native:retire:check
npm run native:parity:report
npm run native:test
npm test
git diff --check
```

Expected state before full Electron retirement:

- `native:retire:check` remains `BLOCKED` until signed/notarized release and strict Gatekeeper evidence are available.
- `native:parity:report` may remain `BLOCKED` for release blockers, not because the Electron footprint should be deleted now.

## Verification Results

Current run:

- `npm run native:retire:plan -- --no-checks`: passed and regenerated `native/dist/electron-retirement-plan.json`.
- Retirement plan JSON now keeps:
  - `scripts/check-native-macos-shell.cjs`
  - `scripts/create-analysis-benchmark-fixture.cjs`
  - `scripts/validate-loudness-reference.cjs`
  - `scripts/validate-native-real-folder.cjs`
  - `native/Sources/BeatDropperNativeLoudnessValidation`
  - `native:macos-shell:check`
  - `native:benchmark:analysis:create`
  - `native:validate:loudness-reference`
  - `native:validate:real-folder`
- `npm run native:retire:check`: expected `BLOCKED`.
  - Current blockers: native pre-retirement parity, release signing/notarization readiness, strict release verification, Electron source footprint, Electron package dependencies, and Electron package scripts.
- `npm run native:parity:report`: expected `BLOCKED`.
  - Native validation assets now appear as passing native structure/command checks.
  - Current blockers remain release blockers: Developer ID signing, Gatekeeper assessment, strict release verification, and Electron retirement.
- `npm run native:test`: passed, 123 Swift tests.
- `npm test`: passed, 178 Vitest tests.
- `git diff --check`: passed.

## Metadata Updates Made

- `scripts/plan-electron-retirement.cjs` now keeps current native validation scripts, command scripts, package commands, and the `BeatDropperNativeLoudnessValidation` target.
- `scripts/evaluate-native-parity.cjs` now checks those validation scripts, commands, and target as part of native structure/command parity.
