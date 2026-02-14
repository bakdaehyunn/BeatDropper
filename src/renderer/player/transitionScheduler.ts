import { PlayerSettings, TransitionPlan } from '../../shared/types';

type ScheduledCallback = () => void | Promise<void>;

export interface TransitionScheduleCallbacks {
  onPredecode: ScheduledCallback;
  onCrossfade: ScheduledCallback;
  onTrackEnd: ScheduledCallback;
}

export interface TransitionScheduleArgs {
  currentEndAt: number;
  plan: TransitionPlan;
  settings: PlayerSettings;
  callbacks: TransitionScheduleCallbacks;
}

export class TransitionScheduler {
  private handles: ReturnType<typeof setTimeout>[] = [];
  private readonly nowProvider: () => number;

  constructor(nowProvider: () => number = () => performance.now() / 1000) {
    this.nowProvider = nowProvider;
  }

  clear(): void {
    for (const handle of this.handles) {
      clearTimeout(handle);
    }
    this.handles = [];
  }

  scheduleAt(targetAtSec: number, callback: ScheduledCallback): void {
    const delayMs = Math.max(0, (targetAtSec - this.nowProvider()) * 1000);
    const handle = setTimeout(() => {
      void callback();
    }, delayMs);
    this.handles.push(handle);
  }

  scheduleTransition(args: TransitionScheduleArgs): void {
    this.clear();

    const predecodeAt = args.plan.crossfadeStartAt - args.settings.predecodeLeadSec;

    this.scheduleAt(predecodeAt, args.callbacks.onPredecode);
    this.scheduleAt(args.plan.crossfadeStartAt, args.callbacks.onCrossfade);
    this.scheduleAt(args.currentEndAt, args.callbacks.onTrackEnd);
  }
}
