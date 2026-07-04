import { buildTrackAnalysisFromAudioBuffer } from '../../src/renderer/player/trackAnalysisBuilder';
import { Track } from '../../src/shared/types';

class TestAudioBuffer {
  readonly duration: number;
  readonly sampleRate: number;
  readonly numberOfChannels = 1;
  private readonly data: Float32Array;

  constructor(data: Float32Array, sampleRate: number) {
    this.data = data;
    this.sampleRate = sampleRate;
    this.duration = data.length / sampleRate;
  }

  getChannelData(): Float32Array {
    return this.data;
  }
}

const buildFakeBuffer = (duration = 32, sampleRate = 8000) => {
  const length = duration * sampleRate;
  const data = new Float32Array(length);
  for (let index = 0; index < length; index += 1) {
    const sec = index / sampleRate;
    const pulse = Math.sin(sec * Math.PI * 4) > 0.92 ? 0.7 : 0.08;
    data[index] = pulse * Math.sin(sec * Math.PI * 440);
  }

  return {
    duration,
    sampleRate,
    numberOfChannels: 1,
    getChannelData: () => data
  };
};

const buildPulseBuffer = ({
  bpm,
  durationSec,
  offsetSec = 0,
  accentEvery = 4,
  sampleRate = 22050
}: {
  bpm: number;
  durationSec: number;
  offsetSec?: number;
  accentEvery?: number;
  sampleRate?: number;
}): TestAudioBuffer => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  const beatIntervalSec = 60 / bpm;
  const pulseLength = Math.floor(sampleRate * 0.035);
  let beatIndex = 0;

  for (let timeSec = offsetSec; timeSec < durationSec; timeSec += beatIntervalSec) {
    const start = Math.floor(timeSec * sampleRate);
    const gain = beatIndex % accentEvery === 0 ? 1 : 0.42;
    for (let offset = 0; offset < pulseLength; offset += 1) {
      const index = start + offset;
      if (index >= length) {
        break;
      }
      const decay = Math.exp(-offset / 150);
      data[index] += gain * decay;
    }
    beatIndex += 1;
  }

  return new TestAudioBuffer(data, sampleRate);
};

const buildSectionedPulseBuffer = ({
  bpm,
  durationSec,
  offsetSec = 0,
  sampleRate = 22050,
  gainAt
}: {
  bpm: number;
  durationSec: number;
  offsetSec?: number;
  sampleRate?: number;
  gainAt: (timeSec: number, beatIndex: number) => number;
}): TestAudioBuffer => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  const beatIntervalSec = 60 / bpm;
  const pulseLength = Math.floor(sampleRate * 0.035);
  let beatIndex = 0;

  for (let timeSec = offsetSec; timeSec < durationSec; timeSec += beatIntervalSec) {
    const start = Math.floor(timeSec * sampleRate);
    const gain = gainAt(timeSec, beatIndex);
    for (let offset = 0; offset < pulseLength; offset += 1) {
      const index = start + offset;
      if (index >= length) {
        break;
      }
      const decay = Math.exp(-offset / 150);
      data[index] += gain * decay;
    }
    beatIndex += 1;
  }

  return new TestAudioBuffer(data, sampleRate);
};

const buildSpectralShiftPulseBuffer = ({
  bpm,
  durationSec,
  offsetSec = 0.18,
  sampleRate = 22050
}: {
  bpm: number;
  durationSec: number;
  offsetSec?: number;
  sampleRate?: number;
}): TestAudioBuffer => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  const beatIntervalSec = 60 / bpm;
  const shiftLengthSec = 0.055;
  const amplitude = 0.34;

  for (let index = 0; index < length; index += 1) {
    const timeSec = index / sampleRate;
    const beatPhase =
      timeSec >= offsetSec ? (timeSec - offsetSec) % beatIntervalSec : beatIntervalSec;
    const isSpectralOnset = beatPhase <= shiftLengthSec;
    const frequency = isSpectralOnset ? 2600 : 180;
    data[index] = amplitude * Math.sin(timeSec * Math.PI * 2 * frequency);
  }

  return new TestAudioBuffer(data, sampleRate);
};

