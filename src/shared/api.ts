import { TrackAnalysis } from './analysis';
import { RequestMixPlanInput, RequestMixPlanResult } from './plannerContract';
import {
  AiAgentConnectionResult,
  AiAgentProfile,
  PlayerSettings,
  Track,
  TrackLoadMode,
  TrackLoadResult
} from './types';

export interface DropperApi {
  openTracks(mode: TrackLoadMode): Promise<TrackLoadResult>;
  getTracks(): Promise<Track[]>;
  setTrackOrder(trackIds: string[]): Promise<Track[]>;
  clearTracks(): Promise<void>;
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
