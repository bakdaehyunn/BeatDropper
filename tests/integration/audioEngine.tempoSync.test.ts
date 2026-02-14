import { AudioEngine } from '../../src/renderer/player/audioEngine';
import { PlayerEvent, Track } from '../../src/shared/types';

class FakeAudioParam {
  readonly setCalls: Array<{ value: number; at: number }> = [];
  readonly rampCalls: Array<{ value: number; at: number }> = [];

  cancelScheduledValues(): void {
    return;
  }

  setValueAtTime(value: number, at: number): void {
    this.setCalls.push({ value, at });
  }

  linearRampToValueAtTime(value: number, at: number): void {
    this.rampCalls.push({ value, at });
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
  readonly sources: FakeBufferSourceNode[] = [];

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
    const source = new FakeBufferSourceNode();
    this.sources.push(source);
    return source;
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

const buildTracks = (firstBpm: number, secondBpm: number): Track[] => [
  {
    id: '1',
    title: 'Track 1',
    durationSec: 10,
    format: 'mp3',
    bpm: firstBpm
  },
  {
    id: '2',
    title: 'Track 2',
    durationSec: 10,
    format: 'mp3',
    bpm: secondBpm
  }
];

describe('AudioEngine tempo sync transitions', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2025-01-01T00:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('applies tempo sync and playbackRate automation on compatible bpm', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 0, durationSec: 10 }]
    ]);

    let contextRef: FakeAudioContext | null = null;
    const contextFactory = (): FakeAudioContext => {
      contextRef = new FakeAudioContext(nowProvider, decodePolicy);
      return contextRef;
    };

    const events: PlayerEvent[] = [];
    const engine = new AudioEngine({
      readTrackBuffer: async (trackId: string) => {
        const marker = trackId === '2' ? 2 : 1;
        return new Uint8Array([marker]).buffer;
      },
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 2,
        repeatAll: false
      },
      contextFactory
    });

    engine.onEvent((event) => events.push(event));
    engine.loadTracks(buildTracks(124, 128));
    await engine.start(0);
    await flushPromises();

    vi.advanceTimersByTime(2_600);
    await flushPromises();

    const appliedIndex = events.findIndex((event) => event.type === 'tempo_sync_applied');
    const transitionIndex = events.findIndex(
      (event) => event.type === 'transition_started'
    );
    expect(appliedIndex).toBeGreaterThanOrEqual(0);
    expect(transitionIndex).toBeGreaterThan(appliedIndex);

    const secondSource = contextRef?.sources[1];
    expect(secondSource).toBeDefined();
    expect(secondSource?.playbackRate.setCalls.length ?? 0).toBeGreaterThanOrEqual(2);
    expect(secondSource?.playbackRate.rampCalls[0]?.value).toBe(1);

    await engine.destroy();
  });

  it('skips tempo sync when bpm mismatch is too large', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 0, durationSec: 10 }]
    ]);

    let contextRef: FakeAudioContext | null = null;
    const contextFactory = (): FakeAudioContext => {
      contextRef = new FakeAudioContext(nowProvider, decodePolicy);
      return contextRef;
    };

    const events: PlayerEvent[] = [];
    const engine = new AudioEngine({
      readTrackBuffer: async (trackId: string) => {
        const marker = trackId === '2' ? 2 : 1;
        return new Uint8Array([marker]).buffer;
      },
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 2,
        repeatAll: false
      },
      contextFactory
    });

    engine.onEvent((event) => events.push(event));
    engine.loadTracks(buildTracks(100, 140));
    await engine.start(0);
    await flushPromises();

    vi.advanceTimersByTime(2_600);
    await flushPromises();

    const skipped = events.find((event) => event.type === 'tempo_sync_skipped');
    expect(skipped).toBeDefined();
    expect(skipped?.details?.reason).toBe('residual_too_high');
    expect(events.some((event) => event.type === 'transition_started')).toBe(true);
    expect(contextRef?.sources[1]?.playbackRate.setCalls.length ?? 0).toBe(0);

    await engine.destroy();
  });

  it('applies tempo sync after delayed decode fallback path', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 4_000, durationSec: 10 }]
    ]);

    const contextFactory = (): FakeAudioContext =>
      new FakeAudioContext(nowProvider, decodePolicy);

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

    engine.onEvent((event) => events.push(event));
    engine.loadTracks(buildTracks(124, 128));
    await engine.start(0);
    await flushPromises();

    vi.advanceTimersByTime(2_300);
    await flushPromises();

    vi.advanceTimersByTime(5_000);
    await flushPromises();

    const delayedIndex = events.findIndex((event) => event.type === 'decode_delayed');
    const appliedIndex = events.findIndex((event) => event.type === 'tempo_sync_applied');
    const transitionIndex = events.findIndex(
      (event) => event.type === 'transition_started'
    );

    expect(delayedIndex).toBeGreaterThanOrEqual(0);
    expect(appliedIndex).toBeGreaterThan(delayedIndex);
    expect(transitionIndex).toBeGreaterThan(appliedIndex);

    await engine.destroy();
  });
});
