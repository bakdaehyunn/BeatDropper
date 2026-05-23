import { mkdtemp, rm, unlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { MusicLibraryStore } from '../../src/main/musicLibraryStore';

vi.mock('electron', () => ({
  app: {
    getPath: () => '/tmp'
  }
}));

const loadedTrack = (id: string, title: string, filePath: string) => ({
  filePath,
  track: {
    id,
    title,
    durationSec: 180,
    format: 'mp3' as const,
    bpm: 124
  }
});

describe('MusicLibraryStore', () => {
  it('persists library tracks and preserves original addedAt on update', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-library-store-'));
    const store = new MusicLibraryStore(path.join(tempRoot, 'music-library.json'));

    try {
      const first = await store.upsertLoadedTracks(
        [loadedTrack('track-1', 'Track One', '/music/a/one.mp3')],
        '/music/a',
        '2026-05-22T00:00:00.000Z'
      );
      const second = await store.upsertLoadedTracks(
        [loadedTrack('track-1', 'Track One Updated', '/music/a/one.mp3')],
        '/music/a',
        '2026-05-23T00:00:00.000Z'
      );
      const tracks = await store.readTracks();
      const entries = await store.getEntriesByIds(['track-1']);

      expect(first).toMatchObject({ added: 1, updated: 0 });
      expect(second).toMatchObject({ added: 0, updated: 1 });
      expect(tracks).toHaveLength(1);
      expect(tracks[0]).toMatchObject({
        id: 'track-1',
        title: 'Track One Updated',
        addedAt: '2026-05-22T00:00:00.000Z',
        updatedAt: '2026-05-23T00:00:00.000Z',
        sourceLabel: 'a',
        missing: false,
        missingAt: null
      });
      expect(entries[0]?.filePath).toBe('/music/a/one.mp3');
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('returns playlist register entries in requested order', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-library-store-'));
    const store = new MusicLibraryStore(path.join(tempRoot, 'music-library.json'));

    try {
      await store.upsertLoadedTracks(
        [
          loadedTrack('a', 'A', '/music/a.mp3'),
          loadedTrack('b', 'B', '/music/b.mp3')
        ],
        '/music',
        '2026-05-22T00:00:00.000Z'
      );

      const entries = await store.getEntriesByIds(['b', 'missing', 'a']);
      const registerEntries = store.toRegisterEntries(entries);

      expect(registerEntries.map((entry) => entry.trackId)).toEqual(['b', 'a']);
      expect(registerEntries.map((entry) => entry.filePath)).toEqual([
        '/music/b.mp3',
        '/music/a.mp3'
      ]);
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('preserves an existing library id when the importer id changes for the same file path', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-library-store-'));
    const store = new MusicLibraryStore(path.join(tempRoot, 'music-library.json'));
    const audioPath = path.join(tempRoot, 'one.mp3');

    try {
      const first = await store.upsertLoadedTracks(
        [loadedTrack('legacy-id', 'Track One', audioPath)],
        tempRoot,
        '2026-05-22T00:00:00.000Z'
      );
      const second = await store.upsertLoadedTracks(
        [loadedTrack('stable-path-id', 'Track One Updated', audioPath)],
        tempRoot,
        '2026-05-23T00:00:00.000Z'
      );
      const tracks = await store.readTracks();
      const legacyEntries = await store.getEntriesByIds(['legacy-id']);
      const newEntries = await store.getEntriesByIds(['stable-path-id']);

      expect(first).toMatchObject({ added: 1, updated: 0 });
      expect(second).toMatchObject({ added: 0, updated: 1 });
      expect(tracks).toHaveLength(1);
      expect(tracks[0]).toMatchObject({
        id: 'legacy-id',
        title: 'Track One Updated',
        updatedAt: '2026-05-23T00:00:00.000Z'
      });
      expect(legacyEntries).toHaveLength(1);
      expect(newEntries).toEqual([]);
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('deduplicates legacy and path-stable ids for the same file path during rescan', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-library-store-'));
    const storePath = path.join(tempRoot, 'music-library.json');
    const store = new MusicLibraryStore(storePath);
    const audioPath = path.join(tempRoot, 'one.mp3');

    try {
      await writeFile(
        storePath,
        JSON.stringify(
          {
            schemaVersion: 1,
            tracks: [
              {
                ...loadedTrack('legacy-id', 'Legacy Track', audioPath).track,
                addedAt: '2026-05-21T00:00:00.000Z',
                updatedAt: '2026-05-21T00:00:00.000Z',
                sourcePath: tempRoot,
                sourceLabel: path.basename(tempRoot),
                missing: false,
                missingAt: null,
                filePath: audioPath
              },
              {
                ...loadedTrack('stable-path-id', 'Duplicate Track', audioPath).track,
                addedAt: '2026-05-22T00:00:00.000Z',
                updatedAt: '2026-05-22T00:00:00.000Z',
                sourcePath: tempRoot,
                sourceLabel: path.basename(tempRoot),
                missing: false,
                missingAt: null,
                filePath: audioPath
              }
            ]
          },
          null,
          2
        ),
        'utf8'
      );

      const result = await store.rescanSource(
        [loadedTrack('stable-path-id', 'Fresh Metadata', audioPath)],
        tempRoot,
        [audioPath],
        '2026-05-23T00:00:00.000Z'
      );

      expect(result).toMatchObject({
        added: 0,
        updated: 1,
        missing: 0
      });
      expect(result.tracks).toHaveLength(1);
      expect(result.tracks[0]).toMatchObject({
        id: 'legacy-id',
        title: 'Fresh Metadata',
        updatedAt: '2026-05-23T00:00:00.000Z'
      });
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('marks deleted files missing and restores them when they reappear', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-library-store-'));
    const store = new MusicLibraryStore(path.join(tempRoot, 'music-library.json'));
    const audioPath = path.join(tempRoot, 'one.mp3');

    try {
      await writeFile(audioPath, 'audio');
      await store.upsertLoadedTracks(
        [loadedTrack('track-1', 'Track One', audioPath)],
        tempRoot,
        '2026-05-22T00:00:00.000Z'
      );

      await unlink(audioPath);
      const missing = await store.refreshAvailability('2026-05-23T00:00:00.000Z');

      expect(missing.missing).toBe(1);
      expect(missing.tracks[0]).toMatchObject({
        id: 'track-1',
        missing: true,
        missingAt: '2026-05-23T00:00:00.000Z'
      });

      await writeFile(audioPath, 'audio');
      const restored = await store.refreshAvailability('2026-05-24T00:00:00.000Z');

      expect(restored.restored).toBe(1);
      expect(restored.tracks[0]).toMatchObject({
        id: 'track-1',
        missing: false,
        missingAt: null
      });
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('rescans a source folder by adding new tracks and marking removed files missing', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-library-store-'));
    const store = new MusicLibraryStore(path.join(tempRoot, 'music-library.json'));
    const removedPath = path.join(tempRoot, 'removed.mp3');
    const keptPath = path.join(tempRoot, 'kept.mp3');
    const addedPath = path.join(tempRoot, 'added.mp3');

    try {
      await store.upsertLoadedTracks(
        [
          loadedTrack('removed', 'Removed', removedPath),
          loadedTrack('kept', 'Kept', keptPath)
        ],
        tempRoot,
        '2026-05-22T00:00:00.000Z'
      );

      const result = await store.rescanSource(
        [
          loadedTrack('kept', 'Kept', keptPath),
          loadedTrack('added', 'Added', addedPath)
        ],
        tempRoot,
        [keptPath, addedPath],
        '2026-05-23T00:00:00.000Z'
      );

      expect(result).toMatchObject({
        added: 1,
        updated: 1,
        missing: 1
      });
      expect(result.tracks.find((track) => track.id === 'removed')).toMatchObject({
        missing: true,
        missingAt: '2026-05-23T00:00:00.000Z'
      });
      expect(result.tracks.find((track) => track.id === 'added')).toMatchObject({
        missing: false,
        missingAt: null
      });
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });
});
