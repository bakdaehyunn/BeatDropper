import { contextBridge, ipcRenderer } from 'electron';
import { DropperApi } from '../shared/api';
import { PlayerSettings, TrackLoadMode, TrackLoadResult } from '../shared/types';

const toArrayBuffer = (payload: unknown): ArrayBuffer => {
  if (payload instanceof ArrayBuffer) {
    return payload;
  }

  if (ArrayBuffer.isView(payload)) {
    const view = payload as ArrayBufferView;
    const underlying = view.buffer;

    if (underlying instanceof ArrayBuffer) {
      if (view.byteOffset === 0 && view.byteLength === underlying.byteLength) {
        return underlying;
      }
      return underlying.slice(view.byteOffset, view.byteOffset + view.byteLength);
    }

    const copied = new Uint8Array(view.byteLength);
    copied.set(new Uint8Array(underlying, view.byteOffset, view.byteLength));
    return copied.buffer;
  }

  throw new Error('Invalid track buffer payload');
};

const dropperApi: DropperApi = {
  openTracks: async (mode: TrackLoadMode): Promise<TrackLoadResult> => {
    return ipcRenderer.invoke('library:openTracks', mode);
  },
  readTrackBufferById: async (trackId: string): Promise<ArrayBuffer> => {
    const payload = await ipcRenderer.invoke('track:readBufferById', trackId);
    return toArrayBuffer(payload);
  },
  getTrackAnalysis: async (trackId: string) => {
    return ipcRenderer.invoke('analysis:getByTrackId', trackId);
  },
  requestMixPlan: async (candidate) => {
    return ipcRenderer.invoke('planner:requestMixPlan', candidate);
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
