# DJ Set Operations UI Design Freeze - 2026-05-01

## Scope
- Rework the main renderer UI around a DJ loading and operating a prepared set.
- Keep the current working playlist model: load, append, reorder, remove, clear, play.
- Surface existing track and AI mix data without inventing unavailable analysis.

## Non-goals
- No saved playlist library.
- No real USB folder tree.
- No key, energy, waveform, or phrase analysis beyond existing contracts.

## Locked Decisions
- Main screen is set-operations oriented: source/load bar, Now/Mix/Next cockpit, large playlist table.
- Playlist rows show order, status, title, BPM, length, format, cue, and mix-readiness.
- Mix panel shows AI plan or rule-based fallback information from existing player events.
- Track analysis is loaded through the existing `getTrackAnalysis` API and shown as available.

## Current vs Target
- Current: source and generic queue panels compete with playlist space.
- Target: source is a compact bar; the center is Now/Mix/Next; playlist is the dominant lower workspace.

## Risks
- Existing event data is session-only, so mix plan details appear after playback/planner events.
- Missing BPM/cue data remains `--` until metadata or analysis resolves it.
