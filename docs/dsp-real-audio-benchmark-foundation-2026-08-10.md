# BeatDropper Real-Audio DSP Benchmark Foundation

Date: 2026-08-10
Status: schema v2 and gate v1 approved on 2026-08-15; production analyzer changes remain forbidden during initial corpus construction

## Purpose

This foundation separates three concerns that were previously mixed together:

1. fixture-level regression checks;
2. real-audio corpus integrity and coverage;
3. aggregate accuracy and confidence-calibration gates.

Existing `synthetic` and `snapshot` fixtures remain valid. Only fixtures explicitly marked `kind: "real_audio"` participate in corpus gates.

## Candidate Corpus Format (schema version 2)

Every real-audio fixture must include:

```json
{
  "kind": "real_audio",
  "corpus": {
    "schemaVersion": 2,
    "split": "calibration",
    "anonymizedAssetId": "asset-opaque-id",
    "audioRights": "private_user_owned",
    "audioDurationSec": 240,
    "sampleRate": 44100,
    "channelCount": 2,
    "genreTags": ["house"],
    "tempoProfile": "fixed",
    "referenceTools": [
      { "name": "ffmpeg loudnorm", "version": "...", "settings": "EBU R128" }
    ]
  },
  "groundTruthLabels": {
    "schemaVersion": 2,
    "reviewedBy": "reviewer-pseudonym",
    "reviewedAt": "ISO-8601 timestamp",
    "expected": {}
  },
  "analysis": {}
}
```

Allowed rights values are `private_user_owned` and `redistribution_cleared`. Audio is not embedded in fixtures. Private audio and identifying titles/artists stay outside the repository. `anonymizedAssetId` is an opaque local mapping key, not a filename, title, or reversible path.

## Labels

The candidate schema supports:

- scalar BPM;
- bar-grid checkpoints for long-form drift;
- repeated downbeat timestamps plus first-downbeat compatibility;
- phrase-boundary timestamps;
- tonic and major/minor key;
- integrated LUFS and true peak;
- typed cue timestamps and reviewer-approved cue origins;
- stored analyzer confidence values for every supported concept.

Ground truth must be independent of the captured BeatDropper analysis. The fixture creator may bootstrap labels, but bootstrapped values remain unapproved until a reviewer corrects and signs them.

## Split Policy

- `calibration`: may be used to tune thresholds and confidence mappings.
- `validation`: frozen holdout used to approve an algorithm change.
- `regression`: small, durable failure set used on every relevant change.

An asset id must belong to exactly one split. Algorithm development must not inspect or tune against validation labels after the split is frozen.

## Metrics

For each concept the report includes labeled count, correctness count, accuracy, p50 error, p95 error, and confidence calibration when confidence exists.

Confidence calibration uses five fixed bins and reports:

- observed accuracy;
- mean predicted confidence;
- expected calibration error (ECE);
- Brier score.

Key error is binary exact tonic/mode mismatch. Timing and loudness concepts report their natural units: BPM, seconds, LU, or dBTP.

## Candidate Gate

The approved thresholds live in `docs/dsp-benchmark-corpus-gate-v1.json`. They intentionally require 60 real-audio fixtures and non-trivial calibration/validation/regression coverage. The most important quality targets are:

- BPM p95 error at most 1 BPM;
- beatgrid p95 average drift at most 180 ms;
- downbeat p95 average distance at most 150 ms;
- phrase p95 average distance at most 2 seconds;
- exact key accuracy at least 75%;
- LUFS p95 delta at most 0.2 LU;
- true-peak p95 delta at most 0.5 dBTP;
- cue p95 distance at most 1 second;
- concept ECE generally at most 0.10–0.15.

The gate was approved by the user through the active goal on 2026-08-15. The configuration records `status: "approved"`, `approvedBy`, and `approvedAt`. Enforcement now fails when the corpus does not meet the approved coverage and quality thresholds.

## Approved Boundary

The following were approved on 2026-08-15:

1. corpus schema version 2;
2. the 30/20/10 split minimums;
3. concept coverage counts;
4. accuracy and p95 thresholds;
5. ECE/Brier thresholds;
6. privacy and rights rules.

No production BPM, beatgrid, downbeat, phrase, key, loudness, true-peak, or cue algorithm is changed while building the first reviewed calibration batch. Any later algorithm goal must use the frozen validation split and enforce this approved gate.
