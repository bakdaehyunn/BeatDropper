export type AudioFormat = 'mp3' | 'wav';
export type AiDjMode = 'safe' | 'balanced' | 'adventurous';
export type AiAgentProfileKind = 'cli';

export interface AiAgentProfile {
  id: string;
  name: string;
  kind: AiAgentProfileKind;
  command: string;
  args: string[];
  timeoutMs: number;
  enabled: boolean;
}

export type AiAgentConnectionStatus =
  | 'not_checked'
  | 'ready'
  | 'cli_not_found'
  | 'login_required'
  | 'test_failed';

export interface AiAgentConnectionResult {
  profileId: string;
  profileName: string;
  status: AiAgentConnectionStatus;
  message: string;
  checkedAt: string;
  canRunPlanner: boolean;
  details?: Record<string, string | number | boolean | null>;
}

export interface Track {
  id: string;
  title: string;
  durationSec: number;
  format: AudioFormat;
  bpm?: number | null;
}

export interface MusicLibraryTrack extends Track {
  addedAt: string;
  updatedAt: string;
  sourcePath: string;
  sourceLabel: string;
  missing: boolean;
  missingAt: string | null;
}

export interface UserPlaylist {
  id: string;
  name: string;
  trackIds: string[];
  createdAt: string;
  updatedAt: string;
}

export interface UserPlaylistMutationResult {
  playlists: UserPlaylist[];
  playlist: UserPlaylist | null;
}

export interface PlayerSettings {
  fadeDurationSec: number;
  masterGain: number;
  predecodeLeadSec: number;
  repeatAll: boolean;
  decodeTimeoutDurationWeightMs: number;
  decodeTimeoutSizeWeightMs: number;
  aiDjEnabled: boolean;
  aiDjMode: AiDjMode;
  aiAgentProfiles: AiAgentProfile[];
  activeAiAgentProfileId: string;
  plannerCommand: string;
  plannerArgs: string[];
  plannerTimeoutMs: number;
}

export interface TransitionContext {
  current: Track;
  next: Track;
  currentStartAt: number;
  currentEndAt: number;
}

export interface TransitionPlan {
  crossfadeStartAt: number;
  crossfadeEndAt: number;
}

export interface TransitionAdvisor {
  plan(ctx: TransitionContext, settings: PlayerSettings): TransitionPlan;
}

export interface TrackLoadResult {
  tracks: Track[];
  skipped: string[];
  canceled: boolean;
  mode: TrackLoadMode;
}

export type TrackLoadMode = 'replace' | 'append';

export interface MusicLibraryImportResult {
  tracks: MusicLibraryTrack[];
  added: number;
  updated: number;
  restored: number;
  missing: number;
  skipped: string[];
  canceled: boolean;
  sourcePath: string | null;
}

export type PlayerEventType =
  | 'track_started'
  | 'predecode_started'
  | 'bpm_resolved'
  | 'mix_plan_applied'
  | 'mix_plan_fallback'
  | 'transition_started'
  | 'transition_completed'
  | 'tempo_sync_applied'
  | 'tempo_sync_skipped'
  | 'decode_delayed'
  | 'track_skipped'
  | 'playback_paused'
  | 'playback_resumed'
  | 'playback_stopped'
  | 'error';

export interface PlayerEvent {
  type: PlayerEventType;
  at: number;
  message: string;
  details?: Record<string, unknown>;
}
