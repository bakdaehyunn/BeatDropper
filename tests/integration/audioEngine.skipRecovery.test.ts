import { AudioEngine } from '../../src/renderer/player/audioEngine';
import { PlayerEvent, Track } from '../../src/shared/types';

class FakeAudioParam {
  cancelScheduledValues(): void {
    return;
  }

  setValueAtTime(): void {
    return;
  }

  linearRampToValueAtTime(): void {
    return;
  }
}

class FakeGainNode {
  gain = new FakeAudioParam();

  connect(): void {
    return;
  }
}

class FakeBufferSourceNode {
  buffer: { duration: number } | null = null;
  onended: (() => void) | null = null;
  playbackRate = new FakeAudioParam();
  readonly startCalls: Array<{ when: number; offset: number }> = [];

  connect(): void {
    return;
  }

  start(when: number, offset = 0): void {
    this.startCalls.push({ when, offset });
  }

  stop(): void {
    return;
  }
}

class FakeAudioContext {
  destination = {};

  private readonly decodePolicy: Map<number, { delayMs: number; durationSec: number }>;
  private readonly nowProvider: () => number;

  constructor(
    nowProvider: () => number,
    decodePolicy: Map<number, { delayMs: number; durationSec: number }>
  ) {
    this.nowProvider = nowProvider;
    this.decodePolicy = decodePolicy;
  }

  get currentTime(): number {
    return this.nowProvider();
  }

  createGain(): FakeGainNode {
    return new FakeGainNode();
  }

  createBufferSource(): FakeBufferSourceNode {
    return new FakeBufferSourceNode();
  }

  decodeAudioData(buffer: ArrayBuffer): Promise<{ duration: number }> {
    const id = new Uint8Array(buffer)[0];
    const policy = this.decodePolicy.get(id);
    if (!policy) {
      return Promise.reject(new Error(`No decode policy for ${id}`));
    }

    if (policy.delayMs <= 0) {
      return Promise.resolve({ duration: policy.durationSec });
    }

    return new Promise((resolve) => {
      setTimeout(() => resolve({ duration: policy.durationSec }), policy.delayMs);
    });
  }

  resume(): Promise<void> {
    return Promise.resolve();
  }

  close(): Promise<void> {
    return Promise.resolve();
  }
}

const flushPromises = async (): Promise<void> => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

const tracks: Track[] = [
  { id: '1', title: 'Track 1', durationSec: 10, format: 'mp3' },
  { id: '2', title: 'Track 2', durationSec: 10, format: 'mp3' },
  { id: '3', title: 'Track 3', durationSec: 10, format: 'mp3' }
];

describe('AudioEngine skip recovery', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2025-01-01T00:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('starts from next playable track when the selected first track is broken', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [2, { delayMs: 0, durationSec: 10 }],
      [3, { delayMs: 0, durationSec: 10 }]
    ]);

    const engine = new AudioEngine({
      readTrackBuffer: async (trackId: string) => new Uint8Array([Number(trackId)]).buffer,
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 2,
        repeatAll: false
      },
      contextFactory: () => new FakeAudioContext(nowProvider, decodePolicy)
    });

    const events: PlayerEvent[] = [];
    engine.onEvent((event) => events.push(event));
    engine.loadTracks(tracks);
    await engine.start(0);
    await flushPromises();

    const skipped = events.find((event) => event.type === 'track_skipped');
    const started = events.find((event) => event.type === 'track_started');

    expect(skipped?.details?.trackId).toBe('1');
    expect(skipped?.details?.stage).toBe('start');
    expect(started?.details?.trackId).toBe('2');
    expect(engine.getCurrentIndex()).toBe(1);

    await engine.destroy();
  });

  it('times out slow decode during transition and continues with the following track', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 5_000, durationSec: 10 }],
      [3, { delayMs: 0, durationSec: 10 }]
    ]);

    const engine = new AudioEngine({
      readTrackBuffer: async (trackId: string) => new Uint8Array([Number(trackId)]).buffer,
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 2,
        repeatAll: false
      },
      contextFactory: () => new FakeAudioContext(nowProvider, decodePolicy)
    });

    const events: PlayerEvent[] = [];
    engine.onEvent((event) => events.push(event));
    engine.loadTracks(tracks);
    await engine.start(0);
    await flushPromises();

    await vi.advanceTimersByTimeAsync(15_000);
    await flushPromises();

    const skipped = events.find(
      (event) => event.type === 'track_skipped' && event.details?.trackId === '2'
    );
    const latestTrackStart = [...events]
      .reverse()
      .find((event) => event.type === 'track_started');

    expect(skipped).toBeDefined();
    expect(['crossfade', 'hard_switch']).toContain(skipped?.details?.stage);
    expect(String(skipped?.details?.reason ?? '')).toContain('Decode timeout');
    expect(latestTrackStart?.details?.trackId).toBe('3');

    await engine.destroy();
  });

  it('keeps waiting for large tracks to avoid premature timeout skips', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 2_600, durationSec: 10 }]
    ]);

    const largeTrackBytes = 12 * 1024 * 1024;
    const engine = new AudioEngine({
      readTrackBuffer: async (trackId: string) => {
        const marker = Number(trackId);
        if (marker === 2) {
          const payload = new Uint8Array(largeTrackBytes);
          payload[0] = marker;
          return payload.buffer;
        }
        return new Uint8Array([marker]).buffer;
      },
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 2,
        repeatAll: false
      },
      contextFactory: () => new FakeAudioContext(nowProvider, decodePolicy)
    });

    const events: PlayerEvent[] = [];
    engine.onEvent((event) => events.push(event));
    engine.loadTracks([
      tracks[0],
      { id: '2', title: 'Track 2 large', durationSec: 10, format: 'mp3' }
    ]);
    await engine.start(0);
    await flushPromises();

    await vi.advanceTimersByTimeAsync(12_000);
    await flushPromises();

    const skippedLargeTrack = events.find(
      (event) => event.type === 'track_skipped' && event.details?.trackId === '2'
    );
    const latestTrackStart = [...events]
      .reverse()
      .find((event) => event.type === 'track_started');

    expect(skippedLargeTrack).toBeUndefined();
    expect(latestTrackStart?.details?.trackId).toBe('2');

    await engine.destroy();
  });
});
