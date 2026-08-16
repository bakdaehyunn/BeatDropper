# BeatDropper Native UI Redesign — 2026-08-16

## Scope

The native SwiftUI application was reorganized from a collection of peer panels into two focused workflows derived from the approved Sites review. Playback, DSP analysis, planning, library persistence, saved sets, migration, shortcuts, and accessibility behavior remain owned by the existing native model and engine.

No Electron, React, Vite, or web runtime was added to the product repository.

## Implemented hierarchy

- Shared shell
  - one persistent bottom transport across Playing and Creative
- current track and playback state, elapsed/total progress, previous/play/next, AI Mix, and master output
  - responsive wide/compact toolbar and transport layouts
  - workspace-only scrolling so the transport stays visible at the 760 × 520 minimum window size
- Playing
  - current deck → transition decision → next deck hero
  - stacked current/next waveforms with play/OUT/IN markers
  - the incoming deck publishes its own elapsed position during crossfade, so the Next waveform gains a moving PLAY cursor before promotion to Current
  - countdown, planner confidence, mix style, rendered quality, and evidence disclosure
  - active transitions retain their plan and show bar count, calculated duration, beat-grid/seconds source, OUT/IN points, and live progress for both decks
  - compact Current/Next/Remaining set-flow summary and row states for Current, Next, Analyzing, Pending, Ready, and Missing
- Creative
  - track-preparation studio with waveform, cue editing, preview transport, and analysis metrics
  - BPM override and tap workflow presented as the real beat-grid correction control
  - saved-set builder, searchable library, and analysis-derived energy-flow strip
- Hardening
  - Space controls live playback in Playing and preview playback in Creative, without competing shortcuts
  - AI Mix toggle animation respects Reduce Motion
  - empty, analysis-in-progress, missing-file, planner, and recovery states continue to use the existing native state model

## Verification results

- Swift build passed; the full Swift suite passed 151 tests across 26 suites.
- Native accessibility passed 49 checks; native macOS shell integration passed 15 checks.
- Node tooling passed 22 tests across 5 files.
- Ad-hoc `BeatDropper.app`, ZIP, and DMG packaging passed codesign and DMG verification.
- Packaged app smoke reported one visible key window named BeatDropper.
- Packaged playback stress completed two DSP-backed transitions, confirmed both incoming playheads advanced, preserved an active transition across pause/resume and simulated device recovery, and returned to Idle.
- Extended packaged session stress imported and analyzed 12 tracks with bounded concurrency, applied planner/DSP state through six transitions, confirmed every incoming handoff, and returned to Idle.
- Playing, Creative, and the 760 × 520 compact layout were visually checked; the compact workspace scrolls while the shared transport remains anchored.
- Active product source, manifests, native targets, scripts, and tests passed the Electron runtime-reference scan.
- The complete 16-step local native preflight passed after the transition redesign.

Developer ID signing, notarization, and Gatekeeper acceptance remain external release-credential work and are not blockers for a local ad-hoc build.
