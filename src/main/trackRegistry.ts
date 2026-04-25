interface TrackRegistryEntry {
  filePath: string;
  selectedAt: number;
}

interface RegisterTrackInput {
  trackId: string;
  filePath: string;
}

const TRACK_AUTH_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_TRACK_REGISTRY_ENTRIES = 2000;

export class TrackRegistry {
  private readonly entries = new Map<string, TrackRegistryEntry>();
  private readonly nowProvider: () => number;

  constructor(nowProvider: () => number = () => Date.now()) {
    this.nowProvider = nowProvider;
  }

  replace(tracks: RegisterTrackInput[]): void {
    this.entries.clear();
    const selectedAt = this.nowProvider();

    for (const track of tracks) {
      this.entries.set(track.trackId, {
        filePath: track.filePath,
        selectedAt
      });
    }

    this.pruneOverflow();
  }

  append(tracks: RegisterTrackInput[]): void {
    const selectedAt = this.nowProvider();
    this.sweepExpired(selectedAt);

    for (const track of tracks) {
      this.entries.set(track.trackId, {
        filePath: track.filePath,
        selectedAt
      });
    }

    this.pruneOverflow();
  }

  resolvePath(trackId: unknown): string {
    if (typeof trackId !== 'string' || trackId.trim().length === 0) {
      throw new Error('Invalid track id');
    }

    const now = this.nowProvider();
    this.sweepExpired(now);
    const entry = this.entries.get(trackId);
    if (!entry) {
      throw new Error('Track is not authorized');
    }

    entry.selectedAt = now;
    this.entries.set(trackId, entry);
    return entry.filePath;
  }

  get size(): number {
    return this.entries.size;
  }

  getSnapshot(): Map<string, TrackRegistryEntry> {
    return new Map(this.entries);
  }

  private sweepExpired(now: number): void {
    for (const [trackId, entry] of this.entries) {
      if (now - entry.selectedAt > TRACK_AUTH_TTL_MS) {
        this.entries.delete(trackId);
      }
    }
  }

  private pruneOverflow(): void {
    if (this.entries.size <= MAX_TRACK_REGISTRY_ENTRIES) {
      return;
    }

    const overflow = this.entries.size - MAX_TRACK_REGISTRY_ENTRIES;
    const sorted = Array.from(this.entries.entries()).sort(
      (left, right) => left[1].selectedAt - right[1].selectedAt
    );

    for (let index = 0; index < overflow; index += 1) {
      const victim = sorted[index];
      if (!victim) {
        break;
      }
      this.entries.delete(victim[0]);
    }
  }
}
