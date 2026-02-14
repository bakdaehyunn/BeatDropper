interface TrackRegistryEntry {
  filePath: string;
  selectedAt: number;
}

interface RegisterTrackInput {
  trackId: string;
  filePath: string;
}

export class TrackRegistry {
  private readonly entries = new Map<string, TrackRegistryEntry>();

  replace(tracks: RegisterTrackInput[]): void {
    this.entries.clear();
    const selectedAt = Date.now();

    for (const track of tracks) {
      this.entries.set(track.trackId, {
        filePath: track.filePath,
        selectedAt
      });
    }
  }

  resolvePath(trackId: unknown): string {
    if (typeof trackId !== 'string' || trackId.trim().length === 0) {
      throw new Error('Invalid track id');
    }

    const entry = this.entries.get(trackId);
    if (!entry) {
      throw new Error('Track is not authorized');
    }

    return entry.filePath;
  }

  get size(): number {
    return this.entries.size;
  }

  getSnapshot(): Map<string, TrackRegistryEntry> {
    return new Map(this.entries);
  }
}
