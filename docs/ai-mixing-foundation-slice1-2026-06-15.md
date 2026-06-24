# AI Mixing Foundation Slice 1

## Purpose

BeatDropper currently plans DJ transitions: timing, next-track offset, style, tempo sync, phrase alignment, energy strategy, confidence, and evidence. Slice 1 adds a backward-compatible planning contract for future AI mixing controls without changing realtime audio execution.

## Current Gaps

- The native audio engine executes equal-power deck crossfades and output metering, but does not execute EQ, filter, limiter, loudness, ducking, or stem-aware automation.
- Track analysis provides BPM, beat/bar/phrase grids, energy, coarse low/mid/high spectral bands, transients, and cue candidates. It does not provide key, vocal sections, stem classes, LUFS, masking, or rendered-transition quality metrics.
- Planner benchmarks validate timing, style, confidence, candidate choice, and evidence. They do not validate audible mix quality.
- User preparation stores BPM overrides and hot cues only. It does not yet capture vocal-safe, harmonic-safe, EQ, gain, or energy-shaping intent.

## Slice 1 Design

`MixPlan.mixControls` is optional so older planner artifacts and CLI responses remain valid. When validation succeeds, BeatDropper clamps or defaults the controls into conservative planning metadata:

- `gain`: outgoing and incoming deck trim in dB.
- `eq`: three-band outgoing/incoming EQ hints in dB.
- `filter`: optional outgoing/incoming low-pass or high-pass sweep hints.
- `loudness`: optional target LUFS metadata and peak ceiling metadata.
- `clipProtection`: monitor-only or soft-limit intent metadata.
- `qualityNotes`: short planner/debug notes.

The native fallback planner emits conservative defaults. The Codex schema allows `mixControls` but does not require it. The prompt states that controls are metadata for a later deterministic DSP executor and must not request realtime AI control.

## Explicit Non-Goals

- No realtime AI calls inside the audio loop.
- No EQ, filter, limiter, loudness, stem, vocal, key, or LUFS DSP implementation.
- No audio-engine behavior change.
- No Electron retirement or broad cleanup.
- No commit or push.

## Future Slices

1. Add rendered-transition quality analysis for clipping, peak jump, RMS/loudness jump, and spectral masking risk. Done in slice 2 as an offline BeatDropperCore estimator.
2. Add native DSP execution for a very small subset of validated controls, starting with deck gain trim only.
3. Add user intent controls such as vocal-safe, harmonic-safe, long blend, quick swap, energy lift, energy drop, and bass-safe blend.
4. Add richer analysis fields: key/Camelot, section labels, vocal probability, bass/kick density, and approximate loudness.
5. Add UI/debug review for proposed mix controls before they can affect playback.

## Verification Expectations

- Existing `MixPlan` JSON without `mixControls` decodes.
- Validation clamps unsafe control ranges and defaults missing controls.
- Native fallback plans include conservative metadata.
- Codex planner schema accepts but does not require `mixControls`.
- Planner prompt preserves the deterministic execution boundary.
- Native planner and analysis benchmarks are run; existing analysis fixture failures are reported plainly.
