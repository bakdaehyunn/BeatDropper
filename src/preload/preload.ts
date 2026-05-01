import { contextBridge, ipcRenderer } from 'electron';
import { DropperApi } from '../shared/api';
import { PlayerSettings, TrackLoadMode, TrackLoadResult } from '../shared/types';

const toArrayBuffer = (payload: unknown): ArrayBuffer => {
  if (payload instanceof ArrayBuffer) {
    return payload;
  }

  if (
    typeof payload === 'object' &&
    payload !== null &&
    'type' in payload &&
    'data' in payload &&
    (payload as { type?: unknown }).type === 'Buffer' &&
    Array.isArray((payload as { data?: unknown }).data)
  ) {
    return new Uint8Array((payload as { data: number[] }).data).buffer;
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
  getTracks: async () => {
    return ipcRenderer.invoke('library:getTracks');
  },
  setTrackOrder: async (trackIds: string[]) => {
    return ipcRenderer.invoke('library:setTrackOrder', trackIds);
  },
  clearTracks: async (): Promise<void> => {
    await ipcRenderer.invoke('library:clearTracks');
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
  },
  minimizeWindow: async (): Promise<void> => {
    await ipcRenderer.invoke('window:minimize');
  },
  toggleMaximizeWindow: async (): Promise<void> => {
    await ipcRenderer.invoke('window:toggleMaximize');
  },
  closeWindow: async (): Promise<void> => {
    await ipcRenderer.invoke('window:close');
  }
};

contextBridge.exposeInMainWorld('dropperApi', dropperApi);
