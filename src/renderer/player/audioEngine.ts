import { DEFAULT_SETTINGS, sanitizeSettings } from '../../shared/settings';
import { estimateAdaptiveDecodeTimeoutMs } from '../../shared/decodeTimeout';
import { MixPlan } from '../../shared/mixPlan';
import {
  RequestMixPlanResult
} from '../../shared/plannerContract';
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
  start(when: number, offset?: number): void;
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
  requestMixPlan?: (input: {
    currentTrack: Track;
    nextTrack: Track;
    currentPlayback: {
      elapsedSec: number;
    };
    settingsOverride?: Partial<PlayerSettings>;
  }) => Promise<RequestMixPlanResult>;
  settings?: Partial<PlayerSettings>;
  advisor?: TransitionAdvisor;
  contextFactory?: () => AudioContextLike;
}

interface TransitionExecutionPlan {
  crossfadeStartAt: number;
  crossfadeEndAt: number;
  nextTrackStartOffsetSec: number;
  source: 'rule_based' | 'ai';
  reasoningSummary: string | null;
  tempoSync:
    | {
        mode: 'auto';
      }
    | {
        mode: 'disabled';
      }
    | {
        mode: 'fixed';
        targetRate: number;
      };
}

type DeckKey = 'A' | 'B';
type RecoveryStage = 'start' | 'predecode' | 'crossfade' | 'hard_switch' | 'manual_jump';

const MAX_DECODE_CACHE = 8;
const MIN_VALID_BPM = 60;
const MAX_VALID_BPM = 200;
const TEMPO_RECOVERY_SEC = 0.8;
const START_DECODE_TIMEOUT_MS = 2500;
const PREDECODE_TIMEOUT_MS = 3000;
const RECOVERY_DECODE_TIMEOUT_MS = 1200;
const MANUAL_JUMP_DECODE_TIMEOUT_MS = 1800;
const DECODE_TIMEOUT_PREFIX = 'Decode timeout';
const OUTPUT_HEADROOM_GAIN = 0.72;

