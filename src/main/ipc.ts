import { dialog, ipcMain } from 'electron';
import { readFile } from 'node:fs/promises';
import { PlayerSettings } from '../shared/types';
import { readSettings, writeSettings } from './settingsStore';
import { loadTracksFromPaths } from './trackLibrary';
import { TrackRegistry } from './trackRegistry';

const trackRegistry = new TrackRegistry();

export const registerIpcHandlers = (): void => {
  ipcMain.handle('library:openTracks', async () => {
    const result = await dialog.showOpenDialog({
      title: 'Select audio tracks',
      properties: ['openFile', 'multiSelections'],
      filters: [
        {
          name: 'Audio',
          extensions: ['mp3', 'wav']
        }
      ]
    });

    if (result.canceled) {
      trackRegistry.replace([]);
      return { tracks: [], skipped: [] };
    }

    const loaded = await loadTracksFromPaths(result.filePaths);
    trackRegistry.replace(
      loaded.tracks.map((entry) => ({
        trackId: entry.track.id,
        filePath: entry.filePath
      }))
    );

    return {
      tracks: loaded.tracks.map((entry) => entry.track),
      skipped: loaded.skipped
    };
  });

  ipcMain.handle('track:readBufferById', async (_event, trackId: unknown) => {
    const filePath = trackRegistry.resolvePath(trackId);
    const buffer = await readFile(filePath);
    return new Uint8Array(buffer);
  });

  ipcMain.handle('settings:get', async () => {
    return readSettings();
  });

  ipcMain.handle(
    'settings:save',
    async (_event, candidate: Partial<PlayerSettings>) => {
      return writeSettings(candidate);
    }
  );
};
