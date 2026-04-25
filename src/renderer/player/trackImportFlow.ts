import { PlayerEvent, Track, TrackLoadResult } from '../../shared/types';

export interface TrackImportState {
  tracks: Track[];
  selectedIndex: number;
  currentTrackIndex: number | null;
  resolvedBpmByTrack: Record<string, number>;
}

export const mergeTracks = (current: Track[], incoming: Track[]): Track[] => {
  const merged = [...current];
  const indexById = new Map<string, number>();

  for (const [index, track] of merged.entries()) {
    indexById.set(track.id, index);
  }

  for (const track of incoming) {
    const existingIndex = indexById.get(track.id);
    if (typeof existingIndex === 'number') {
      merged[existingIndex] = track;
      continue;
    }

    indexById.set(track.id, merged.length);
    merged.push(track);
  }

  return merged;
};

export const applyTrackLoadResult = (
  state: TrackImportState,
  result: TrackLoadResult
): TrackImportState => {
  if (result.canceled) {
    return state;
  }

  if (result.mode === 'replace') {
    return {
      tracks: result.tracks,
      selectedIndex: 0,
      currentTrackIndex: null,
      resolvedBpmByTrack: {}
    };
  }

  const nextTracks = mergeTracks(state.tracks, result.tracks);
  const selectedTrackId = state.tracks[state.selectedIndex]?.id ?? null;
  const currentTrackId =
    state.currentTrackIndex !== null ? state.tracks[state.currentTrackIndex]?.id ?? null : null;

  const nextSelectedIndex = selectedTrackId
    ? Math.max(0, nextTracks.findIndex((track) => track.id === selectedTrackId))
    : nextTracks.length > 0
      ? 0
      : 0;
  const currentResolvedIndex =
    currentTrackId !== null
      ? nextTracks.findIndex((track) => track.id === currentTrackId)
      : -1;

  return {
    tracks: nextTracks,
    selectedIndex: nextSelectedIndex,
    currentTrackIndex: currentResolvedIndex >= 0 ? currentResolvedIndex : state.currentTrackIndex,
    resolvedBpmByTrack: state.resolvedBpmByTrack
  };
};

export const skippedMessagesToEvents = (messages: string[]): PlayerEvent[] => {
  return messages.map<PlayerEvent>((message) => ({
    type: 'track_skipped',
    at: 0,
    message
  }));
};

export const formatTrackLoadError = (error: unknown): string => {
  const raw = error instanceof Error && error.message ? error.message : String(error ?? '');
  const normalized = raw.trim();
  if (!normalized) {
    return 'Unable to load tracks.';
  }
  if (/permission/i.test(normalized)) {
    return 'Unable to load tracks due to file permission.';
  }
  if (/not authorized/i.test(normalized)) {
    return 'Unable to load tracks due to registry authorization.';
  }
  return `Unable to load tracks: ${normalized}`;
};