const buildConstantToneBuffer = ({
  durationSec,
  sampleRate = 22050,
  frequency = 120,
  amplitude = 0.32
}: {
  durationSec: number;
  sampleRate?: number;
  frequency?: number;
  amplitude?: number;
}): TestAudioBuffer => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  for (let index = 0; index < length; index += 1) {
    const timeSec = index / sampleRate;
    data[index] = amplitude * Math.sin(timeSec * Math.PI * 2 * frequency);
  }
  return new TestAudioBuffer(data, sampleRate);
};

const buildGradualFadePulseBuffer = ({
  bpm,
  durationSec,
  offsetSec = 0.1,
  sampleRate = 22050
}: {
  bpm: number;
  durationSec: number;
  offsetSec?: number;
  sampleRate?: number;
}): TestAudioBuffer => {
  return buildSectionedPulseBuffer({
    bpm,
    durationSec,
    offsetSec,
    sampleRate,
    gainAt: (timeSec, beatIndex) => {
      const accent = beatIndex % 4 === 0 ? 1 : 0.45;
      return accent * Math.max(0.12, 1 - timeSec / durationSec);
    }
  });
};

const buildNoisyOffGridTransientBuffer = (
  durationSec: number,
  sampleRate = 22050
): TestAudioBuffer => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  let seed = 4277009102;
  const nextRandom = (): number => {
    seed = (seed * 1664525 + 1013904223) % 0x100000000;
    return seed / 0x100000000;
  };

  for (let index = 0; index < length; index += 1) {
    const timeSec = index / sampleRate;
    data[index] = 0.025 * Math.sin(timeSec * Math.PI * 2 * 150);
  }

  for (let burst = 0; burst < 72; burst += 1) {
    let timeSec = 0.15 + nextRandom() * Math.max(1, durationSec - 0.3);
    const beatPhase = timeSec % 0.5;
    if (beatPhase < 0.14 || beatPhase > 0.36) {
      timeSec += 0.19;
    }
    const start = Math.floor(Math.min(durationSec - 0.05, timeSec) * sampleRate);
    const pulseLength = Math.floor(sampleRate * 0.024);
    const frequency = 700 + nextRandom() * 3200;
    const gain = 0.28 + nextRandom() * 0.45;
    for (let offset = 0; offset < pulseLength; offset += 1) {
      const index = start + offset;
      if (index >= length) {
        break;
      }
      const sampleTime = index / sampleRate;
      const decay = Math.exp(-offset / 95);
      data[index] += gain * decay * Math.sin(sampleTime * Math.PI * 2 * frequency);
    }
  }

  return new TestAudioBuffer(data, sampleRate);
};

