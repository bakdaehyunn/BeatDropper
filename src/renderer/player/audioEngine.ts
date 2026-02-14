import { DEFAULT_SETTINGS, sanitizeSettings } from '../../shared/settings';
import {
  PlayerEvent,
  PlayerSettings,
  Track,
  TransitionAdvisor,
  TransitionContext,
  TransitionPlan
} from '../../shared/types';
import { estimateTrackBpm } from './bpmEstimator';
import { QueueManager } from './queueManager';
import { RuleBasedAdvisor } from './ruleBasedAdvisor';
import { resolveTempoSyncDecision } from './tempoSyncPolicy';
import { TransitionScheduler } from './transitionScheduler';

type AudioBufferLike = {
  duration: number;
  sampleRate?: number;
  numberOfChannels?: number;
  getChannelData?: (channel: number) => Float32Array;
};

type AudioParamLike = {
  cancelScheduledValues(startTime: number): void;
  setValueAtTime(value: number, startTime: number): void;
  linearRampToValueAtTime(value: number, endTime: number): void;
};

type GainNodeLike = {
  gain: AudioParamLike;
  connect(destination: unknown): void;
};

type AnalyserNodeLike = {
  fftSize: number;
  smoothingTimeConstant: number;
  connect(destination: unknown): void;
  getFloatTimeDomainData(array: Float32Array): void;
};

type AudioBufferSourceNodeLike = {
  buffer: AudioBufferLike | null;
  onended: (() => void) | null;
  playbackRate?: AudioParamLike;
  connect(destination: unknown): void;
  start(when: number): void;
  stop(when?: number): void;
};

type AudioContextLike = {
  readonly currentTime: number;
  readonly destination: unknown;
  createGain(): GainNodeLike;
  createAnalyser?(): AnalyserNodeLike;
  createBufferSource(): AudioBufferSourceNodeLike;
  decodeAudioData(audioData: ArrayBuffer): Promise<AudioBufferLike>;
  suspend?(): Promise<void>;
  resume?(): Promise<void>;
  close?(): Promise<void>;
};

interface DeckState {
  gainNode: GainNodeLike;
  source: AudioBufferSourceNodeLike | null;
}

interface TrackTempo {
  bpm: number;
  source: 'metadata' | 'estimated';
  confidence?: number;
}

interface AudioEngineDeps {
  readTrackBuffer(trackId: string): Promise<ArrayBuffer>;
  settings?: Partial<PlayerSettings>;
  advisor?: TransitionAdvisor;
  contextFactory?: () => AudioContextLike;
}

type DeckKey = 'A' | 'B';

const MAX_DECODE_CACHE = 8;
const MIN_VALID_BPM = 60;
const MAX_VALID_BPM = 200;
const TEMPO_RECOVERY_SEC = 0.8;

export class AudioEngine {
  private readonly context: AudioContextLike;
  private readonly readTrackBuffer: (trackId: string) => Promise<ArrayBuffer>;
  private readonly advisor: TransitionAdvisor;
  private readonly scheduler: TransitionScheduler;
  private readonly queueManager: QueueManager;
  private readonly listeners = new Set<(event: PlayerEvent) => void>();
  private readonly decodedCache = new Map<string, AudioBufferLike>();
  private readonly decodedCacheOrder: string[] = [];
  private readonly trackTempoCache = new Map<string, TrackTempo | null>();
  private readonly tempoFailureReasonByTrack = new Map<string, string>();

  private readonly masterGain: GainNodeLike;
  private readonly analyser: AnalyserNodeLike | null;
  private readonly analyserBuffer: Float32Array | null;
  private deckA: DeckState;
  private deckB: DeckState;
  private activeDeck: DeckKey = 'A';

  private settings: PlayerSettings;
  private running = false;
  private paused = false;
  private currentIndex: number | null = null;
  private scheduleToken = 0;
  private currentTrackStartAt = 0;
  private currentTrackDurationSec = 0;

