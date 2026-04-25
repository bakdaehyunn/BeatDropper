export type AudioFormat = 'mp3' | 'wav';
export type AiDjMode = 'safe' | 'balanced' | 'adventurous';

export interface Track {
  id: string;
  title: string;
  durationSec: number;
  format: AudioFormat;
  bpm?: number | null;
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