describe('buildTrackAnalysisFromAudioBuffer', () => {
  it('builds waveform, energy, bar, phrase, and cue data for a track', () => {
    const track: Track = {
      id: 'track-1',
      title: 'Track 1',
      durationSec: 32,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(track, buildFakeBuffer());

    expect(analysis.trackId).toBe(track.id);
    expect(analysis.bpm).toBe(120);
    expect(analysis.waveformPeaks.length).toBeGreaterThan(0);
    expect(analysis.waveformDetail.length).toBeGreaterThan(analysis.waveformPeaks.length);
    expect(analysis.spectralBands.length).toBe(analysis.waveformDetail.length);
    expect(analysis.transientMarkers.length).toBeGreaterThan(0);
    expect(analysis.energyProfile.length).toBeGreaterThan(0);
    expect(analysis.beatGridSec.length).toBeGreaterThan(0);
    expect(analysis.barGrid.length).toBeGreaterThan(0);
    expect(analysis.phraseMarkers.length).toBeGreaterThan(0);
    expect(analysis.cueCandidates.map((cue) => cue.type)).toEqual(
      expect.arrayContaining(['intro', 'outro'])
    );
    expect(analysis.analysisQuality.waveformDetail).toBeGreaterThan(0);
    expect(analysis.analysisQuality.spectralBands).toBeGreaterThan(0);
  });

  it('aligns beat and bar grids to detected pulse offset instead of always starting at zero', () => {
    const track: Track = {
      id: 'offset-track',
      title: 'Offset Track',
      durationSec: 64,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildPulseBuffer({ bpm: 120, durationSec: 64, offsetSec: 0.18 })
    );

    expect(analysis.beatGridSec[0]).toBeGreaterThanOrEqual(0.1);
    expect(analysis.beatGridSec[0]).toBeLessThanOrEqual(0.3);
    expect(analysis.barGrid[0]?.startSec).toBeGreaterThanOrEqual(0.1);
    expect(analysis.barGrid[0]?.startSec).toBeLessThanOrEqual(0.3);
    expect(analysis.analysisQuality.beatGrid).toBeGreaterThan(0.45);
  });

  it('uses spectral flux to detect beat onsets when RMS stays nearly stable', () => {
    const track: Track = {
      id: 'spectral-onset-track',
      title: 'Spectral Onset Track',
      durationSec: 48,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildSpectralShiftPulseBuffer({ bpm: 120, durationSec: 48, offsetSec: 0.18 })
    );

    expect(
      analysis.transientMarkers.some((marker) => Math.abs(marker.timeSec - 0.18) < 0.12)
    ).toBe(true);
    expect(analysis.transientMarkers.length).toBeGreaterThan(20);
    expect(analysis.beatGridSec[0]).toBeGreaterThanOrEqual(0.08);
    expect(analysis.beatGridSec[0]).toBeLessThanOrEqual(0.3);
    expect(analysis.analysisQuality.beatGrid).toBeGreaterThan(0.35);
  });

  it('scores beat-aligned transient evidence above noisy off-grid markers', () => {
    const track: Track = {
      id: 'transient-quality-track',
      title: 'Transient Quality Track',
      durationSec: 48,
      format: 'wav',
      bpm: 120
    };

    const clean = buildTrackAnalysisFromAudioBuffer(
      track,
      buildPulseBuffer({ bpm: 120, durationSec: 48, offsetSec: 0.18 })
    );
    const noisy = buildTrackAnalysisFromAudioBuffer(
      { ...track, id: 'off-grid-noisy-transients' },
      buildNoisyOffGridTransientBuffer(48)
    );

    expect(clean.analysisQuality.transientMarkers).toBeGreaterThan(0.45);
    expect(clean.analysisQuality.transientMarkers).toBeGreaterThan(
      noisy.analysisQuality.transientMarkers + 0.12
    );
  });

  it('snaps cue candidates to bar boundaries for planner-ready mix points', () => {
    const track: Track = {
      id: 'cue-track',
      title: 'Cue Track',
      durationSec: 96,
      format: 'wav',
      bpm: 124
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildPulseBuffer({ bpm: 124, durationSec: 96, offsetSec: 0.12 })
    );
    const outro = analysis.cueCandidates.find((cue) => cue.type === 'outro');
    const firstDownbeat = analysis.cueCandidates.find((cue) => cue.type === 'first_downbeat');

    expect(outro).toBeDefined();
    expect(firstDownbeat).toBeDefined();
    expect(
      analysis.barGrid.some((bar) => Math.abs(bar.startSec - (outro?.startSec ?? -1)) < 0.001)
    ).toBe(true);
    expect(
      analysis.barGrid.some(
        (bar) => Math.abs(bar.startSec - (firstDownbeat?.startSec ?? -1)) < 0.001
      )
    ).toBe(true);
  });

  it('scores accented downbeats higher than ambiguous beat-only pulses', () => {
    const track: Track = {
      id: 'downbeat-confidence',
      title: 'Downbeat Confidence',
      durationSec: 96,
      format: 'wav',
      bpm: 120
    };

    const accented = buildTrackAnalysisFromAudioBuffer(
      track,
      buildPulseBuffer({ bpm: 120, durationSec: 96, offsetSec: 0.1, accentEvery: 4 })
    );
    const ambiguous = buildTrackAnalysisFromAudioBuffer(
      { ...track, id: 'ambiguous-downbeat' },
      buildPulseBuffer({ bpm: 120, durationSec: 96, offsetSec: 0.1, accentEvery: 1 })
    );

    const accentedFirstDownbeat = accented.cueCandidates.find((cue) => cue.type === 'first_downbeat');
    const ambiguousFirstDownbeat = ambiguous.cueCandidates.find((cue) => cue.type === 'first_downbeat');

    expect(accented.analysisQuality.beatGrid).toBeGreaterThan(ambiguous.analysisQuality.beatGrid);
    expect(accented.phraseMarkers[0]?.confidence ?? 0).toBeGreaterThan(
      ambiguous.phraseMarkers[0]?.confidence ?? 0
    );
    expect(accentedFirstDownbeat?.confidence ?? 0).toBeGreaterThan(
      ambiguousFirstDownbeat?.confidence ?? 0
    );
  });

  it('keeps steady-loop phrase confidence moderate without section-change evidence', () => {
    const track: Track = {
      id: 'steady-phrase-confidence',
      title: 'Steady Phrase Confidence',
      durationSec: 128,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildPulseBuffer({ bpm: 120, durationSec: 128, offsetSec: 0.1 })
    );
    const maxPhraseConfidence = Math.max(
      0,
      ...analysis.phraseMarkers.map((marker) => marker.confidence)
    );

    expect(analysis.phraseMarkers.length).toBeGreaterThan(4);
    expect(maxPhraseConfidence).toBeLessThan(0.8);
  });

  it('raises phrase confidence at a section-change boundary', () => {
    const track: Track = {
      id: 'section-change-phrase-confidence',
      title: 'Section Change Phrase Confidence',
      durationSec: 128,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildSectionedPulseBuffer({
        bpm: 120,
        durationSec: 128,
        offsetSec: 0.1,
        gainAt: (timeSec, beatIndex) => {
          const accent = beatIndex % 4 === 0 ? 1 : 0.45;
          return timeSec >= 64 ? accent : accent * 0.34;
        }
      })
    );
    const changedPhrase = analysis.phraseMarkers.find(
      (marker) => Math.abs(marker.startSec - 64.1) < 2
    );
    const steadyPhrase = analysis.phraseMarkers.find(
      (marker) => Math.abs(marker.startSec - 32.1) < 2
    );

    expect(changedPhrase).toBeDefined();
    expect(steadyPhrase).toBeDefined();
    expect(changedPhrase?.confidence ?? 0).toBeGreaterThan(0.62);
    expect(changedPhrase?.confidence ?? 0).toBeGreaterThan(
      (steadyPhrase?.confidence ?? 1) + 0.08
    );
  });

  it('keeps outro mix-out cue early enough to leave fade room', () => {
    const track: Track = {
      id: 'late-outro',
      title: 'Late Outro',
      durationSec: 96,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildSectionedPulseBuffer({
        bpm: 120,
        durationSec: 96,
        offsetSec: 0.1,
        gainAt: (timeSec, beatIndex) => {
          const accent = beatIndex % 4 === 0 ? 1 : 0.45;
          return timeSec >= 92 ? accent * 0.08 : accent;
        }
      })
    );
    const outro = analysis.cueCandidates.find((cue) => cue.type === 'outro');

    expect(outro).toBeDefined();
    expect(outro?.startSec ?? 96).toBeLessThanOrEqual(84);
    expect(96 - (outro?.startSec ?? 96)).toBeGreaterThanOrEqual(12);
    expect(
      analysis.barGrid.some((bar) => Math.abs(bar.startSec - (outro?.startSec ?? -1)) < 0.001)
    ).toBe(true);
  });

  it('prefers a phrase-aligned low-energy outro window when available', () => {
    const track: Track = {
      id: 'phrase-outro',
      title: 'Phrase Outro',
      durationSec: 128,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildSectionedPulseBuffer({
        bpm: 120,
        durationSec: 128,
        offsetSec: 0.1,
        gainAt: (timeSec, beatIndex) => {
          const accent = beatIndex % 4 === 0 ? 1 : 0.45;
          if (timeSec >= 80 && timeSec < 96) {
            return accent * 0.18;
          }
          if (timeSec >= 112) {
            return accent * 0.35;
          }
          return accent;
        }
      })
    );
    const outro = analysis.cueCandidates.find((cue) => cue.type === 'outro');

    expect(outro).toBeDefined();
    expect(outro?.startSec ?? 0).toBeGreaterThanOrEqual(76);
    expect(outro?.startSec ?? 128).toBeLessThanOrEqual(97);
    expect(outro?.confidence ?? 0).toBeGreaterThan(0.58);
    expect(
      analysis.barGrid.some(
        (bar) => bar.index % 8 === 0 && Math.abs(bar.startSec - (outro?.startSec ?? -1)) < 0.001
      )
    ).toBe(true);
  });

  it('separates track intro from the first stable downbeat after a long low-energy intro', () => {
    const track: Track = {
      id: 'long-intro',
      title: 'Long Intro',
      durationSec: 96,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildSectionedPulseBuffer({
        bpm: 120,
        durationSec: 96,
        offsetSec: 0.1,
        gainAt: (timeSec, beatIndex) => {
          const accent = beatIndex % 4 === 0 ? 1 : 0.45;
          return timeSec < 24 ? accent * 0.08 : accent;
        }
      })
    );
    const intro = analysis.cueCandidates.find((cue) => cue.type === 'intro');
    const firstDownbeat = analysis.cueCandidates.find((cue) => cue.type === 'first_downbeat');

    expect(intro).toBeDefined();
    expect(firstDownbeat).toBeDefined();
    expect(intro?.startSec ?? 99).toBeLessThan(1);
    expect(firstDownbeat?.startSec ?? 0).toBeGreaterThanOrEqual(22);
    expect(firstDownbeat?.confidence ?? 0).toBeGreaterThan(intro?.confidence ?? 1);
    expect(
      analysis.barGrid.some(
        (bar) => Math.abs(bar.startSec - (firstDownbeat?.startSec ?? -1)) < 0.001
      )
    ).toBe(true);
  });

  it('does not mark flat nonzero energy cues as derived', () => {
    const track: Track = {
      id: 'flat-tone',
      title: 'Flat Tone',
      durationSec: 48,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildConstantToneBuffer({ durationSec: 48 })
    );
    const energyCues = analysis.cueCandidates.filter((cue) =>
      cue.type === 'low_energy_break' || cue.type === 'high_energy_drop' || cue.type === 'outro'
    );

    expect(energyCues.length).toBeGreaterThan(0);
    expect(energyCues.every((cue) => cue.origin === 'heuristic_placeholder')).toBe(true);
  });

  it('does not mark a gradual fade as a derived outro cue', () => {
    const track: Track = {
      id: 'gradual-fade',
      title: 'Gradual Fade',
      durationSec: 96,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildGradualFadePulseBuffer({ bpm: 120, durationSec: 96 })
    );
    const outro = analysis.cueCandidates.find((cue) => cue.type === 'outro');

    expect(outro).toBeDefined();
    expect(outro?.origin).toBe('heuristic_placeholder');
  });

  it('marks a section lift with local attack as a derived high-energy drop', () => {
    const track: Track = {
      id: 'section-lift',
      title: 'Section Lift',
      durationSec: 64,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildSectionedPulseBuffer({
        bpm: 120,
        durationSec: 64,
        offsetSec: 0.1,
        gainAt: (timeSec, beatIndex) => {
          const accent = beatIndex % 4 === 0 ? 1 : 0.45;
          return timeSec < 16 ? accent * 0.18 : accent;
        }
      })
    );
    const drop = analysis.cueCandidates.find((cue) => cue.type === 'high_energy_drop');

    expect(drop).toBeDefined();
    expect(drop?.origin).toBe('derived');
    expect(drop?.startSec ?? 0).toBeGreaterThanOrEqual(14);
    expect(drop?.startSec ?? 99).toBeLessThanOrEqual(18);
  });

  it('prefers high-confidence derived BPM over mismatched metadata BPM', () => {
    const track: Track = {
      id: 'metadata-mismatch',
      title: 'Metadata Mismatch',
      durationSec: 72,
      format: 'wav',
      bpm: 96
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(
      track,
      buildPulseBuffer({ bpm: 128, durationSec: 72 })
    );

    expect(analysis.bpm ?? 0).toBeGreaterThanOrEqual(124);
    expect(analysis.bpm ?? 0).toBeLessThanOrEqual(132);
    expect(analysis.source).toBe('derived');
    expect(analysis.analysisWarnings).toContain('bpm_metadata_mismatch');
  });
});