export class AudioEngine {
  private readonly context: AudioContextLike;
  private readonly readTrackBuffer: (trackId: string) => Promise<ArrayBuffer>;
  private readonly requestMixPlan:
    | AudioEngineDeps['requestMixPlan']
    | null;
  private readonly advisor: TransitionAdvisor;
  private readonly scheduler: TransitionScheduler;
  private readonly queueManager: QueueManager;
  private readonly listeners = new Set<(event: PlayerEvent) => void>();
  private readonly decodedCache = new Map<string, AudioBufferLike>();
  private readonly decodedCacheOrder: string[] = [];
  private readonly inFlightDecode = new Map<string, Promise<AudioBufferLike>>();
  private readonly trackBufferSizeHint = new Map<string, number>();
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
    this.requestMixPlan = deps.requestMixPlan ?? null;
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
      this.resolveOutputGain(),
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
      this.resolveOutputGain(),
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
      const started = await this.playTrack(safeIndex, this.context.currentTime + 0.05);
      if (!started) {
        this.emit('error', 'No playable tracks available');
        this.stop();
      }
    } catch (error) {
      const reason = this.normalizeErrorMessage(error);
      this.emit('error', `Failed to start playback: ${reason}`, {
        reason
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

  private resolveOutputGain(): number {
    return this.settings.masterGain * OUTPUT_HEADROOM_GAIN;
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

  private async playTrack(index: number, startAt: number): Promise<boolean> {
    const playable = await this.resolvePlayableTrack(index, 'start');
    if (!playable) {
      return false;
    }

    if (!this.running) {
      return false;
    }

    const deck = this.getActiveDeck();
    this.startSource(deck, playable.decoded, startAt, 1);
    this.currentIndex = playable.index;
    this.currentTrackStartAt = startAt;
    this.currentTrackDurationSec = playable.decoded.duration;

    this.emit('track_started', `Playing: ${playable.track.title}`, {
      trackId: playable.track.id,
      index: playable.index
    });

    this.scheduleForCurrent(
      playable.index,
      playable.track,
      startAt,
      playable.decoded.duration
    );
    return true;
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
    const executionPlan = this.buildRuleExecutionPlan(transitionPlan);
    const token = ++this.scheduleToken;

    this.scheduler.scheduleTransition({
      currentEndAt,
      plan: transitionPlan,
      settings: this.settings,
      callbacks: {
        onPredecode: () =>
          this.handlePredecode({
            currentIndex,
            currentTrack,
            currentStartAt,
            currentEndAt,
            nextIndex,
            fallbackPlan: executionPlan,
            token
          }),
        onCrossfade: () =>
          this.handleCrossfade(nextIndex, executionPlan, token),
        onTrackEnd: () => this.handleTrackEnd(currentIndex, token)
      }
    });
  }

  private async handlePredecode(args: {
    currentIndex: number;
    currentTrack: Track;
    currentStartAt: number;
    currentEndAt: number;
    nextIndex: number;
    fallbackPlan: TransitionExecutionPlan;
    token: number;
  }): Promise<void> {
    const { currentIndex, currentTrack, currentStartAt, currentEndAt, nextIndex, fallbackPlan, token } =
      args;
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
      await this.decodeTrack(nextTrack, this.decodeTimeoutMsForStage('predecode'));
      if (!this.isTokenActive(token)) {
        return;
      }

      const remaining = fallbackPlan.crossfadeStartAt - this.context.currentTime;
      if (remaining < 3) {
        this.emit('decode_delayed', `Predecode finished only ${remaining.toFixed(2)}s before transition`, {
          trackId: nextTrack.id,
          remainingSec: remaining
        });
      }

      if (!this.requestMixPlan) {
        return;
      }

      let result: RequestMixPlanResult;
      try {
        result = await this.requestMixPlan({
          currentTrack,
          nextTrack,
          currentPlayback: {
            elapsedSec: Math.max(0, this.context.currentTime - currentStartAt)
          }
        });
      } catch (error) {
        this.emit('mix_plan_fallback', 'Using rule-based transition plan', {
          currentTrackId: currentTrack.id,
          nextTrackId: nextTrack.id,
          reason: error instanceof Error ? error.message : String(error),
          plannerRequest: {
            currentTrackId: currentTrack.id,
            nextTrackId: nextTrack.id,
            elapsedSec: Math.max(0, this.context.currentTime - currentStartAt)
          },
          plannerResponse: null
        });
        return;
      }
      if (!this.isTokenActive(token)) {
        return;
      }

      if (!result.plan) {
        this.emit('mix_plan_fallback', 'Using rule-based transition plan', {
          currentTrackId: currentTrack.id,
          nextTrackId: nextTrack.id,
          reason: result.reason,
          plannerRequest: result.request,
          plannerResponse: result.response
        });
        return;
      }

      const executionPlan = this.buildExecutionPlanFromMixPlan(
        currentStartAt,
        currentEndAt,
        result.plan
      );
      this.scheduler.clear();
      this.scheduler.scheduleAt(executionPlan.crossfadeStartAt, () =>
        this.handleCrossfade(nextIndex, executionPlan, token)
      );
      this.scheduler.scheduleAt(currentEndAt, () =>
        this.handleTrackEnd(currentIndex, token)
      );
      this.emit('mix_plan_applied', 'AI mix plan applied', {
        currentTrackId: currentTrack.id,
        nextTrackId: nextTrack.id,
        source: result.source,
        transitionStartAt: executionPlan.crossfadeStartAt,
        transitionEndAt: executionPlan.crossfadeEndAt,
        nextTrackStartOffsetSec: executionPlan.nextTrackStartOffsetSec,
        reasoningSummary: executionPlan.reasoningSummary,
        plannerRequest: result.request,
        plannerResponse: result.response
      });
    } catch (error) {
      if (this.isDecodeTimeoutError(error)) {
        this.emit('decode_delayed', `Predecode timeout: ${nextTrack.title}`, {
          trackId: nextTrack.id,
          timeoutMs: this.decodeTimeoutMsForStage('predecode')
        });
        return;
      }

      this.emit('error', `Predecode failed: ${nextTrack.title}`, {
        reason: this.normalizeErrorMessage(error)
      });
    }
  }

  private async handleCrossfade(
    nextIndex: number,
    plan: TransitionExecutionPlan,
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
        plan
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
      const playable = await this.resolvePlayableTrack(nextIndex, 'crossfade', token);
      if (!playable) {
        if (this.isTokenActive(token)) {
          this.emit('error', 'Fallback transition failed: no playable tracks');
          this.stop();
        }
        return;
      }

      if (!this.isTokenActive(token)) {
        return;
      }

      const startAt = this.context.currentTime + 0.02;
      const fadeEndAt = startAt + Math.min(this.settings.fadeDurationSec, 2);
      this.performTransition(playable.index, playable.decoded, {
        crossfadeStartAt: startAt,
        crossfadeEndAt: fadeEndAt,
        nextTrackStartOffsetSec: 0,
        source: 'rule_based',
        reasoningSummary: null,
        tempoSync: { mode: 'auto' }
      });
    } catch (error) {
      this.emit('error', 'Fallback transition failed', {
        reason: this.normalizeErrorMessage(error)
      });
      this.stop();
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

    const playable = await this.resolvePlayableTrack(nextIndex, 'hard_switch');
    if (!playable) {
      this.emit('error', 'Hard switch failed: no playable tracks');
      this.stop();
      return;
    }

    const startAt = this.context.currentTime + 0.02;
    const fadeEndAt = startAt + Math.min(1, this.settings.fadeDurationSec);
    this.performTransition(playable.index, playable.decoded, {
      crossfadeStartAt: startAt,
      crossfadeEndAt: fadeEndAt,
      nextTrackStartOffsetSec: 0,
      source: 'rule_based',
      reasoningSummary: null,
      tempoSync: { mode: 'auto' }
    });
  }

  private performTransition(
    nextIndex: number,
    nextBuffer: AudioBufferLike,
    plan: TransitionExecutionPlan
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
    const startAt = plan.crossfadeStartAt;
    const fadeEndAt = plan.crossfadeEndAt;
    const safeNextTrackOffsetSec = this.clampStartOffsetSec(
      nextBuffer,
      plan.nextTrackStartOffsetSec
    );
    const remainingDurationSec = Math.max(
      0.05,
      nextBuffer.duration - safeNextTrackOffsetSec
    );

    const nextSource = this.startSource(
      nextDeck,
      nextBuffer,
      startAt,
      0,
      safeNextTrackOffsetSec
    );
    nextDeck.gainNode.gain.cancelScheduledValues(startAt);
    nextDeck.gainNode.gain.setValueAtTime(0, startAt);
    nextDeck.gainNode.gain.linearRampToValueAtTime(1, fadeEndAt);

    this.tryApplyTempoSync({
      currentTrack,
      nextTrack,
      nextSource,
      startAt,
      fadeEndAt,
      plan
    });

    this.applyFadeOut(previousDeck, startAt, fadeEndAt);
    previousDeck.source?.stop(fadeEndAt + 0.05);

    this.emit('transition_started', `Crossfade: ${nextTrack.title}`, {
      nextTrackId: nextTrack.id,
      startAt,
      endAt: fadeEndAt,
      source: plan.source,
      nextTrackStartOffsetSec: safeNextTrackOffsetSec,
      reasoningSummary: plan.reasoningSummary
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
    this.currentTrackDurationSec = remainingDurationSec;
    this.swapDecks();

    this.emit('track_started', `Playing: ${nextTrack.title}`, {
      trackId: nextTrack.id,
      index: nextIndex
    });

    this.scheduleForCurrent(nextIndex, nextTrack, startAt, remainingDurationSec);
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
    initialGain: number,
    offsetSec = 0
  ): AudioBufferSourceNodeLike {
    this.stopDeckSource(deck, startAt);

    const source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(deck.gainNode);
    const safeOffsetSec = this.clampStartOffsetSec(buffer, offsetSec);
    source.start(startAt, safeOffsetSec);

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
    try {
      if (this.paused) {
        await this.context.resume?.();
        this.paused = false;
      }

      this.scheduler.clear();
      this.scheduleToken += 1;
      const playable = await this.resolvePlayableTrack(index, 'manual_jump');
      if (!playable) {
        this.emit('error', `${errorMessage}: no playable tracks`);
        return;
      }

      const startAt = this.context.currentTime + 0.02;
      const fadeEndAt = startAt + Math.min(this.settings.fadeDurationSec, 2);
      this.performTransition(playable.index, playable.decoded, {
        crossfadeStartAt: startAt,
        crossfadeEndAt: fadeEndAt,
        nextTrackStartOffsetSec: 0,
        source: 'rule_based',
        reasoningSummary: null,
        tempoSync: { mode: 'auto' }
      });
    } catch (error) {
      this.emit('error', errorMessage, {
        reason: this.normalizeErrorMessage(error)
      });
    }
  }

  private async decodeTrack(track: Track, timeoutMs?: number): Promise<AudioBufferLike> {
    const cached = this.decodedCache.get(track.id);
    if (cached) {
      this.resolveTrackTempo(track, cached);
      return cached;
    }

    let inFlight = this.inFlightDecode.get(track.id);
    if (!inFlight) {
      inFlight = (async () => {
        const raw = await this.readTrackBuffer(track.id);
        this.trackBufferSizeHint.set(track.id, raw.byteLength);
        const decoded = await this.context.decodeAudioData(raw);
        this.cacheDecoded(track.id, decoded);
        this.resolveTrackTempo(track, decoded);
        return decoded;
      })();
      this.inFlightDecode.set(track.id, inFlight);
      void inFlight
        .finally(() => {
          if (this.inFlightDecode.get(track.id) === inFlight) {
            this.inFlightDecode.delete(track.id);
          }
        })
        .catch(() => undefined);
    }

    if (typeof timeoutMs === 'number' && Number.isFinite(timeoutMs) && timeoutMs > 0) {
      const adaptiveTimeoutMs = this.resolveAdaptiveDecodeTimeoutMs(track, timeoutMs);
      return this.withDecodeTimeout(inFlight, track, adaptiveTimeoutMs);
    }

    return inFlight;
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

  private decodeTimeoutMsForStage(stage: RecoveryStage): number {
    if (stage === 'start') {
      return START_DECODE_TIMEOUT_MS;
    }

    if (stage === 'predecode') {
      return PREDECODE_TIMEOUT_MS;
    }

    if (stage === 'manual_jump') {
      return MANUAL_JUMP_DECODE_TIMEOUT_MS;
    }

    return RECOVERY_DECODE_TIMEOUT_MS;
  }

  private isDecodeTimeoutError(error: unknown): boolean {
    return this.normalizeErrorMessage(error).startsWith(DECODE_TIMEOUT_PREFIX);
  }

  private resolveAdaptiveDecodeTimeoutMs(track: Track, baseTimeoutMs: number): number {
    const sizeHintBytes = this.trackBufferSizeHint.get(track.id) ?? 0;
    return estimateAdaptiveDecodeTimeoutMs(
      this.settings,
      baseTimeoutMs,
      track.durationSec,
      sizeHintBytes
    );
  }

  private async withDecodeTimeout(
    decodePromise: Promise<AudioBufferLike>,
    track: Track,
    timeoutMs: number
  ): Promise<AudioBufferLike> {
    let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
    const timeoutPromise = new Promise<never>((_resolve, reject) => {
      timeoutHandle = setTimeout(() => {
        reject(new Error(`${DECODE_TIMEOUT_PREFIX}: ${track.title} (${timeoutMs}ms)`));
      }, timeoutMs);
    });

    void decodePromise.catch(() => undefined);

    try {
      return await Promise.race([decodePromise, timeoutPromise]);
    } finally {
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
      }
    }
  }

  private collectForwardIndices(startIndex: number): number[] {
    const tracks = this.queueManager.getTracks();
    if (tracks.length === 0) {
      return [];
    }

    const safeStart = Math.min(Math.max(startIndex, 0), tracks.length - 1);
    const indices: number[] = [];
    const visited = new Set<number>();
    let current: number | null = safeStart;

    while (current !== null && !visited.has(current)) {
      visited.add(current);
      indices.push(current);
      current = this.queueManager.getNextIndex(current);
    }

    return indices;
  }

  private async resolvePlayableTrack(
    startIndex: number,
    stage: RecoveryStage,
    token?: number
  ): Promise<{ index: number; track: Track; decoded: AudioBufferLike } | null> {
    const candidates = this.collectForwardIndices(startIndex);
    if (candidates.length === 0) {
      return null;
    }

    for (const candidateIndex of candidates) {
      if (token !== undefined && !this.isTokenActive(token)) {
        return null;
      }

      const isLastCandidate = candidateIndex === candidates[candidates.length - 1];
      const timeoutMs = isLastCandidate
        ? undefined
        : this.decodeTimeoutMsForStage(stage);

      const track = this.queueManager.getCurrent(candidateIndex);
      if (!track) {
        continue;
      }

      try {
        const decoded = await this.decodeTrack(track, timeoutMs);
        if (token !== undefined && !this.isTokenActive(token)) {
          return null;
        }
        return { index: candidateIndex, track, decoded };
      } catch (error) {
        this.emit('track_skipped', `Skipped unplayable track: ${track.title}`, {
          trackId: track.id,
          index: candidateIndex,
          requestedIndex: startIndex,
          stage,
          reason: this.normalizeErrorMessage(error)
        });
      }
    }

    return null;
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
    plan: TransitionExecutionPlan;
  }): void {
    if (args.plan.tempoSync.mode === 'disabled') {
      this.emit('tempo_sync_skipped', 'Tempo sync skipped', {
        reason: 'mix_plan_disabled',
        currentTrackId: args.currentTrack?.id ?? null,
        nextTrackId: args.nextTrack.id
      });
      return;
    }

    if (args.plan.tempoSync.mode === 'fixed') {
      if (!args.nextSource.playbackRate) {
        this.emit('tempo_sync_skipped', 'Tempo sync skipped', {
          reason: 'playback_rate_unavailable',
          currentTrackId: args.currentTrack?.id ?? null,
          nextTrackId: args.nextTrack.id
        });
        return;
      }

      const recoveryAt = args.fadeEndAt + TEMPO_RECOVERY_SEC;
      args.nextSource.playbackRate.cancelScheduledValues(args.startAt);
      args.nextSource.playbackRate.setValueAtTime(
        args.plan.tempoSync.targetRate,
        args.startAt
      );
      args.nextSource.playbackRate.setValueAtTime(
        args.plan.tempoSync.targetRate,
        args.fadeEndAt
      );
      args.nextSource.playbackRate.linearRampToValueAtTime(1, recoveryAt);

      this.emit('tempo_sync_applied', 'Tempo sync applied', {
        currentTrackId: args.currentTrack?.id ?? null,
        nextTrackId: args.nextTrack.id,
        currentBpm: null,
        nextBpm: null,
        currentSource: null,
        nextSource: 'mix_plan',
        targetRate: args.plan.tempoSync.targetRate,
        desiredRate: args.plan.tempoSync.targetRate,
        residualMismatchPct: null,
        recoveryAt
      });
      return;
    }

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

  private clampStartOffsetSec(buffer: AudioBufferLike, offsetSec: number): number {
    return Math.max(0, Math.min(offsetSec, Math.max(0, buffer.duration - 0.01)));
  }

  private buildRuleExecutionPlan(plan: TransitionPlan): TransitionExecutionPlan {
    return {
      crossfadeStartAt: plan.crossfadeStartAt,
      crossfadeEndAt: plan.crossfadeEndAt,
      nextTrackStartOffsetSec: 0,
      source: 'rule_based',
      reasoningSummary: null,
      tempoSync: { mode: 'auto' }
    };
  }

  private buildExecutionPlanFromMixPlan(
    currentStartAt: number,
    currentEndAt: number,
    mixPlan: MixPlan
  ): TransitionExecutionPlan {
    const now = this.context.currentTime;
    const minimumStartAt = Math.min(currentEndAt, Math.max(now + 0.02, currentStartAt));
    const desiredStartAt = currentStartAt + mixPlan.transitionStartSec;
    const desiredEndAt = currentStartAt + mixPlan.transitionEndSec;
    let crossfadeStartAt = Math.min(currentEndAt, Math.max(minimumStartAt, desiredStartAt));
    let crossfadeEndAt = Math.min(currentEndAt, Math.max(crossfadeStartAt + 0.05, desiredEndAt));

    if (crossfadeEndAt > currentEndAt) {
      crossfadeEndAt = currentEndAt;
      crossfadeStartAt = Math.min(crossfadeStartAt, Math.max(minimumStartAt, crossfadeEndAt - 0.05));
    }

    return {
      crossfadeStartAt,
      crossfadeEndAt,
      nextTrackStartOffsetSec: mixPlan.nextTrackStartOffsetSec,
      source: 'ai',
      reasoningSummary: mixPlan.reasoningSummary,
      tempoSync: mixPlan.tempoSync.enabled && mixPlan.tempoSync.targetRate !== null
        ? { mode: 'fixed', targetRate: mixPlan.tempoSync.targetRate }
        : { mode: 'disabled' }
    };
  }
}
