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

  connect(): void {
    return;
  }

  start(): void {
    return;
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
      setTimeout(() => {
        resolve({ duration: policy.durationSec });
      }, policy.delayMs);
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
};

describe('AudioEngine decode fallback', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2025-01-01T00:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('emits decode_delayed and then transitions when decode is late', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 4_000, durationSec: 10 }]
    ]);

    const contextFactory = (): FakeAudioContext =>
      new FakeAudioContext(nowProvider, decodePolicy);

    const tracks: Track[] = [
      {
        id: '1',
        title: 'Track 1',
        durationSec: 10,
        format: 'mp3'
      },
      {
        id: '2',
        title: 'Track 2',
        durationSec: 10,
        format: 'mp3'
      }
    ];

    const events: PlayerEvent[] = [];
    const engine = new AudioEngine({
      readTrackBuffer: async (trackId: string) => {
        const marker = trackId === '2' ? 2 : 1;
        return new Uint8Array([marker]).buffer;
      },
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 0,
        repeatAll: false
      },
      contextFactory
    });

    const unsubscribe = engine.onEvent((event) => events.push(event));
    engine.loadTracks(tracks);
    await engine.start(0);
    await flushPromises();

    vi.advanceTimersByTime(2_300);
    await flushPromises();

    vi.advanceTimersByTime(5_000);
    await flushPromises();

    const delayedIndex = events.findIndex((event) => event.type === 'decode_delayed');
    const transitionIndex = events.findIndex(
      (event) => event.type === 'transition_started'
    );

    expect(delayedIndex).toBeGreaterThanOrEqual(0);
    expect(transitionIndex).toBeGreaterThan(delayedIndex);

    unsubscribe();
    await engine.destroy();
  });
});
