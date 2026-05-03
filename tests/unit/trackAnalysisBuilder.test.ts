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
