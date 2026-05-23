import { MusicLibraryTrack } from '../../shared/types';

export const ALL_LIBRARY_SOURCES = 'all';

export interface MusicLibrarySourceSummary {
  sourcePath: string;
  sourceLabel: string;
  count: number;
}

export interface MusicLibraryFilterInput {
  query: string;
  sourcePath: string;
}

const normalize = (value: string): string => value.trim().toLowerCase();

export const buildMusicLibrarySourceSummaries = (
  tracks: MusicLibraryTrack[]
): MusicLibrarySourceSummary[] => {
  const bySource = new Map<string, MusicLibrarySourceSummary>();

  for (const track of tracks) {
    const existing = bySource.get(track.sourcePath);
    if (existing) {
      existing.count += 1;
      continue;
    }
    bySource.set(track.sourcePath, {
      sourcePath: track.sourcePath,
      sourceLabel: track.sourceLabel,
      count: 1
    });
  }

  return Array.from(bySource.values()).sort((left, right) =>
    left.sourceLabel.localeCompare(right.sourceLabel) || left.sourcePath.localeCompare(right.sourcePath)
  );
};

export const filterMusicLibraryTracks = (
  tracks: MusicLibraryTrack[],
  input: MusicLibraryFilterInput
): MusicLibraryTrack[] => {
  const queryTerms = normalize(input.query).split(/\s+/).filter(Boolean);
  const hasSourceFilter =
    input.sourcePath.trim().length > 0 && input.sourcePath !== ALL_LIBRARY_SOURCES;

  return tracks.filter((track) => {
    if (hasSourceFilter && track.sourcePath !== input.sourcePath) {
      return false;
    }

    if (queryTerms.length === 0) {
      return true;
    }

    const haystack = normalize(
      [
        track.title,
        track.sourceLabel,
        track.sourcePath,
        track.format,
        typeof track.bpm === 'number' && Number.isFinite(track.bpm)
          ? String(Math.round(track.bpm))
          : ''
      ].join(' ')
    );

    return queryTerms.every((term) => haystack.includes(term));
  });
};
