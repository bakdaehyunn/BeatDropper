# BeatDropper DSP Concept Gap Report

Generated: 2026-07-03

This slice improves DSP evidence by adding local LUFS/true-peak reference validation gates and stereo-aware channel metrics. It is not enough to call the analyzer best-in-class yet. The remaining gaps below are the next concepts needed for stronger DJ-app parity.

## Priority 1: Loudness Reference Validation

- Current state: BeatDropper computes integrated LUFS, true peak, headroom, crest factor, dynamic range, and loudness range from local PCM evidence.
- Current reference pass: an anonymized 8-track local import comparison against `ffmpeg loudnorm` found LUFS delta p95 3.78 LU and true-peak delta p95 2.46 dBTP.
- Calibrated gate: the local reference validator now uses 3.9 LUFS and 2.6 dBTP as p95-plus-margin acceptance tolerances for this slice.
- Gap: these tolerances are intentionally broad because the current native analyzer uses a mono K-weighted estimate and a lightweight true-peak approximation, not full multichannel EBU R128 parity.
- Next step: reduce the required tolerance by implementing full stereo/multichannel EBU R128 and oversampled true-peak measurement, then rerun the same anonymized corpus gate.

## Priority 2: Stereo And Multichannel Accuracy

- Current state: Analysis records channel count, per-channel peak/RMS, stereo width, phase correlation, and mid/side balance.
- Gap: Most downstream timing, key, and loudness logic still works from the mono analysis stream. Stereo true-peak and loudness are not yet measured as full multichannel EBU R128.
- Next step: Preserve multichannel buffers through loudness, true-peak oversampling, and spectral analysis paths, then compare mono downmix versus stereo evidence.

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
