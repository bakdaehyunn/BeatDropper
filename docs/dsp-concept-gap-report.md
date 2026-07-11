# BeatDropper DSP Concept Gap Report

Generated: 2026-07-03

This slice improves DSP evidence by adding local LUFS/true-peak reference validation gates, stereo-aware channel metrics, multichannel loudness measurement, and a bounded oversampled true-peak estimate. It is not enough to call the analyzer best-in-class yet. The remaining gaps below are the next concepts needed for stronger DJ-app parity.

## Priority 1: Loudness Reference Validation

- Current state: BeatDropper computes integrated LUFS, true peak, headroom, crest factor, dynamic range, and loudness range from local PCM channel evidence when preserved channel samples are available.
- Previous reference pass: an anonymized 8-track local import comparison against `ffmpeg loudnorm` found LUFS delta p95 3.78 LU and true-peak delta p95 2.46 dBTP.
- Current reference pass: after multichannel loudness summing and bounded 4x cubic true-peak interpolation, the same validation command compared 8/8 files with LUFS delta p95 0.07 LU and true-peak delta p95 1.57 dBTP.
- Calibrated gate: the local reference validator now uses 0.2 LUFS and 1.8 dBTP as p95-plus-margin acceptance tolerances for this slice.
- Gap: true peak is still a bounded cubic oversampling estimate, not a full standards-grade oversampling filter, and channel weighting still assumes a conventional layout when no explicit channel layout metadata is available.
- Next step: replace the bounded true-peak estimate with a verified BS.1770-style oversampling filter, persist channel layout when available, then expand the anonymized corpus beyond 8 files.

## Priority 2: Stereo And Multichannel Accuracy

- Current state: Analysis records channel count, per-channel peak/RMS, stereo width, phase correlation, and mid/side balance. Loudness and true peak now use preserved channel samples instead of relying only on the mono analysis stream.
- Gap: Most downstream timing, key, and spectral logic still works from the mono analysis stream. Loudness channel weighting is layout-assumed rather than layout-metadata-driven.
- Next step: Preserve channel layout metadata through import/analysis and compare mono downmix versus stereo evidence in benchmark fixtures.

## Priority 3: Key Detection

- Current state: Harmonic key uses chroma-style local evidence and confidence checks.
- Gap: It lacks stronger DJ-grade concepts such as HPSS, CQT/HPCP features, tuning correction, Camelot/Open Key mapping, sectional key changes, and confidence calibration against labeled music.
- Next step: Add a key-evaluation fixture set with labeled major/minor and ambiguous tracks before changing the algorithm.

## Priority 4: Beatgrid And Tempo Drift

- Current state: Beat and bar evidence is derived from transient and energy evidence with benchmark gates.
- Gap: It does not yet model variable tempo, beatgrid drift correction, half/double-tempo ambiguity, or long-form bar alignment against reference grids.
- Next step: Add fixture cases for drift, tempo ramps, half/double BPM, and weak downbeats, then introduce a grid optimizer.

## Priority 5: Phrase And Structure

- Current state: Phrase markers and cue candidates use energy and transient structure.
- Gap: It does not explicitly classify intro, breakdown, buildup, drop, chorus, bridge, outro, vocal sections, or transition-safe regions.
- Next step: Add novelty-curve segmentation and section labels, then use those labels in cue ranking.

## Priority 6: Cue Ranking

- Current state: Cue candidates are now distinguished by derived evidence versus placeholder origin.
- Gap: Cue quality is still rule-calibrated, not learned or validated against DJ-reviewed labels.
- Next step: Capture anonymized user-reviewed cue labels and evaluate ranking precision/recall by cue type.

## Priority 7: Spectral And Timbre Evidence

- Current state: Low/mid/high spectral bands and transient evidence are available.
- Gap: It lacks richer features used in competitive analysis workflows, including Mel or Bark bands, MFCC-style timbre, vocal/percussion likelihood, spectral contrast, and stem-aware evidence.
- Next step: Extend fixture snapshots with richer spectral summaries before introducing UI decisions that depend on them.

## Priority 8: Confidence Calibration

- Current state: Confidence values are bounded and tested, but thresholds remain calibrated constants.
- Gap: Confidence is not yet tied to reliability curves from real-track outcomes.
- Next step: Store anonymized validation outcomes, plot predicted confidence versus observed correctness, and tune thresholds per concept.
