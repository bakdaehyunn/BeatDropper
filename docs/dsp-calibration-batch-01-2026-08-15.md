# DSP Calibration Batch 01

Date: 2026-08-15
Status: five reference-reviewed private calibration fixtures; human audition pending

## Batch

- Five user-owned WAV masters.
- Split: `calibration` only.
- Fixtures: `cal-001` through `cal-005`.
- Private artifact directory: `~/beatdropper-real-audio-benchmarks/calibration-v1`.
- Audio, filenames, titles, artists, and the local asset mapping are not committed.
- Each fixture has schema-v2 labels, a pseudonymous reviewer, review timestamp, opaque asset id, rights status, and independent reference-tool provenance.

## Review Method

Reference candidates were extracted independently from BeatDropper using librosa 0.11.0 for beat/chroma analysis and FFmpeg 8.1.2 `loudnorm` for EBU R128 integrated loudness and true peak. Downbeat phase was selected from the strongest four-beat onset phase. Phrase candidates use eight-bar boundaries anchored to that independent downbeat grid. The resulting labels were checked for finite values, duration bounds, unique asset ids, anonymization, and successful schema decoding.

The extraction environment is intentionally external to the app and can be recreated with:

```sh
python3 -m pip install --target /tmp/beatdropper-reference-env -r scripts/requirements-dsp-reference.txt
PYTHONPATH=/tmp/beatdropper-reference-env python3 scripts/extract-dsp-reference.py /path/to/private.wav --out /private/reference.json
```

## Baseline Result

The batch has zero corpus-integrity issues and labels all eight Goal 2 concepts on all five fixtures. The approved aggregate gate is correctly enforceable but unmet because the corpus is only 5/60 and contains no validation or regression fixtures yet.

This first baseline also exposes real production-analysis gaps without changing production code: all five analyses fail the reference-reviewed fixtures. The four older cache entries lack key and loudness evidence; the fifth fresh extraction supplies those fields but still misses the independent key and timing labels. Detailed private metrics are stored in `~/beatdropper-real-audio-benchmarks/calibration-v1-report.json`.

## Boundary

No production DSP analyzer was modified. This batch is calibration data, not evidence that the 60-track release gate passes. Validation labels remain uncreated and must be frozen before later algorithm tuning.

## Human Audition

Batch 01 remains reference-reviewed until a person listens to the timing-click and key excerpts. Keep the private asset-to-path map outside the repository, then run:

```sh
npm run native:benchmark:analysis:review -- --batch-dir ~/beatdropper-real-audio-benchmarks/calibration-v1 --audio-map ~/beatdropper-real-audio-benchmarks/audio-map.json --reviewer reviewer-pseudonym
```

The review tool records separate receipts under `~/beatdropper-real-audio-benchmarks/human-reviews`. A fixture is updated only when both timing and key are accepted or edited. Rejected and skipped decisions remain incomplete. Automated answer files are marked `SIMULATED_REVIEW` and fail corpus integrity, so tests cannot masquerade as human approval.

## Expansion Intake

Inventory additional user-owned audio without copying it or committing paths:

```sh
npm run native:benchmark:analysis:inventory -- --root /path/to/private/audio --manifest ~/beatdropper-real-audio-benchmarks/manifest.json --out ~/beatdropper-real-audio-benchmarks/intake.json --target 30
```

The inventory hashes files, deduplicates byte-identical copies, excludes existing batch hashes, and reports the exact shortage. As of 2026-08-15, the accessible folders contain five unique audio files total, and all five are now in batch 01. Twenty-five additional distinct tracks are still required to reach 30.
