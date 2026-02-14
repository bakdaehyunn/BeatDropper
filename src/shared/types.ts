export type AudioFormat = 'mp3' | 'wav';

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
}

export type PlayerEventType =
  | 'track_started'
  | 'predecode_started'
  | 'bpm_resolved'
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
