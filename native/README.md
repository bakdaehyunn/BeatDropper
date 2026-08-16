# BeatDropper Native macOS App

BeatDropper is a native macOS desktop app built with SwiftUI, AppKit, AVAudioEngine, and a Swift core. The repository no longer contains a second desktop runtime.

## Current Native State

- Swift Package at `native/`.
- `BeatDropperCore` contains Codable contract models shared with the planner contract:
  - `Track`
  - `MusicLibraryTrack`
  - `UserPlaylist`
  - `PlayerSettings`
  - `TrackAnalysis`
  - `PlannerRequest`
  - `PlannerResponse`
  - `MixPlan`
  - planner `analysisSummary` and `pairContext`
- `BeatDropperNative` SwiftUI/AppKit app includes:
  - native macOS window, commands, and standard Settings scene
  - local file/folder import
  - Application Support persistence for library, source folders, playlists, saved sets, and analysis cache
  - one-time migration from legacy `music-library.json` and `user-playlists.json` into native state when no native library exists
  - native mix settings persistence with one-time migration from legacy `player-settings.json`
  - source folder rescan with missing-folder/missing-track marking and fingerprint-based relinking
  - playlist rows, inspector, playback, and mix planning respect missing-file state
  - two-deck `AVAudioEngine` playback with equal-power crossfade
  - master output level metering from the native audio graph
  - native DSP analysis foundation for waveform, energy, spectral bands, transients, BPM, bars, phrases, and cue candidates
  - bounded native DSP analysis queue for larger folder imports
  - Codex planner bridge through the existing `codex-mix-planner.cjs` contract
  - deterministic local fallback mix plans from native `pairContext` evidence when the CLI planner fails
  - shared beat/bar transition policy for AI, local fallback, and manual Next: 0–1-bar hard cut, 4-bar energy swap, 8-bar smooth blend, and optional high-confidence safe 16-bar blend
  - phrase-compatible OUT/IN snapping, synchronized-BPM duration, extreme-tempo downgrade, and seconds fallback only when BPM/bar-grid evidence is unreliable
  - scheduled AI mix execution based on planner transition timing
  - Playing workspace with current deck → transition decision → next deck hierarchy, stacked DSP waveforms, live positions for both decks, style/bar/duration/timing-source/OUT/IN evidence, compact set flow, and an on-demand evidence inspector
  - Creative workspace with waveform/cue preparation, BPM-backed beat-grid correction, saved-set building, library search, and analysis-derived energy flow
  - one persistent bottom transport shared by both workspaces, including current track, progress, previous/play/next, AI Mix state, and master output
  - responsive toolbar/workspace layouts at the 760 × 520 minimum window size, with workspace-only scrolling so transport remains anchored
  - standard macOS Settings scene for fade duration, master gain, and AI mode
  - Finder Open With support for audio files and music folders
  - drag-and-drop import for audio files and music folders
- `scripts/package-native-app.sh` creates local and release distribution artifacts:
  - `native/dist/BeatDropper.app`
  - `native/dist/BeatDropper.zip`
  - `native/dist/BeatDropper.dmg`

AI mix planning uses the bundled `codex-mix-planner.cjs` bridge. Packaging also bundles the Node runtime used to execute that bridge, then augments PATH with common macOS CLI locations so a Finder-launched app can still find an authenticated `codex` CLI. If Codex cannot run, BeatDropper keeps playback usable by falling back to the native deterministic planner from `pairContext` evidence.

Because the Node runtime is shipped inside the app bundle, packaging also includes `Contents/Resources/ThirdParty/THIRD-PARTY-NOTICES.txt` and `Contents/Resources/ThirdParty/Node-LICENSE.txt`. Release manifests, smoke reports, and verification reports record checksums for those files so runtime licensing evidence cannot go stale silently.

## Commands

From the repository root:

```sh
npm run native:build
npm run native:accessibility:check
npm run native:benchmark:analysis
npm run native:benchmark:analysis:gate
npm run native:benchmark:planner
npm run native:macos-shell:check
npm run native:test
npm run native:package
npm run native:parity:report
npm run native:preflight:local
npm run native:preflight:release
npm run native:release:check
npm run native:release:manifest
npm run native:release:setup
npm run native:release:setup:check
npm run native:release:smoke
npm run native:release:verify
npm run native:release:verify:local
npm run native:run
npm run native:smoke
npm run native:smoke:dmg
npm run native:stress:library
npm run native:stress:open-import
npm run native:stress:playback
npm run native:stress:session
npm run native:stress:session:extended
```

