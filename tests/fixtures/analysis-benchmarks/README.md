# Analysis Benchmark Fixtures

These fixtures evaluate BeatDropper `TrackAnalysis` output against manually chosen timing expectations.

Use two fixture kinds:

- `synthetic`: generated timing cases committed to the repo.
- `snapshot`: captured analysis from a real private-library track. Do not commit audio files.
- `real_audio`: anonymized, independently reviewed schema-v2 labels used by aggregate corpus gates. Audio is never embedded.

Snapshot fixtures should contain:

- `kind: "snapshot"`
- `trackReference` with a non-sensitive title/artist or private note
- `expected.bpm`, `expected.firstDownbeatSec`, `expected.outroCueSec`, and enough `barGridSec` / `phraseBoundarySec` checkpoints to catch drift
- `analysis`, copied from the app's saved `TrackAnalysis` JSON for that track

Create a private snapshot fixture from a saved native app analysis cache entry:

```sh
npm run native:benchmark:analysis:create -- --list-cache
npm run native:benchmark:analysis:create -- --track-id "TRACK_ID_FROM_CACHE" --out-dir ~/beatdropper-analysis-snapshots
```

Create from an exported/copied analysis JSON file:

```sh
npm run native:benchmark:analysis:create -- --analysis-file ./analysis.json --out-dir ~/beatdropper-analysis-snapshots
```

Run default committed fixtures:

```sh
npm run native:benchmark:analysis
```

Run a private snapshot directory without committing it:

```sh
npm run native:benchmark:analysis -- --fixture-dir ~/beatdropper-analysis-snapshots
```

Run only private snapshots:

```sh
npm run native:benchmark:analysis -- --no-default-fixtures --fixture-dir ~/beatdropper-analysis-snapshots
```

Private snapshot fixtures should stay outside the repo unless the audio source is synthetic or cleared for sharing.

Extract the current native analysis for a private audio file without changing its production DSP implementation:

```sh
npm run native:benchmark:analysis:extract -- /path/to/private.wav ~/beatdropper-real-audio-benchmarks/analyses/cal-006.json
```

## Real-audio corpus fixtures

The proposed format, split policy, privacy rules, metrics, and approval boundary are documented in
`docs/dsp-real-audio-benchmark-foundation-2026-08-10.md`. A real-audio fixture requires corpus metadata,
an opaque asset id, rights status, and schema-v2 ground truth signed by a pseudonymous reviewer.

Bootstrap a private fixture (then independently correct and review every label):

```sh
npm run native:benchmark:analysis:create -- --analysis-file ./analysis.json --out-dir ~/beatdropper-real-audio-benchmarks --real-audio --split calibration --asset-id asset-opaque-id --audio-rights private_user_owned --duration 240 --sample-rate 44100 --channel-count 2 --tempo-profile fixed --genre-tags house --reviewed-by reviewer-pseudonym
```

Report the approved gate:

```sh
npm run native:benchmark:analysis:corpus-gate -- --fixture-dir ~/beatdropper-real-audio-benchmarks
```

The gate is approved, so `--enforce-approved-corpus-gate` is available and will fail until all approved corpus coverage and quality thresholds are met.
