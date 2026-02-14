import { AudioBufferForBpm, estimateTrackBpm } from '../../src/renderer/player/bpmEstimator';

class TestAudioBuffer implements AudioBufferForBpm {
  readonly duration: number;
  readonly sampleRate: number;
  readonly numberOfChannels: number;
  private readonly channels: Float32Array[];

  constructor(channels: Float32Array[], sampleRate: number) {
    this.channels = channels;
    this.sampleRate = sampleRate;
    this.numberOfChannels = channels.length;
    this.duration = channels[0].length / sampleRate;
  }

  getChannelData(channel: number): Float32Array {
    return this.channels[channel];
  }
}

const buildPulseBuffer = (
  bpm: number,
  durationSec: number,
  sampleRate = 22050
): TestAudioBuffer => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  const beatInterval = (60 / bpm) * sampleRate;
  const pulseLength = Math.floor(sampleRate * 0.015);

  for (let beat = 0; beat < length; beat += beatInterval) {
    const start = Math.floor(beat);
    for (let offset = 0; offset < pulseLength; offset += 1) {
      const index = start + offset;
      if (index >= length) {
        break;
      }
      data[index] += Math.exp(-offset / 35);
    }
  }

  return new TestAudioBuffer([data], sampleRate);
};

const buildNoiseBuffer = (durationSec: number, sampleRate = 22050): TestAudioBuffer => {
  const length = Math.floor(durationSec * sampleRate);
  const data = new Float32Array(length);
  let seed = 1234567;

  for (let index = 0; index < length; index += 1) {
    seed = (seed * 1664525 + 1013904223) % 0x100000000;
    data[index] = ((seed / 0x100000000) * 2 - 1) * 0.2;
  }

  return new TestAudioBuffer([data], sampleRate);
};

describe('estimateTrackBpm', () => {
  it('estimates bpm from synthetic pulse signal', () => {
    const buffer = buildPulseBuffer(120, 30);
    const result = estimateTrackBpm(buffer);

    expect(result.bpm).not.toBeNull();
    expect(result.bpm ?? 0).toBeGreaterThanOrEqual(116);
    expect(result.bpm ?? 0).toBeLessThanOrEqual(124);
  });

  it('returns null for random noise', () => {
    const buffer = buildNoiseBuffer(30);
    const result = estimateTrackBpm(buffer);

    expect(result.bpm).toBeNull();
  });

  it('returns null for silence', () => {
    const silence = new Float32Array(22050 * 12);
    const buffer = new TestAudioBuffer([silence], 22050);
    const result = estimateTrackBpm(buffer);

    expect(result.bpm).toBeNull();
  });
});