  constructor(deps: AudioEngineDeps) {
    this.readTrackBuffer = deps.readTrackBuffer;
    this.settings = sanitizeSettings({
      ...DEFAULT_SETTINGS,
      ...(deps.settings ?? {})
    });
    this.advisor = deps.advisor ?? new RuleBasedAdvisor();
    this.queueManager = new QueueManager([], this.settings.repeatAll);

    const contextFactory =
      deps.contextFactory ?? (() => new AudioContext() as unknown as AudioContextLike);
    this.context = contextFactory();
    this.scheduler = new TransitionScheduler(() => this.context.currentTime);

    this.masterGain = this.context.createGain();
    this.masterGain.gain.setValueAtTime(
      this.settings.masterGain,
      this.context.currentTime
    );
    this.analyser = this.context.createAnalyser?.() ?? null;
    if (this.analyser) {
      this.analyser.fftSize = 2048;
      this.analyser.smoothingTimeConstant = 0.82;
      this.masterGain.connect(this.analyser);
      this.analyser.connect(this.context.destination);
      this.analyserBuffer = new Float32Array(this.analyser.fftSize);
    } else {
      this.masterGain.connect(this.context.destination);
      this.analyserBuffer = null;
    }

    this.deckA = this.createDeck();
    this.deckB = this.createDeck();
  }

