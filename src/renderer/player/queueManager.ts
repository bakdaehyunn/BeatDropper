import { Track } from '../../shared/types';

export class QueueManager {
  private tracks: Track[] = [];
  private repeatAll: boolean;

  constructor(tracks: Track[] = [], repeatAll = true) {
    this.tracks = [...tracks];
    this.repeatAll = repeatAll;
  }

  setTracks(tracks: Track[]): void {
    this.tracks = [...tracks];
  }

  getTracks(): Track[] {
    return [...this.tracks];
  }

  setRepeatAll(next: boolean): void {
    this.repeatAll = next;
  }

  getCurrent(index: number): Track | null {
    return this.tracks[index] ?? null;
  }

  getNextIndex(currentIndex: number): number | null {
    if (this.tracks.length === 0) {
      return null;
    }

    const next = currentIndex + 1;
    if (next < this.tracks.length) {
      return next;
    }

    return this.repeatAll ? 0 : null;
  }

  getPreviousIndex(currentIndex: number): number | null {
    if (this.tracks.length === 0) {
      return null;
    }

    const previous = currentIndex - 1;
    if (previous >= 0) {
      return previous;
    }

    return this.repeatAll ? this.tracks.length - 1 : null;
  }

  advance(currentIndex: number): number | null {
    return this.getNextIndex(currentIndex);
  }
}
