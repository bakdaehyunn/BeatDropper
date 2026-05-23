import {
  ALL_LIBRARY_SOURCES,
  buildMusicLibrarySourceSummaries,
  filterMusicLibraryTracks
} from '../../src/renderer/player/musicLibraryFilter';
import { MusicLibraryTrack } from '../../src/shared/types';

const track = (
  id: string,
  title: string,
  sourcePath: string,
  sourceLabel: string,
  bpm: number | null = null
): MusicLibraryTrack => ({
  id,
  title,
  durationSec: 180,
  format: 'mp3',
  bpm,
  addedAt: '2026-05-22T00:00:00.000Z',
  updatedAt: '2026-05-22T00:00:00.000Z',
  sourcePath,
  sourceLabel,
  missing: false,
  missingAt: null
});

describe('musicLibraryFilter', () => {
  it('summarizes sources with track counts', () => {
    const summaries = buildMusicLibrarySourceSummaries([
      track('a', 'A', '/music/peak', 'Peak'),
      track('b', 'B', '/music/warmup', 'Warmup'),
      track('c', 'C', '/music/peak', 'Peak')
    ]);

    expect(summaries).toEqual([
      { sourcePath: '/music/peak', sourceLabel: 'Peak', count: 2 },
      { sourcePath: '/music/warmup', sourceLabel: 'Warmup', count: 1 }
    ]);
  });

  it('filters by source folder and multi-term search query', () => {
    const tracks = [
      track('a', 'Late Night House', '/music/peak', 'Peak', 124),
      track('b', 'Warmup Groove', '/music/warmup', 'Warmup', 118),
      track('c', 'Peak Techno Tool', '/music/peak', 'Peak', 132)
    ];

    expect(
      filterMusicLibraryTracks(tracks, {
        sourcePath: '/music/peak',
        query: 'peak 132'
      }).map((item) => item.id)
    ).toEqual(['c']);
  });

  it('keeps all sources when the all source filter is selected', () => {
    const tracks = [
      track('a', 'Late Night House', '/music/peak', 'Peak', 124),
      track('b', 'Warmup Groove', '/music/warmup', 'Warmup', 118)
    ];

    expect(
      filterMusicLibraryTracks(tracks, {
        sourcePath: ALL_LIBRARY_SOURCES,
        query: 'mp3'
      }).map((item) => item.id)
    ).toEqual(['a', 'b']);
  });
});