  onEvent(listener: (event: PlayerEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  loadTracks(tracks: Track[]): void {
    this.queueManager.setTracks(tracks);
    this.trackTempoCache.clear();
    this.tempoFailureReasonByTrack.clear();
  }

  setSettings(candidate: Partial<PlayerSettings>): PlayerSettings {
    this.settings = sanitizeSettings({ ...this.settings, ...candidate });
    this.queueManager.setRepeatAll(this.settings.repeatAll);
    this.masterGain.gain.setValueAtTime(
      this.settings.masterGain,
      this.context.currentTime
    );
    return this.settings;
  }

  getSettings(): PlayerSettings {
    return this.settings;
  }

  getCurrentIndex(): number | null {
    return this.currentIndex;
  }

  isPlaying(): boolean {
    return this.running && !this.paused;
  }

  isPaused(): boolean {
    return this.running && this.paused;
  }

  getOutputLevel(): number {
    if (!this.running || this.paused || !this.analyser || !this.analyserBuffer) {
      return 0;
    }

    this.analyser.getFloatTimeDomainData(this.analyserBuffer);
    let sumSquares = 0;
    for (let index = 0; index < this.analyserBuffer.length; index += 1) {
      const sample = this.analyserBuffer[index];
      sumSquares += sample * sample;
    }

    const rms = Math.sqrt(sumSquares / this.analyserBuffer.length);
    return Math.min(1, rms * 2.2);
  }

  async start(startIndex = 0): Promise<void> {
    const tracks = this.queueManager.getTracks();
    if (tracks.length === 0) {
      this.emit('error', 'No tracks loaded');
      return;
    }

    const safeIndex = Math.min(Math.max(startIndex, 0), tracks.length - 1);

    try {
      await this.context.resume?.();
      this.running = true;
      this.paused = false;
      await this.playTrack(safeIndex, this.context.currentTime + 0.05);
    } catch (error) {
      this.emit('error', 'Failed to start playback', {
        reason: this.normalizeErrorMessage(error)
      });
      this.stop();
    }
  }

  stop(): void {
    this.running = false;
    this.paused = false;
    this.scheduleToken += 1;
    this.scheduler.clear();

    this.stopDeckSource(this.deckA);
    this.stopDeckSource(this.deckB);

    this.deckA.gainNode.gain.setValueAtTime(0, this.context.currentTime);
    this.deckB.gainNode.gain.setValueAtTime(0, this.context.currentTime);

    this.currentIndex = null;
    this.currentTrackStartAt = 0;
    this.currentTrackDurationSec = 0;
    this.activeDeck = 'A';
    this.emit('playback_stopped', 'Playback stopped');
  }

  async pause(): Promise<void> {
    if (!this.running || this.paused) {
      return;
    }

    await this.context.suspend?.();
    this.paused = true;
    this.scheduler.clear();
    this.emit('playback_paused', 'Playback paused');
  }

  async resume(): Promise<void> {
    if (!this.running || !this.paused) {
      return;
    }

    await this.context.resume?.();
    this.paused = false;

    if (
      this.currentIndex !== null &&
      this.currentTrackDurationSec > 0
    ) {
      const currentTrack = this.queueManager.getCurrent(this.currentIndex);
      if (currentTrack) {
        this.scheduleForCurrent(
          this.currentIndex,
          currentTrack,
          this.currentTrackStartAt,
          this.currentTrackDurationSec
        );
      }
    }

    this.emit('playback_resumed', 'Playback resumed');
  }

  async skipToNext(): Promise<void> {
    if (!this.running || this.currentIndex === null) {
      return;
    }

    const nextIndex = this.queueManager.getNextIndex(this.currentIndex);
    if (nextIndex === null) {
      this.stop();
      return;
    }

    await this.jumpToIndex(nextIndex, 'Manual skip failed');
  }

  async skipToPrevious(): Promise<void> {
    if (!this.running || this.currentIndex === null) {
      return;
    }

    const elapsed = Math.max(0, this.context.currentTime - this.currentTrackStartAt);
    const shouldRestartCurrent = elapsed > 3;

    let previousIndex: number | null = shouldRestartCurrent
      ? this.currentIndex
      : this.queueManager.getPreviousIndex(this.currentIndex);

    if (previousIndex === null) {
      previousIndex = this.currentIndex;
    }

    await this.jumpToIndex(previousIndex, 'Manual previous failed');
  }

  async destroy(): Promise<void> {
    this.stop();
    await this.context.close?.();
  }

  private createDeck(): DeckState {
    const gainNode = this.context.createGain();
    gainNode.gain.setValueAtTime(0, this.context.currentTime);
    gainNode.connect(this.masterGain);
    return { gainNode, source: null };
  }

  private getActiveDeck(): DeckState {
    return this.activeDeck === 'A' ? this.deckA : this.deckB;
  }

  private getInactiveDeck(): DeckState {
    return this.activeDeck === 'A' ? this.deckB : this.deckA;
  }

  private swapDecks(): void {
    this.activeDeck = this.activeDeck === 'A' ? 'B' : 'A';
  }

  private emit(
    type: PlayerEvent['type'],
    message: string,
    details?: Record<string, unknown>
  ): void {
    const event: PlayerEvent = {
      type,
      message,
      at: this.context.currentTime,
      details
    };
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  private async playTrack(index: number, startAt: number): Promise<void> {
    const track = this.queueManager.getCurrent(index);
    if (!track) {
      this.emit('error', `Track index out of range: ${index}`);
      this.stop();
      return;
    }

    const decoded = await this.decodeTrack(track);
    if (!this.running) {
      return;
    }

    const deck = this.getActiveDeck();
    this.startSource(deck, decoded, startAt, 1);
    this.currentIndex = index;
    this.currentTrackStartAt = startAt;
    this.currentTrackDurationSec = decoded.duration;

    this.emit('track_started', `Playing: ${track.title}`, {
      trackId: track.id,
      index
    });

    this.scheduleForCurrent(index, track, startAt, decoded.duration);
  }

  private scheduleForCurrent(
    currentIndex: number,
    currentTrack: Track,
    currentStartAt: number,
    durationSec: number
  ): void {
    const currentEndAt = currentStartAt + durationSec;
    const nextIndex = this.queueManager.getNextIndex(currentIndex);

    if (nextIndex === null) {
      this.scheduler.clear();
      const token = ++this.scheduleToken;
      this.scheduler.scheduleAt(currentEndAt, () =>
        this.handleTrackEnd(currentIndex, token)
      );
      return;
    }

    const nextTrack = this.queueManager.getCurrent(nextIndex);
    if (!nextTrack) {
      this.emit('error', 'Next track not found in queue');
      this.stop();
      return;
    }

    const transitionContext: TransitionContext = {
      current: currentTrack,
      next: nextTrack,
      currentStartAt,
      currentEndAt
    };

    const transitionPlan = this.advisor.plan(transitionContext, this.settings);
    const token = ++this.scheduleToken;

    this.scheduler.scheduleTransition({
      currentEndAt,
      plan: transitionPlan,
      settings: this.settings,
      callbacks: {
        onPredecode: () =>
          this.handlePredecode(nextIndex, transitionPlan.crossfadeStartAt, token),
        onCrossfade: () =>
          this.handleCrossfade(nextIndex, transitionPlan, token),
        onTrackEnd: () => this.handleTrackEnd(currentIndex, token)
      }
    });
  }

  private async handlePredecode(
    nextIndex: number,
    crossfadeStartAt: number,
    token: number
  ): Promise<void> {
    if (!this.isTokenActive(token)) {
      return;
    }

    const nextTrack = this.queueManager.getCurrent(nextIndex);
    if (!nextTrack) {
      return;
    }

    this.emit('predecode_started', `Pre-decoding: ${nextTrack.title}`, {
      trackId: nextTrack.id
    });

    try {
      await this.decodeTrack(nextTrack);
      if (!this.isTokenActive(token)) {
        return;
      }

      const remaining = crossfadeStartAt - this.context.currentTime;
      if (remaining < 3) {
        this.emit('decode_delayed', `Predecode finished only ${remaining.toFixed(2)}s before transition`, {
          trackId: nextTrack.id,
          remainingSec: remaining
        });
      }
    } catch (error) {
      this.emit('error', `Predecode failed: ${nextTrack.title}`, {
        reason: this.normalizeErrorMessage(error)
      });
    }
  }

  private async handleCrossfade(
    nextIndex: number,
    plan: TransitionPlan,
    token: number
  ): Promise<void> {
    if (!this.isTokenActive(token)) {
      return;
    }

    const nextTrack = this.queueManager.getCurrent(nextIndex);
    if (!nextTrack) {
      this.emit('error', 'Crossfade aborted: next track unavailable');
      return;
    }

    const nextDecoded = this.decodedCache.get(nextTrack.id);
    if (nextDecoded) {
      this.performTransition(
        nextIndex,
        nextDecoded,
        plan.crossfadeStartAt,
        plan.crossfadeEndAt
      );
      return;
    }

    this.emit('decode_delayed', `Decode delayed during transition: ${nextTrack.title}`, {
      trackId: nextTrack.id
    });

    const activeDeck = this.getActiveDeck();
    const now = this.context.currentTime;
    this.applyFadeOut(activeDeck, now, now + 0.2);
    activeDeck.source?.stop(now + 0.22);

    try {
      const decoded = await this.decodeTrack(nextTrack);
      if (!this.isTokenActive(token)) {
        return;
      }

      const startAt = this.context.currentTime + 0.02;
      const fadeEndAt = startAt + Math.min(this.settings.fadeDurationSec, 2);
      this.performTransition(nextIndex, decoded, startAt, fadeEndAt);
    } catch (error) {
      this.emit('error', `Fallback transition failed: ${nextTrack.title}`, {
        reason: this.normalizeErrorMessage(error)
      });
    }
  }

  private handleTrackEnd(endedIndex: number, token: number): void {
    if (!this.isTokenActive(token)) {
      return;
    }

    if (this.currentIndex !== endedIndex) {
      return;
    }

    const nextIndex = this.queueManager.getNextIndex(endedIndex);
    if (nextIndex === null) {
      this.stop();
      return;
    }

    void this.tryHardSwitch(nextIndex);
  }

  private async tryHardSwitch(nextIndex: number): Promise<void> {
    if (!this.running) {
      return;
    }

    const nextTrack = this.queueManager.getCurrent(nextIndex);
    if (!nextTrack) {
      this.stop();
      return;
    }

    try {
      const decoded = await this.decodeTrack(nextTrack);
      const startAt = this.context.currentTime + 0.02;
      const fadeEndAt = startAt + Math.min(1, this.settings.fadeDurationSec);
      this.performTransition(nextIndex, decoded, startAt, fadeEndAt);
    } catch (error) {
      this.emit('error', `Hard switch failed: ${nextTrack.title}`, {
        reason: this.normalizeErrorMessage(error)
      });
      this.stop();
    }
  }

  private performTransition(
    nextIndex: number,
    nextBuffer: AudioBufferLike,
    startAt: number,
    fadeEndAt: number
  ): void {
    if (!this.running) {
      return;
    }

    const previousDeck = this.getActiveDeck();
    const nextDeck = this.getInactiveDeck();
    const currentTrack =
      this.currentIndex !== null ? this.queueManager.getCurrent(this.currentIndex) : null;
    const nextTrack = this.queueManager.getCurrent(nextIndex);
    if (!nextTrack) {
      return;
    }

    const nextSource = this.startSource(nextDeck, nextBuffer, startAt, 0);
    nextDeck.gainNode.gain.cancelScheduledValues(startAt);
    nextDeck.gainNode.gain.setValueAtTime(0, startAt);
    nextDeck.gainNode.gain.linearRampToValueAtTime(1, fadeEndAt);

    this.tryApplyTempoSync({
      currentTrack,
      nextTrack,
      nextSource,
      startAt,
      fadeEndAt
    });

    this.applyFadeOut(previousDeck, startAt, fadeEndAt);
    previousDeck.source?.stop(fadeEndAt + 0.05);

    this.emit('transition_started', `Crossfade: ${nextTrack.title}`, {
      nextTrackId: nextTrack.id,
      startAt,
      endAt: fadeEndAt
    });

    const transitionCompleteDelay = Math.max(
      0,
      (fadeEndAt - this.context.currentTime) * 1000
    );
    setTimeout(() => {
      if (!this.running) {
        return;
      }
      this.emit('transition_completed', `Transition completed: ${nextTrack.title}`, {
        trackId: nextTrack.id
      });
    }, transitionCompleteDelay);

    this.currentIndex = nextIndex;
    this.currentTrackStartAt = startAt;
    this.currentTrackDurationSec = nextBuffer.duration;
    this.swapDecks();

    this.emit('track_started', `Playing: ${nextTrack.title}`, {
      trackId: nextTrack.id,
      index: nextIndex
    });

    this.scheduleForCurrent(nextIndex, nextTrack, startAt, nextBuffer.duration);
  }

  private applyFadeOut(deck: DeckState, startAt: number, endAt: number): void {
    deck.gainNode.gain.cancelScheduledValues(startAt);
    deck.gainNode.gain.setValueAtTime(1, startAt);
    deck.gainNode.gain.linearRampToValueAtTime(0, endAt);
  }

  private startSource(
    deck: DeckState,
    buffer: AudioBufferLike,
    startAt: number,
    initialGain: number
  ): AudioBufferSourceNodeLike {
    this.stopDeckSource(deck, startAt);

    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(deck.gainNode);
    source.start(startAt);

    deck.source = source;
    deck.gainNode.gain.cancelScheduledValues(startAt);
    deck.gainNode.gain.setValueAtTime(initialGain, startAt);
    return source;
  }

  private stopDeckSource(deck: DeckState, when = this.context.currentTime): void {
    if (!deck.source) {
      return;
    }

    try {
      deck.source.stop(when);
    } catch {}

    deck.source = null;
  }

  private async jumpToIndex(index: number, errorMessage: string): Promise<void> {
    const targetTrack = this.queueManager.getCurrent(index);
    if (!targetTrack) {
      this.stop();
      return;
    }

    try {
      if (this.paused) {
        await this.context.resume?.();
        this.paused = false;
      }

      this.scheduler.clear();
      this.scheduleToken += 1;
      const decoded = await this.decodeTrack(targetTrack);
      const startAt = this.context.currentTime + 0.02;
      const fadeEndAt = startAt + Math.min(this.settings.fadeDurationSec, 2);
      this.performTransition(index, decoded, startAt, fadeEndAt);
    } catch (error) {
      this.emit('error', errorMessage, {
        reason: this.normalizeErrorMessage(error)
      });
    }
  }

  private async decodeTrack(track: Track): Promise<AudioBufferLike> {
    const cached = this.decodedCache.get(track.id);
    if (cached) {
      this.resolveTrackTempo(track, cached);
      return cached;
    }

    const raw = await this.readTrackBuffer(track.id);
    const cloned = raw.slice(0);
    const decoded = await this.context.decodeAudioData(cloned);
    this.cacheDecoded(track.id, decoded);
    this.resolveTrackTempo(track, decoded);
    return decoded;
  }

  private cacheDecoded(trackId: string, decoded: AudioBufferLike): void {
    if (this.decodedCache.has(trackId)) {
      return;
    }

    this.decodedCache.set(trackId, decoded);
    this.decodedCacheOrder.push(trackId);

    while (this.decodedCacheOrder.length > MAX_DECODE_CACHE) {
      const oldestId = this.decodedCacheOrder.shift();
      if (!oldestId) {
        break;
      }
      this.decodedCache.delete(oldestId);
    }
  }

  private isTokenActive(token: number): boolean {
    return this.running && !this.paused && token === this.scheduleToken;
  }

  private normalizeErrorMessage(error: unknown): string {
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }

  private tryApplyTempoSync(args: {
    currentTrack: Track | null;
    nextTrack: Track;
    nextSource: AudioBufferSourceNodeLike;
    startAt: number;
    fadeEndAt: number;
  }): void {
    const currentTempo = args.currentTrack ? this.getTrackTempo(args.currentTrack) : null;
    const nextTempo = this.getTrackTempo(args.nextTrack);
    const decision = resolveTempoSyncDecision(
      currentTempo?.bpm ?? null,
      nextTempo?.bpm ?? null
    );

    if (decision.mode !== 'apply') {
      this.emit('tempo_sync_skipped', 'Tempo sync skipped', {
        reason: decision.reason,
        currentTrackId: args.currentTrack?.id ?? null,
        nextTrackId: args.nextTrack.id,
        currentBpm: currentTempo?.bpm ?? null,
        nextBpm: nextTempo?.bpm ?? null,
        currentReason: args.currentTrack
          ? this.tempoFailureReasonByTrack.get(args.currentTrack.id) ?? null
          : 'missing_current_track',
        nextReason: this.tempoFailureReasonByTrack.get(args.nextTrack.id) ?? null,
        desiredRate: decision.desiredRate,
        targetRate: decision.targetRate,
        residualMismatchPct: decision.residualMismatchPct
      });
      return;
    }

    if (!args.nextSource.playbackRate) {
      this.emit('tempo_sync_skipped', 'Tempo sync skipped', {
        reason: 'playback_rate_unavailable',
        currentTrackId: args.currentTrack?.id ?? null,
        nextTrackId: args.nextTrack.id,
        currentBpm: currentTempo?.bpm ?? null,
        nextBpm: nextTempo?.bpm ?? null
      });
      return;
    }

    const recoveryAt = args.fadeEndAt + TEMPO_RECOVERY_SEC;
    args.nextSource.playbackRate.cancelScheduledValues(args.startAt);
    args.nextSource.playbackRate.setValueAtTime(decision.targetRate, args.startAt);
    args.nextSource.playbackRate.setValueAtTime(decision.targetRate, args.fadeEndAt);
    args.nextSource.playbackRate.linearRampToValueAtTime(1, recoveryAt);

    this.emit('tempo_sync_applied', 'Tempo sync applied', {
      currentTrackId: args.currentTrack?.id ?? null,
      nextTrackId: args.nextTrack.id,
      currentBpm: currentTempo?.bpm ?? null,
      nextBpm: nextTempo?.bpm ?? null,
      currentSource: currentTempo?.source ?? null,
      nextSource: nextTempo?.source ?? null,
      targetRate: decision.targetRate,
      desiredRate: decision.desiredRate,
      residualMismatchPct: decision.residualMismatchPct,
      recoveryAt
    });
  }

  private getTrackTempo(track: Track): TrackTempo | null {
    const cached = this.trackTempoCache.get(track.id);
    if (cached !== undefined) {
      return cached;
    }

    return this.resolveTrackTempo(track);
  }

  private resolveTrackTempo(track: Track, decoded?: AudioBufferLike): TrackTempo | null {
    const cached = this.trackTempoCache.get(track.id);
    if (cached !== undefined) {
      return cached;
    }

    const metadataBpm = this.normalizeBpm(track.bpm);
    if (metadataBpm !== null) {
      const resolved: TrackTempo = {
        bpm: metadataBpm,
        source: 'metadata'
      };
      this.trackTempoCache.set(track.id, resolved);
      this.tempoFailureReasonByTrack.delete(track.id);
      this.emit('bpm_resolved', `BPM resolved: ${track.title}`, {
        trackId: track.id,
        bpm: metadataBpm,
        source: 'metadata'
      });
      return resolved;
    }

    if (decoded === undefined) {
      this.tempoFailureReasonByTrack.set(track.id, 'missing_bpm');
      return null;
    }

    const estimate = estimateTrackBpm(decoded);
    if (estimate.bpm === null) {
      this.trackTempoCache.set(track.id, null);
      this.tempoFailureReasonByTrack.set(track.id, estimate.reason ?? 'missing_bpm');
      return null;
    }

    const resolved: TrackTempo = {
      bpm: estimate.bpm,
      source: 'estimated',
      confidence: estimate.confidence
    };
    this.trackTempoCache.set(track.id, resolved);
    this.tempoFailureReasonByTrack.delete(track.id);
    this.emit('bpm_resolved', `BPM estimated: ${track.title}`, {
      trackId: track.id,
      bpm: estimate.bpm,
      source: 'estimated',
      confidence: estimate.confidence,
      analyzedSeconds: estimate.analyzedSeconds
    });
    return resolved;
  }

  private normalizeBpm(candidate: number | null | undefined): number | null {
    if (
      typeof candidate !== 'number' ||
      !Number.isFinite(candidate) ||
      candidate < MIN_VALID_BPM ||
      candidate > MAX_VALID_BPM
    ) {
      return null;
    }

    return candidate;
  }
}
