import { QueueManager } from '../../src/renderer/player/queueManager';
import { Track } from '../../src/shared/types';

const createTrack = (index: number): Track => ({
  id: `track-${index}`,
  title: `Track ${index}`,
  durationSec: 180,
  format: 'mp3'
});

describe('QueueManager', () => {
  it('returns next index in sequential order', () => {
    const manager = new QueueManager([createTrack(1), createTrack(2), createTrack(3)]);

    expect(manager.getNextIndex(0)).toBe(1);
    expect(manager.getNextIndex(1)).toBe(2);
  });

  it('wraps to start when repeatAll is true', () => {
    const manager = new QueueManager([createTrack(1), createTrack(2)], true);
    expect(manager.getNextIndex(1)).toBe(0);
  });

  it('stops at end when repeatAll is false', () => {
    const manager = new QueueManager([createTrack(1), createTrack(2)], false);
    expect(manager.getNextIndex(1)).toBeNull();
  });

  it('returns previous index and wraps when repeatAll is true', () => {
    const manager = new QueueManager([createTrack(1), createTrack(2), createTrack(3)], true);
    expect(manager.getPreviousIndex(2)).toBe(1);
    expect(manager.getPreviousIndex(0)).toBe(2);
  });

  it('returns null previous at start when repeatAll is false', () => {
    const manager = new QueueManager([createTrack(1), createTrack(2)], false);
    expect(manager.getPreviousIndex(0)).toBeNull();
  });
});
