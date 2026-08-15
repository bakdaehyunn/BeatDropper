#!/usr/bin/env python3
"""Extract independent, reviewable DSP reference candidates from a local audio file."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import librosa
import numpy as np


MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
TONICS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def rounded(values, digits=3):
    return [round(float(value), digits) for value in values]


def loudness(path):
    command = [
        "ffmpeg", "-hide_banner", "-nostats", "-i", path,
        "-af", "loudnorm=I=-23:TP=-2:LRA=7:print_format=json", "-f", "null", "-"
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    start = result.stderr.rfind("{")
    end = result.stderr.rfind("}")
    if start < 0 or end < start:
        raise RuntimeError("ffmpeg loudnorm did not emit JSON")
    payload = json.loads(result.stderr[start:end + 1])
    return float(payload["input_i"]), float(payload["input_tp"])


def key_estimate(chroma):
    energy = np.mean(chroma, axis=1)
    candidates = []
    for tonic in range(12):
        candidates.append((np.corrcoef(energy, np.roll(MAJOR, tonic))[0, 1], tonic, "major"))
        candidates.append((np.corrcoef(energy, np.roll(MINOR, tonic))[0, 1], tonic, "minor"))
    score, tonic, mode = max(candidates, key=lambda item: item[0])
    return TONICS[tonic], mode, float(score)


def extract(path):
    y, sample_rate = librosa.load(path, sr=22050, mono=True)
    duration = librosa.get_duration(y=y, sr=sample_rate)
    onset = librosa.onset.onset_strength(y=y, sr=sample_rate)
    tempo, beat_frames = librosa.beat.beat_track(onset_envelope=onset, sr=sample_rate, units="frames")
    beat_frames = np.asarray(beat_frames, dtype=int)
    beat_times = librosa.frames_to_time(beat_frames, sr=sample_rate)
    if len(beat_frames) < 8:
        raise RuntimeError("insufficient beat evidence")

    phase_scores = [float(np.mean(onset[beat_frames[phase::4]])) for phase in range(4)]
    downbeat_phase = int(np.argmax(phase_scores))
    downbeats = beat_times[downbeat_phase::4]

    chroma = librosa.feature.chroma_cqt(y=y, sr=sample_rate)
    tonic, mode, key_score = key_estimate(chroma)

    bars_per_phrase = 8
    phrase_boundaries = downbeats[::bars_per_phrase]
    integrated_lufs, true_peak = loudness(path)
    return {
        "schemaVersion": 1,
        "referenceMethod": "librosa-0.11 beat/chroma plus ffmpeg-8.1 loudnorm",
        "audioDurationSec": round(float(duration), 3),
        "sampleRate": int(sample_rate),
        "bpm": round(float(np.asarray(tempo).reshape(-1)[0]), 3),
        "beatGridSec": rounded(downbeats[:32]),
        "downbeatSec": rounded(downbeats[:32]),
        "phraseBoundarySec": rounded(phrase_boundaries),
        "musicalKey": {"tonic": tonic, "mode": mode},
        "keyProfileCorrelation": round(key_score, 3),
        "integratedLUFS": round(integrated_lufs, 2),
        "truePeakDb": round(true_peak, 2),
        "cueCandidates": [
            {"type": "first_downbeat", "startSec": round(float(downbeats[0]), 3), "origin": "derived"}
        ],
        "reviewNotes": [
            "Downbeat phase selected by strongest mean onset across four beat phases.",
            "Phrase candidates are eight-bar boundaries anchored to the independent downbeat grid.",
            "Timing arrays are capped only for compact review fixtures; source analysis remains unchanged."
        ]
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("audio_file")
    parser.add_argument("--out")
    args = parser.parse_args()
    rendered = json.dumps(extract(args.audio_file), indent=2, sort_keys=True) + "\n"
    if args.out:
        destination = Path(args.out)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)


if __name__ == "__main__":
    main()
