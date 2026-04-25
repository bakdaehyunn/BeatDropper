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
  await Promise.resolve();
  await Promise.resolve();
};

const tracks: Track[] = [
  {
    id: '1',
    title: 'Track 1',
    durationSec: 10,
    format: 'mp3',
    bpm: 124
  },
  {
    id: '2',
    title: 'Track 2',
    durationSec: 24,
    format: 'mp3',
    bpm: 128
  }
];

describe('AudioEngine mix plan execution', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2025-01-01T00:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('applies planner timing, next-track offset, and fixed tempo sync', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 0, durationSec: 24 }]
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
      requestMixPlan: async () => ({
        source: 'cli',
        reason: null,
        request: {} as never,
        response: null,
        analysis: {
          current: null,
          next: null
        },
        plan: {
          transitionStartSec: 4,
          transitionEndSec: 7,
          nextTrackStartOffsetSec: 12,
          style: 'smooth_blend',
          confidence: 0.9,
          reasoningSummary: 'Bring in the chorus late',
          tempoSync: {
            enabled: true,
            targetRate: 0.97
          }
        }
      }),
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 2,
        repeatAll: false
      },
      contextFactory
    });

    engine.onEvent((event) => events.push(event));
    engine.loadTracks(tracks);
    await engine.start(0);
    await flushPromises();

    await vi.advanceTimersByTimeAsync(7_500);
    await flushPromises();

    const applied = events.find((event) => event.type === 'mix_plan_applied');
    const transitionStarted = events.find((event) => event.type === 'transition_started');
    const secondSource = contextRef?.sources[1];

    expect(applied).toBeDefined();
    expect(transitionStarted?.details?.source).toBe('ai');
    expect(transitionStarted?.details?.nextTrackStartOffsetSec).toBe(12);
    expect(secondSource?.startCalls[0]?.offset).toBe(12);
    expect(secondSource?.playbackRate.setCalls[0]?.value).toBeCloseTo(0.97, 5);

    await engine.destroy();
  });

  it('keeps the rule-based transition when planner returns no valid plan', async () => {
    const baseMs = Date.now();
    const nowProvider = (): number => (Date.now() - baseMs) / 1000;
    const decodePolicy = new Map<number, { delayMs: number; durationSec: number }>([
      [1, { delayMs: 0, durationSec: 10 }],
      [2, { delayMs: 0, durationSec: 24 }]
    ]);

    const events: PlayerEvent[] = [];
    const engine = new AudioEngine({
      readTrackBuffer: async (trackId: string) => {
        const marker = trackId === '2' ? 2 : 1;
        return new Uint8Array([marker]).buffer;
      },
      requestMixPlan: async () => ({
        source: 'fallback',
        reason: 'planner_command_missing',
        request: {} as never,
        response: null,
        analysis: {
          current: null,
          next: null
        },
        plan: null
      }),
      settings: {
        fadeDurationSec: 8,
        masterGain: 1,
        predecodeLeadSec: 2,
        repeatAll: false
      },
      contextFactory: () => new FakeAudioContext(nowProvider, decodePolicy)
    });

    engine.onEvent((event) => events.push(event));
    engine.loadTracks(tracks);
    await engine.start(0);
    await flushPromises();

    await vi.advanceTimersByTimeAsync(2_600);
    await flushPromises();

    const fallback = events.find((event) => event.type === 'mix_plan_fallback');
    const transitionStarted = events.find((event) => event.type === 'transition_started');

    expect(fallback?.details?.reason).toBe('planner_command_missing');
    expect(transitionStarted?.details?.source).toBe('rule_based');

    await engine.destroy();
  });
});
