import { contextBridge, ipcRenderer } from 'electron';
import { DropperApi } from '../shared/api';
import { PlayerSettings, TrackLoadResult } from '../shared/types';

const dropperApi: DropperApi = {
  openTracks: async (): Promise<TrackLoadResult> => {
    return ipcRenderer.invoke('library:openTracks');
  },
  readTrackBufferById: async (trackId: string): Promise<ArrayBuffer> => {
    const bytes = (await ipcRenderer.invoke(
      'track:readBufferById',
      trackId
    )) as Uint8Array;
    return Uint8Array.from(bytes).buffer;
  },
  getSettings: async (): Promise<PlayerSettings> => {
    return ipcRenderer.invoke('settings:get');
  },
  saveSettings: async (
    candidate: Partial<PlayerSettings>
  ): Promise<PlayerSettings> => {
    return ipcRenderer.invoke('settings:save', candidate);
  }
};

contextBridge.exposeInMainWorld('dropperApi', dropperApi);