Directly inside `native/`:

```sh
swift build
swift test
swift run BeatDropperNative
```

## Packaging And Signing

Local packaging uses ad-hoc signing by default:

```sh
npm run native:package
```

During packaging, `CFBundleShortVersionString` is written from the root `package.json` version and `CFBundleVersion` defaults to the same numeric value. Set `BUNDLE_VERSION=123` when a separate build number is needed for a release candidate.

Packaging also writes a release manifest:

```txt
native/dist/release-manifest.json
```

The manifest records source git provenance, build toolchain provenance, app/zip/dmg artifact paths, file sizes, SHA-256 checksums, bundled planner evidence, Info.plist version metadata, codesign verification, DMG verification, and the current Gatekeeper assessment. Ad-hoc local packages are expected to record passing codesign/DMG verification but rejected Gatekeeper status until Developer ID signing and notarization are configured.

Release smoke writes separate launch evidence:

```txt
native/dist/release-smoke-report.json
```

Release verification also writes durable audit reports:

```txt
native/dist/local-release-verification-report.json
native/dist/release-verification-report.json
native/dist/notary-logs/
```

To refresh the manifest for existing artifacts:

```sh
npm run native:release:manifest
```

To verify a local ad-hoc package without requiring Developer ID or notarization:

```sh
npm run native:release:verify:local
```

To verify a real release package after Developer ID signing and notarization:

```sh
npm run native:release:verify
```

Strict release verification checks artifact checksums against the manifest, source git provenance, build toolchain provenance, clean source state, app bundle version metadata, bundled Node runtime execution, bundled Node codesign/dependency integrity, bundled Node third-party notice/license evidence, bundled planner script syntax, app codesign, hardened runtime, Developer ID trust chain, Apple notary submission/log evidence, stapled notarization tickets, app Gatekeeper assessment, quarantine-simulated app/ZIP/DMG Gatekeeper assessment, ZIP-contained app verification, DMG verification, DMG signature, DMG Gatekeeper assessment, and Gatekeeper assessment for an app copied out of the DMG. It writes `native/dist/release-verification-report.json` with artifact checksums that must match `native/dist/release-manifest.json`. Local ad-hoc verification keeps checksum, source provenance, plist, bundle version metadata, bundled Node runtime execution, bundled Node codesign/dependency integrity, bundled Node notice/license evidence, bundled planner script syntax, codesign, ZIP, DMG, quarantine simulation, and copied-installed-app integrity checks strict, reports dirty source state, Developer ID, notarization, notary-log, and Gatekeeper misses as warnings, and writes `native/dist/local-release-verification-report.json` with the same manifest-bound checksum evidence.

Developer ID signing requires a valid certificate name in `SIGN_IDENTITY`:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" npm run native:package
```

Check the local release environment before attempting notarization:

```sh
npm run native:release:check
```

`native:release:check` verifies Xcode tools, Node and Codex CLI planner runtime availability, Developer ID signing identity, configured notary credentials, notary credential authentication through `notarytool history`, current artifact checksums, source provenance evidence, release smoke evidence, bundled Node runtime execution, bundled Node codesign/dependency integrity, bundled Node notice/license evidence, bundled planner script syntax, and app bundle version metadata. It writes:

```txt
native/dist/release-readiness-report.json
```

Create and validate the notary keychain profile before the first notarized release:

```sh
NOTARY_KEYCHAIN_PROFILE="beatdropper-notary" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_PASSWORD="app-specific-password" \
npm run native:release:setup
```

To inspect local release tooling, signing identities, and setup instructions without storing credentials:

```sh
npm run native:release:setup:check
```

Notarized release builds require Developer ID signing plus Apple notary credentials. Keychain profile flow:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="beatdropper-notary" \
npm run native:release
```

