import { TrackAnalysis } from './analysis';
import { RequestMixPlanInput, RequestMixPlanResult } from './plannerContract';
import {
  AiAgentConnectionResult,
  AiAgentProfile,
  MusicLibraryImportResult,
  MusicLibraryTrack,
  PlayerSettings,
  Track,
  TrackLoadMode,
  TrackLoadResult,
  UserPlaylist,
  UserPlaylistMutationResult
} from './types';

export interface DropperApi {
  openTracks(mode: TrackLoadMode): Promise<TrackLoadResult>;
  getTracks(): Promise<Track[]>;
  setTrackOrder(trackIds: string[]): Promise<Track[]>;
  clearTracks(): Promise<void>;
  getLibraryTracks(): Promise<MusicLibraryTrack[]>;
  importLibraryFolder(): Promise<MusicLibraryImportResult>;
  rescanLibraryFolder(sourcePath: string): Promise<MusicLibraryImportResult>;
  addLibraryTracksToPlaylist(trackIds: string[], mode: TrackLoadMode): Promise<TrackLoadResult>;
  getUserPlaylists(): Promise<UserPlaylist[]>;
  createUserPlaylist(name: string, trackIds: string[]): Promise<UserPlaylistMutationResult>;
  renameUserPlaylist(playlistId: string, name: string): Promise<UserPlaylistMutationResult>;
  deleteUserPlaylist(playlistId: string): Promise<UserPlaylistMutationResult>;
  setUserPlaylistTracks(playlistId: string, trackIds: string[]): Promise<UserPlaylistMutationResult>;
  addLibraryTracksToUserPlaylist(
    playlistId: string,
    trackIds: string[]
  ): Promise<UserPlaylistMutationResult>;
  loadUserPlaylist(playlistId: string): Promise<TrackLoadResult>;
  readTrackBufferById(trackId: string): Promise<ArrayBuffer>;
  getTrackAnalysis(trackId: string): Promise<TrackAnalysis | null>;
  saveTrackAnalysis(trackId: string, analysis: TrackAnalysis): Promise<TrackAnalysis>;
  requestMixPlan(candidate: RequestMixPlanInput): Promise<RequestMixPlanResult>;
  checkAiAgentConnection(profile: AiAgentProfile): Promise<AiAgentConnectionResult>;
  getSettings(): Promise<PlayerSettings>;
  saveSettings(candidate: Partial<PlayerSettings>): Promise<PlayerSettings>;
  minimizeWindow(): Promise<void>;
  toggleMaximizeWindow(): Promise<void>;
  closeWindow(): Promise<void>;
}
