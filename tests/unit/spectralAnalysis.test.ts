import { buildSpectralBandsFromAudioBuffer } from '../../src/renderer/player/spectralAnalysis';

class TestAudioBuffer {
  readonly duration: number;
  readonly numberOfChannels = 1;
  private readonly data: Float32Array;

  constructor(
    data: Float32Array,
    readonly sampleRate: number
  ) {
    this.data = data;
    this.duration = data.length / sampleRate;
  }

  getChannelData(): Float32Array {
    return this.data;
  }
}

const buildSineBuffer = (frequencyHz: number, durationSec = 2, sampleRate = 22050) => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  for (let index = 0; index < length; index += 1) {
    const timeSec = index / sampleRate;
    data[index] = 0.7 * Math.sin(timeSec * Math.PI * 2 * frequencyHz);
  }
  return new TestAudioBuffer(data, sampleRate);
};

const averageBand = (
  points: ReturnType<typeof buildSpectralBandsFromAudioBuffer>,
  band: 'low' | 'mid' | 'high'
) => points.reduce((sum, point) => sum + point[band], 0) / Math.max(1, points.length);

describe('buildSpectralBandsFromAudioBuffer', () => {
  it('separates low-frequency and high-frequency energy with FFT band power', () => {
    const low = buildSpectralBandsFromAudioBuffer(buildSineBuffer(110), {
      bucketCount: 8,
      fftSize: 1024
    });
    const high = buildSpectralBandsFromAudioBuffer(buildSineBuffer(7000), {
      bucketCount: 8,
      fftSize: 1024
    });

    expect(averageBand(low, 'low')).toBeGreaterThan(averageBand(low, 'high') * 4);
    expect(averageBand(high, 'high')).toBeGreaterThan(averageBand(high, 'low') * 4);
  });

  it('returns the requested bucket count using normalized band values', () => {
    const points = buildSpectralBandsFromAudioBuffer(buildSineBuffer(1000), {
      bucketCount: 12,
      fftSize: 1024
    });

    expect(points).toHaveLength(12);
    expect(points.every((point) => point.low >= 0 && point.low <= 1)).toBe(true);
    expect(points.every((point) => point.mid >= 0 && point.mid <= 1)).toBe(true);
    expect(points.every((point) => point.high >= 0 && point.high <= 1)).toBe(true);
  });
});
