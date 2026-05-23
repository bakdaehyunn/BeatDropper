import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { UserPlaylistStore } from '../../src/main/userPlaylistStore';

vi.mock('electron', () => ({
  app: {
    getPath: () => '/tmp'
  }
}));

describe('UserPlaylistStore', () => {
  it('creates, renames, and saves user-curated track order', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-user-playlists-'));
    const store = new UserPlaylistStore(path.join(tempRoot, 'user-playlists.json'));

    try {
      const created = await store.createPlaylist(
        '  Friday   picks  ',
        ['track-1', 'track-2', 'track-1'],
        '2026-05-22T00:00:00.000Z'
      );
      const playlistId = created.playlist?.id ?? '';
      const renamed = await store.renamePlaylist(
        playlistId,
        'Friday picks updated',
        '2026-05-23T00:00:00.000Z'
      );
      const saved = await store.setPlaylistTracks(
        playlistId,
        ['track-3', 'track-2'],
        '2026-05-24T00:00:00.000Z'
      );
      const playlists = await store.readPlaylists();

      expect(created.playlist).toMatchObject({
        name: 'Friday picks',
        trackIds: ['track-1', 'track-2'],
        createdAt: '2026-05-22T00:00:00.000Z',
        updatedAt: '2026-05-22T00:00:00.000Z'
      });
      expect(renamed.playlist).toMatchObject({
        id: playlistId,
        name: 'Friday picks updated',
        updatedAt: '2026-05-23T00:00:00.000Z'
      });
      expect(saved.playlist).toMatchObject({
        id: playlistId,
        trackIds: ['track-3', 'track-2'],
        updatedAt: '2026-05-24T00:00:00.000Z'
      });
      expect(playlists).toHaveLength(1);
      expect(playlists[0]).toMatchObject({
        id: playlistId,
        name: 'Friday picks updated',
        trackIds: ['track-3', 'track-2']
      });
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('adds library tracks without duplicating existing playlist entries', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-user-playlists-'));
    const store = new UserPlaylistStore(path.join(tempRoot, 'user-playlists.json'));

    try {
      const created = await store.createPlaylist(
        'Peak',
        ['a', 'b'],
        '2026-05-22T00:00:00.000Z'
      );
      const playlistId = created.playlist?.id ?? '';
      const result = await store.addTrackIds(
        playlistId,
        ['b', 'c', 'a', 'd'],
        '2026-05-23T00:00:00.000Z'
      );

      expect(result.playlist).toMatchObject({
        id: playlistId,
        trackIds: ['a', 'b', 'c', 'd'],
        updatedAt: '2026-05-23T00:00:00.000Z'
      });
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('deletes playlists and rejects missing playlist updates', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-user-playlists-'));
    const store = new UserPlaylistStore(path.join(tempRoot, 'user-playlists.json'));

    try {
      const created = await store.createPlaylist('After hours', ['x']);
      const playlistId = created.playlist?.id ?? '';
      const deleted = await store.deletePlaylist(playlistId);

      expect(deleted).toMatchObject({
        playlists: [],
        playlist: null
      });
      await expect(store.setPlaylistTracks(playlistId, ['y'])).rejects.toThrow(
        'Playlist not found'
      );
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });
});
