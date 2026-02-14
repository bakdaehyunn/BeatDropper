import { PlayerSettings, TrackLoadResult } from './types';

export interface DropperApi {
  openTracks(): Promise<TrackLoadResult>;
  readTrackBufferById(trackId: string): Promise<ArrayBuffer>;
  getSettings(): Promise<PlayerSettings>;
  saveSettings(candidate: Partial<PlayerSettings>): Promise<PlayerSettings>;
}
