import { DEFAULT_SETTINGS } from '../../src/shared/settings';
import { TransitionScheduler } from '../../src/renderer/player/transitionScheduler';

describe('TransitionScheduler', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2025-01-01T00:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('fires predecode -> crossfade -> track end in order', () => {
    const scheduler = new TransitionScheduler(() => Date.now() / 1000);
    const now = Date.now() / 1000;
    const order: string[] = [];

    scheduler.scheduleTransition({
      currentEndAt: now + 20,
      plan: {
        crossfadeStartAt: now + 12,
        crossfadeEndAt: now + 20
      },
      settings: {
        ...DEFAULT_SETTINGS,
        predecodeLeadSec: 4
      },
      callbacks: {
        onPredecode: () => order.push('predecode'),
        onCrossfade: () => order.push('crossfade'),
        onTrackEnd: () => order.push('end')
      }
    });

    vi.advanceTimersByTime(21_000);
    expect(order).toEqual(['predecode', 'crossfade', 'end']);
  });

  it('keeps transition callback order across 3 chained tracks', () => {
    const scheduler = new TransitionScheduler(() => Date.now() / 1000);
    const now = Date.now() / 1000;
    const order: string[] = [];
    const settings = {
      ...DEFAULT_SETTINGS,
      predecodeLeadSec: 3
    };

    const scheduleTrack = (label: string, startAt: number): void => {
      const endAt = startAt + 10;
      scheduler.scheduleTransition({
        currentEndAt: endAt,
        plan: {
          crossfadeStartAt: endAt - 2,
          crossfadeEndAt: endAt
        },
        settings,
        callbacks: {
          onPredecode: () => order.push(`${label}:predecode`),
          onCrossfade: () => {
            order.push(`${label}:crossfade`);
            if (label === 'track1') {
              scheduleTrack('track2', endAt - 2);
            } else if (label === 'track2') {
              scheduleTrack('track3', endAt - 2);
            }
          },
          onTrackEnd: () => order.push(`${label}:end`)
        }
      });
    };

    scheduleTrack('track1', now);
    vi.advanceTimersByTime(40_000);

    expect(order).toEqual([
      'track1:predecode',
      'track1:crossfade',
      'track2:predecode',
      'track2:crossfade',
      'track3:predecode',
      'track3:crossfade',
      'track3:end'
    ]);
  });
});
