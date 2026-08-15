# Native Playback DSP Execution

Date: 2026-08-10

## Goal

Make the native playback path execute the gain, EQ, filter, loudness, tempo-sync, and clip-protection controls carried by `MixPlan`. The implementation keeps the planner contract unchanged and uses only Apple audio units.

## Audio Graph

Each deck uses the same processing chain:

```text
AVAudioPlayerNode
  -> AVAudioUnitTimePitch
  -> AVAudioUnitEQ (low shelf, parametric mid, high shelf, transition filter)
  -> AVAudioMixerNode (equal-power crossfade gain)
```

The two deck mixers feed the master chain:

```text
deck A + deck B
  -> master summing mixer
  -> Apple peak limiter
  -> ceiling/output mixer
  -> AVAudioEngine main mixer
```

Deck meters are tapped after each deck's DSP chain. The master meter remains after deck summing, limiting, and ceiling attenuation.

## Control Mapping

| Planner control | Runtime behavior |
| --- | --- |
| outgoing/incoming trim | Applied through the deck EQ unit's global gain |
| target integrated LUFS | Adds a bounded `target - measured` correction when analysis confidence is at least 0.45 |
| maximum peak | Caps positive loudness/trim gain using analyzed true peak |
| low EQ | 200 Hz low shelf |
| mid EQ | 1 kHz parametric band |
| high EQ | 6 kHz high shelf |
| high-pass/low-pass | Fourth EQ band with logarithmic start-to-end frequency automation |
| tempo sync | Incoming `AVAudioUnitTimePitch.rate`; pitch remains zero cents |
| soft limit | Apple peak limiter followed by configured ceiling attenuation |
| monitor only | Limiter bypassed; metering remains active |

The shared `PlaybackDSPResolver` is authoritative for parameter sanitization. Loudness correction is limited to ±6 dB, combined deck gain to -12...+6 dB, playback rate to 0.85...1.15, filter frequency to 20...20,000 Hz, and peak ceiling to -6...-0.1 dB.

## Automation And State

- Equal-power crossfade and filter automation advance on the existing 30 Hz transition clock.
- Gain, EQ, and playback-rate changes use a bounded ramp and reach their exact targets within the first 15% of a transition instead of changing discontinuously.
- The incoming deck is configured before it becomes audible.
- Pause keeps the graph and parameter state intact.
- Audio-device configuration recovery snapshots applied and target deck settings, crossfade position, and master protection, then restores them before playback resumes.
- Stopping playback returns both decks and the master chain to neutral DSP settings.

## Verification

Generated-PCM reference tests cover:

- neutral/bypass equivalence within `0.000001` linear sample delta;
- combined trim, LUFS correction, and true-peak gain limiting;
- three-band EQ direction at 80 Hz, 1 kHz, and 10 kHz;
- high-pass and low-pass rejection greater than 30 dB at opposing test frequencies;
- monotonic logarithmic filter automation;
- master output bounded by the configured soft-limit ceiling;
- equal-power transition endpoints and midpoint;
- Apple `AVAudioUnitEQ` offline rendering for low-shelf boost and high-pass rejection;
- the Apple peak-limiter/output-ceiling chain against rendered PCM;
- Apple `AVAudioUnitTimePitch` offline rendering at 1.1x with measured pitch within 5 Hz of a 440 Hz source.

The full native build and test suite remain the release gate for this change.

## Known Limitations

- The Apple peak limiter exposes a fixed 0 dB limiting point. BeatDropper raises pre-gain by the ceiling magnitude and attenuates after limiting to implement a lower output ceiling.
- EQ/filter verification uses a deterministic reference renderer; the native graph uses Apple's production audio units with the same control mapping rather than identical biquad coefficients.
- The 30 Hz control clock is bounded and smoothed but is not sample-accurate automation.
- Tempo-synchronized playback-position calibration against long real files remains a device/runtime validation concern; rendered pitch and duration behavior are covered offline.
- This slice does not change analysis algorithms or add a real-music DSP corpus.
