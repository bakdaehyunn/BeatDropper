import { Track, TrackLoadResult } from '../../src/shared/types';
import {
  applyTrackLoadResult,
  formatTrackLoadError,
  mergeTracks,
  skippedMessagesToEvents
} from '../../src/renderer/player/trackImportFlow';

const track = (id: string, title: string): Track => ({
  id,
  title,
  durationSec: 120,
  format: 'mp3',
  bpm: null
});

describe('trackImportFlow', () => {
  it('mergeTracks keeps existing order and appends new ids', () => {
    const current = [track('a', 'A'), track('b', 'B')];
    const incoming = [track('b', 'B2'), track('c', 'C')];

    const merged = mergeTracks(current, incoming);
    expect(merged.map((item) => item.id)).toEqual(['a', 'b', 'c']);
    expect(merged[1].title).toBe('B2');
  });

  it('applyTrackLoadResult resets state on replace', () => {
    const state = {
      tracks: [track('a', 'A')],
      selectedIndex: 0,
      currentTrackIndex: 0,
      resolvedBpmByTrack: { a: 128 }
    };
    const result: TrackLoadResult = {
      tracks: [track('x', 'X')],
      skipped: [],
      canceled: false,
      mode: 'replace'
    };

    const next = applyTrackLoadResult(state, result);
    expect(next.tracks.map((item) => item.id)).toEqual(['x']);
    expect(next.selectedIndex).toBe(0);
    expect(next.currentTrackIndex).toBeNull();
    expect(next.resolvedBpmByTrack).toEqual({});
  });

  it('applyTrackLoadResult keeps state unchanged on cancel', () => {
    const state = {
      tracks: [track('a', 'A'), track('b', 'B')],
      selectedIndex: 1,
      currentTrackIndex: 0,
      resolvedBpmByTrack: { a: 121 }
    };
    const result: TrackLoadResult = {
      tracks: [],
      skipped: [],
      canceled: true,
      mode: 'append'
    };

    expect(applyTrackLoadResult(state, result)).toEqual(state);
  });

  it('applyTrackLoadResult merges on append and keeps selected/current ids', () => {
    const state = {
      tracks: [track('a', 'A'), track('b', 'B')],
      selectedIndex: 1,
      currentTrackIndex: 0,
      resolvedBpmByTrack: { a: 123 }
    };
    const result: TrackLoadResult = {
      tracks: [track('a', 'A2'), track('c', 'C')],
      skipped: [],
      canceled: false,
      mode: 'append'
    };

    const next = applyTrackLoadResult(state, result);
    expect(next.tracks.map((item) => item.id)).toEqual(['a', 'b', 'c']);
    expect(next.tracks[0].title).toBe('A2');
    expect(next.selectedIndex).toBe(1);
    expect(next.currentTrackIndex).toBe(0);
    expect(next.resolvedBpmByTrack).toEqual({ a: 123 });
  });

  it('formats load errors and maps skipped messages to events', () => {
    expect(formatTrackLoadError(new Error('permission denied'))).toContain('permission');
    expect(formatTrackLoadError('')).toBe('Unable to load tracks.');
    expect(
      skippedMessagesToEvents(['a: unsupported', 'b: corrupted']).map((item) => item.type)
    ).toEqual(['track_skipped', 'track_skipped']);
  });
});