Apple ID flow:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_PASSWORD="app-specific-password" \
npm run native:release
```

`native:release` is intentionally credential-driven. Without a Developer ID certificate and notary credentials, use `native:package` for local testing. During notarization it stores Apple notary submit results and completed logs under `native/dist/notary-logs/`; strict release verification then covers the packaged app, ZIP-contained app, DMG, quarantine-simulated Gatekeeper paths, notary-log evidence, and an app copied out of the DMG. After that it runs `native:release:smoke` so the final signed/notarized app bundle, mounted DMG app, and copied installed app all prove they can launch, and records that evidence in `native/dist/release-smoke-report.json`.

Run the local release-candidate preflight before requesting a notarized release:

```sh
npm run native:preflight:local
```

This gate does not require Apple credentials. It runs whitespace checks, accessibility checks, Swift tests, analysis benchmark gate, planner benchmark, local ad-hoc packaging, local artifact verification, release smoke report generation, playback stress, normal and extended session stress, large-library stress, release-readiness checks, and native parity. The preflight report is written to:

```txt
native/dist/local-preflight-report.json
```

It also refreshes benchmark and packaged stress evidence under:

```txt
native/dist/accessibility-check-report.json
native/dist/macos-shell-check-report.json
native/dist/analysis-benchmark-report.json
native/dist/planner-benchmark-report.json
native/dist/library-stress-report.json
native/dist/open-import-stress-report.json
native/dist/playback-stress-report.json
native/dist/session-stress-report.json
```

When extended stress is enabled, it also writes `native/dist/session-stress-extended-report.json`.

Developer ID, notary, and Gatekeeper misses are allowed only as expected external release blockers.
`native:release:check` also treats these durable local-quality reports as release readiness evidence, so missing or stale DSP benchmark, planner benchmark, accessibility, macOS shell, library stress, open-import stress, playback stress, normal session stress, or extended session stress reports block release readiness until `native:preflight:local` refreshes them. Quick local preflight runs can use `--skip-extended-stress`; that skips only the extended-session evidence and does not represent full release readiness.

For the actual notarized release path, run the strict preflight:

```sh
npm run native:preflight:release
```

This fails fast unless Developer ID signing, authenticated notary credentials, and a clean git tree are ready, then runs the same local quality gate and writes:

```txt
native/dist/release-preflight-report.json
```

The strict preflight uses a pre-release readiness gate, so it does not require an already signed app in `native/dist/`. That avoids a stale ad-hoc local package blocking `native:release` before the release command can build fresh signed/notarized artifacts.

## Parity Gate

Run the native parity audit before release:

```sh
npm run native:parity:report
```

The strict gate exits non-zero while blockers remain:

```sh
npm run native:parity
```

The gate checks native structure, core feature evidence, package artifacts, release manifest evidence, codesign verification, DMG verification, Developer ID/Gatekeeper status, and remaining release blockers. It is expected to stay blocked until Developer ID notarization and clean-machine Gatekeeper verification are complete.

`native:benchmark:analysis` runs the Swift benchmark evaluator against the curated analysis fixture expectations. The default fixture suite includes an intentionally failing weak-analysis case, so a non-zero exit can be expected when running the benchmark suite directly; use the printed PASS/WARN/FAIL distribution as the quality signal.

`native:benchmark:analysis:gate` runs the same fixture suite in release-gate mode. It treats committed `expectedGrade` values as the contract, writes `native/dist/analysis-benchmark-report.json`, and fails only when an analysis fixture unexpectedly changes grade.

`native:benchmark:planner` runs the Swift fallback-planner quality benchmark across cue-rich, sparse, partial-cue, stale-tail, and emergency-tail cases. Unlike live AI planning, this benchmark is deterministic and should exit zero unless the native fallback planner regresses. The local preflight runs it with `--write-json native/dist/planner-benchmark-report.json`, and the parity gate requires that durable report to include passing cases plus analysis-source and planner-failure evidence.

`native:preflight:local` runs the local release-candidate gate and writes `native/dist/local-preflight-report.json`. It should pass before any signing/notarization attempt.

`native:preflight:release` runs the strict release preflight used by `native:release`. It requires signing/notary readiness first, then runs the local gate before packaging and notarizing release artifacts.

`native:release:smoke` runs packaged app smoke, mounted DMG smoke, and installed-app smoke copied out of the DMG, then writes `native/dist/release-smoke-report.json`. The report records artifact checksums and the manifest source/toolchain provenance that must match `native/dist/release-manifest.json`, so stale smoke evidence cannot satisfy the release gates after a new package is built. Strict release verification separately records normal and quarantine-simulated Gatekeeper evidence for the packaged app, ZIP-contained app, DMG, and copied installed app. In the full release path this happens after notarization and strict release verification, so it covers the final distributable output rather than only the preflight package.

`native:accessibility:check` verifies the native SwiftUI workspace hierarchy, responsive shell, persistent transport, waveform evidence, playlist/library states, and labels for icon-only controls. Passing evidence can be written with `--write-json native/dist/accessibility-check-report.json`.

`native:macos-shell:check` verifies the native app shell keeps macOS command menus, keyboard shortcuts, a standard Settings scene, Finder Open With support, drag-and-drop import support, and avoids putting the mix settings popover back into the main toolbar. Passing evidence can be written with `--write-json native/dist/macos-shell-check-report.json`.

`native:smoke` verifies the packaged app bundle, validates codesign, launches the native app in smoke mode, waits for a visible window readiness marker, then exits the app automatically. Run `npm run native:package` first so the smoke test uses the current bundle.

`native:smoke:dmg` verifies `native/dist/BeatDropper.dmg`, mounts it read-only, checks the mounted app bundle, `Info.plist`, Applications shortcut, and codesign, launches the app from the mounted volume in smoke mode, then detaches the volume. Run `npm run native:package` first so the smoke test uses the current disk image.

`native:stress:library` runs the Swift large-library stress suite against synthetic native library records. It verifies Application Support-style persistence, cached browser indexing/search, missing-folder marking, exact folder relink assessment, fingerprint-based moved-folder reconciliation, and stable saved-set track ids. Passing evidence can be written with `--write-json native/dist/library-stress-report.json`.

`native:stress:open-import` launches the packaged app with isolated temporary native stores, simulates Finder-opened folder and loose-file inputs, waits for the bounded DSP analysis queue, and verifies the external import path preserves folder-backed library records. Passing evidence can be written with `--write-json native/dist/open-import-stress-report.json`.

`native:stress:playback` launches the packaged app against synthetic WAV fixtures and verifies two DSP-backed crossfades, the live incoming-deck playhead, pause/resume during a transition, audio-device/configuration recovery, active-plan retention, and a clean stop. Passing evidence can be written with `--write-json native/dist/playback-stress-report.json`. Run `npm run native:package` first.

`native:stress:session` launches the packaged app with isolated temporary native stores, imports a synthetic music folder, waits for the bounded DSP analysis queue, requests a planner-backed/fallback mix plan, plays, crossfades, and exits after returning an evidence marker. Playback and crossfade checks wait for observed native audio-engine state instead of relying on fixed sleeps, and failure output includes state, track id, elapsed time, remaining time, and crossfade progress. Passing evidence can be written with `--write-json native/dist/session-stress-report.json`. Run `npm run native:package` first.

`native:stress:session:extended` uses the same packaged-app path with a longer synthetic set. It imports 12 tracks, verifies the bounded analysis queue, requests repeated planner/fallback transitions, applies each plan and its DSP to the audio engine, verifies the incoming playhead during every handoff, and runs six crossfades in one app session. Passing evidence can be written with `--write-json native/dist/session-stress-extended-report.json`.

## Migration Rules

- Keep the application runtime native-only; Node remains a bounded planner/tooling dependency, not a UI runtime.
- Keep playlist/library taste human-controlled.
- Use AI only for transition technique: mix timing, fade shape, tempo sync, and energy strategy.
- Preserve the current JSON contract while porting. Native Swift should decode existing planner and analysis fixtures.
- Prefer Apple-native APIs:
  - SwiftUI for app structure and simple views
  - AppKit for mature macOS controls and window/menu behavior
  - AVFoundation/AVAudioEngine for playback
  - Accelerate/vDSP-ready design for production DSP expansion

## Phases

### Phase 0: Native Shell

Status: implemented foundation.

- Swift package, native app entry, native commands, and main window are in place.
- The UI is operational and intentionally focused on live set operation.

### Phase 1: Contract Parity

Status: implemented foundation.

- TypeScript shared models are mirrored as Swift Codable models.
- Planner request/response models include `analysisSummary` and `pairContext`.
- Swift tests cover model and planner evidence behavior.

### Phase 2: Native Library And Playlist

Status: implemented foundation.

- Imported tracks, user playlists, saved sets, and analysis cache persist in Application Support.
- The native library store writes a backup copy of the last valid `native-library.json` and falls back to it if the primary file is corrupt, so human-curated saved sets are not silently lost on a bad state file.
- Native player settings also keep a backup copy and recover fade, gain, and mix-mode preferences if the primary settings file is corrupt or missing.
- First native launch can migrate legacy `music-library.json` and `user-playlists.json` files into `native-library.json` when native state does not exist yet.
- First native launch can migrate legacy `player-settings.json` into `native-settings.json`; migrated fade duration, master gain, and AI mode are applied to native playback and planning.
- File and folder import are native.
- Imported source folders persist and can be rescanned.
- Rescan keeps saved set taste references stable by relinking moved files through lightweight file fingerprints.
- Missing source folders and missing source tracks are marked instead of silently deleting taste references.
- Missing tracks and missing source folders can be explicitly relinked from the native UI while preserving saved set track ids.
- Track and folder relink candidates are scored with fingerprint, title, duration, format, and folder coverage evidence; risky relinks require explicit user confirmation before changing a saved taste reference.
- Missing tracks remain visible for taste/history context but are skipped by playback and mix planning.
- The native Library Browser lets the user search the full imported library and manually add tracks to the current set.
- The Library Browser uses a cached sorted/search index so rendering does not rebuild source labels and search keys on every SwiftUI pass.
- Larger folder imports use a bounded DSP analysis queue so the app can keep analyzing without launching one task per track at once.
- `native:stress:library` covers 1,200 synthetic library records, saved sets, search indexing, missing-folder marking, and moved-folder relink while preserving taste track ids, and writes durable large-library evidence for preflight/parity.
- Packaged open-import stress writes durable evidence for Finder/Open With folder and loose-file imports.
- Packaged playback stress writes durable evidence for play, crossfade, pause, resume, and stop.
- Packaged session stress covers synthetic folder import, bounded analysis completion, planner fallback, playback, and crossfade, and writes durable evidence for the normal preflight session.
- Extended packaged session stress covers a 12-track synthetic set with six repeated planner/fallback transitions and crossfades.
- Remaining production work: larger real-library import/analyze stress passes and longer real-library relink tuning.

### Phase 3: Native Playback Engine

Status: implemented foundation.

- Two-deck `AVAudioEngine` playback and equal-power crossfade are implemented.
- Planner timing can trigger scheduled transitions.
- Master and per-deck output level metering are connected to the native audio graph and shown in the transport/deck panels.
- Playback position math clamps invalid long-session elapsed values, crossfade progress is sanitized before timer/gain/published-state updates, and the audio engine attempts to recover active deck/crossfade state after AVAudioEngine configuration changes.
- The packaged app can run an internal playback stress scenario with synthetic WAV fixtures covering play, crossfade, pause, resume, and stop, using condition-based state waits with failure diagnostics.
- The packaged app can run internal session stress scenarios covering import, bounded analysis, planner fallback, playback, repeated crossfades, and isolated temporary persistence, using condition-based state waits with failure diagnostics.
- Remaining production work: longer real-session stress testing and richer meter calibration.

### Phase 4: Native DSP

Status: implemented foundation.

- Native analysis includes waveform, spectral bands, transients, BPM, bars, phrases, and cue candidates.
- Spectral-flux transient detection uses both band-energy rises and band movement, so stable-RMS frequency changes can still produce planner-visible transient evidence.
- Downbeat phase scoring uses low-band spectral evidence, so weaker kick/downbeat patterns are less likely to be displaced by louder high-band backbeats.
- Phrase marker confidence now includes surrounding energy section-change evidence, so both rising and falling phrase boundaries can be ranked for planner timing instead of only high-energy points.
- Track analysis schema v5 invalidates older cached analysis so the upgraded downbeat and phrase confidence evidence is regenerated.
- Native analysis benchmark evaluation is wired to the curated fixture expectations.
- Native analysis benchmark gate writes `native/dist/analysis-benchmark-report.json` and fails on unexpected fixture grade changes while allowing committed weak-fixture expectations.
- Native analysis runs through a bounded queue and surfaces running/queued progress in the main toolbar.
- Remaining production work: real audio fixture expansion, clean-machine validation, and future key/harmonic analysis.

### Phase 5: AI Planner Bridge

Status: implemented foundation.

- Native builds planner requests from Swift analysis models.
- Existing planner script is bundled into the app resources.
- Planner CLI stdout/stderr/exit handling is parsed through tested native core logic, so valid JSON stdout is accepted even if the CLI emits benign stderr warnings.
- Returned plans are validated before application.
- Local fallback planning converts native `pairContext` candidates into validated transition plans if the CLI planner times out, returns no plan, or returns an invalid plan.
- Local fallback candidate selection ranks analysis and cue evidence ahead of stale `tail_fallback` recommendations, keeping tail timing as safety evidence rather than preferred musical evidence.
- Fallback plan evidence records candidate source, evidence level, phrase alignment, bars, BPM delta, energy delta, and planner failure reason for later inspection.
- Packaged session stress verifies that planner bridge/fallback output can drive native playback, including repeated transition loops.
- Native fallback planner quality is covered by `native:benchmark:planner` for cue-rich, sparse, partial-cue, stale-tail, and emergency-tail cases, including required evidence strings in the benchmark contract, printed report, and `native/dist/planner-benchmark-report.json`.
- Remaining production work: planner quality benchmark runs and longer real-session fallback tuning.

### Phase 6: Native DJ UX

Status: first pass implemented.

- Main view shows current deck, AI mix state, next deck, playlist, and optional inspector.
- Fake/underimplemented agent options were avoided.
- Mix settings now live in the standard macOS Settings scene instead of a main-toolbar popover, keeping the DJ workspace focused while preserving fade, master gain, and AI mix mode controls.
- Native command menus cover file import, set editing, library maintenance, playback, AI mix planning, saved sets, and workspace pane toggles with keyboard shortcuts.
- Finder-opened audio files and music folders now enter the same native library, current-set persistence, and DSP analysis queue as in-app imports.
- Dropped audio files and music folders follow the same native import path, with only a transient drop highlight added to the workspace.
- Main panes, icon-only playlist controls, output meters, and transport controls have explicit accessibility labels for VoiceOver and keyboard-oriented use.
- Packaged-app smoke launch evidence is available through `npm run native:smoke`.
- Packaged-app external import evidence is available through `npm run native:stress:open-import`.
- Packaged-app session evidence is available through `npm run native:stress:session`.
- Remaining production work: visual polish, accessibility, and longer real-session usability passes.

### Phase 7: Packaging

Status: implemented foundation.

- Xcode 26.5 is selected and `xcodebuild` is available.
- `scripts/package-native-app.sh` builds a release app bundle from the Swift executable.
- The package script generates icon resources, copies the planner script and Node runtime, signs the app, verifies codesign, and emits app/zip/dmg artifacts.
- The package script writes `native/dist/release-manifest.json` with source/toolchain provenance, checksums, and local verification evidence for each distribution artifact.
- `native:preflight:local` runs the full local release-candidate gate and records a JSON report in `native/dist/local-preflight-report.json`.
- `native:release:verify:local` writes `native/dist/local-release-verification-report.json` with checksum, codesign, ZIP, DMG, quarantine simulation, copied-installed-app, and expected local signing/notary/Gatekeeper warnings.
- `native:release:smoke` writes `native/dist/release-smoke-report.json` after launching the packaged app bundle, the app inside the mounted DMG, and a copied installed app, with checksums and source provenance tied to `native/dist/release-manifest.json`.
- `native:preflight:release` fails fast without Developer ID/notary readiness and authenticated notary credentials, then runs the local quality gate and records `native/dist/release-preflight-report.json`.
- `native:release:setup` stores a validated Apple notary profile in the macOS keychain so release builds do not require raw Apple credentials each time.
- `native:release` runs strict release preflight first, stores Apple notary submit/log evidence, then writes strict `native/dist/release-verification-report.json` with normal and quarantine-simulated Gatekeeper evidence plus app/DMG/install smoke evidence after packaging and notarization. The release ZIP is regenerated after app stapling so it contains the final stapled app bundle.
- Optional Developer ID notarization is supported through `NOTARIZE=1`.
- Remaining production work: run actual notarization with project Apple credentials, staple the shipped artifacts, and complete Gatekeeper verification on a clean machine.

## Current Tooling State

Xcode is installed and selected:

```txt
/Applications/Xcode.app/Contents/Developer
Xcode 26.5
```

The default local app bundle is ad-hoc signed for development. Gatekeeper `spctl` rejection is expected until Developer ID signing and notarization are run with valid Apple credentials.
