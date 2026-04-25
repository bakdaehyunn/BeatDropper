import { TrackAnalysis } from './analysis';
import { RequestMixPlanInput, RequestMixPlanResult } from './plannerContract';
import { PlayerSettings, TrackLoadMode, TrackLoadResult } from './types';

export interface DropperApi {
  openTracks(mode: TrackLoadMode): Promise<TrackLoadResult>;
  readTrackBufferById(trackId: string): Promise<ArrayBuffer>;
  getTrackAnalysis(trackId: string): Promise<TrackAnalysis | null>;
  requestMixPlan(candidate: RequestMixPlanInput): Promise<RequestMixPlanResult>;
  getSettings(): Promise<PlayerSettings>;
  saveSettings(candidate: Partial<PlayerSettings>): Promise<PlayerSettings>;
}
