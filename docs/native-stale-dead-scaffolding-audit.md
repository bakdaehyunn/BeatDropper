# Native Runtime Cleanup Audit

Updated: 2026-08-15

## Outcome

BeatDropper now has one application runtime: the native macOS app under `native/`.

Removed in the native-only cleanup:

- the legacy desktop main, preload, renderer, and shared TypeScript source trees
- React/Vite UI configuration and browser/desktop end-to-end tests
- desktop-runtime dependencies, scripts, and lockfile entries
- retirement-only planning/readiness scripts and the JavaScript benchmark that loaded compiled legacy modules
- generated legacy renderer/runtime artifacts

## Intentionally Retained Compatibility Code

The Swift core still recognizes the previous desktop version's Application Support JSON files. This is a bounded, one-time data migration path for library, saved-playlist, and player-setting data. It is not an application runtime and should remain until support for upgrading existing installations is explicitly ended.

## Retained Node Tooling

Node remains limited to planner bridging, benchmark orchestration, DSP calibration, security checks, packaging, and release verification. The user-facing application and audio runtime remain Swift-native.

## Verification

Run the native-only checks with:

```sh
npm test
npm run native:build
npm run native:test
npm run native:parity:report
git diff --check
```

Release signing, notarization, and clean-machine Gatekeeper evidence remain release-readiness concerns; they no longer gate removal of a second application runtime.
