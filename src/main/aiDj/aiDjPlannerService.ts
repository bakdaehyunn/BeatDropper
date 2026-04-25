import { MixPlan, validateAndClampMixPlan } from '../../shared/mixPlan';
import {
  PlannerRequest,
  PlannerResponse,
  RequestMixPlanInput,
  RequestMixPlanResult,
  buildPlannerRequest,
  isPlannerCommandConfigured,
  toPlannerCliConfig
} from '../../shared/plannerContract';
import { sanitizeSettings } from '../../shared/settings';
import { PlayerSettings } from '../../shared/types';
import { TrackAnalysis } from '../../shared/analysis';
import { CliPlannerAdapter } from './cliPlannerAdapter';

interface AiDjPlannerServiceDeps {
  analysisService: {
    getTrackAnalysis(trackId: string): Promise<TrackAnalysis | null>;
  };
  settingsProvider: () => Promise<PlayerSettings>;
  cliAdapter?: {
    execute(config: ReturnType<typeof toPlannerCliConfig>, request: PlannerRequest): Promise<PlannerResponse>;
  };
}

export class AiDjPlannerService {
  private readonly analysisService: AiDjPlannerServiceDeps['analysisService'];
  private readonly settingsProvider: AiDjPlannerServiceDeps['settingsProvider'];
  private readonly cliAdapter: NonNullable<AiDjPlannerServiceDeps['cliAdapter']>;

  constructor(deps: AiDjPlannerServiceDeps) {
    this.analysisService = deps.analysisService;
    this.settingsProvider = deps.settingsProvider;
    this.cliAdapter = deps.cliAdapter ?? new CliPlannerAdapter();
  }

  async getTrackAnalysis(trackId: string): Promise<TrackAnalysis | null> {
    return this.analysisService.getTrackAnalysis(trackId);
  }

  async requestMixPlan(input: RequestMixPlanInput): Promise<RequestMixPlanResult> {
    const settings = sanitizeSettings({
      ...(await this.settingsProvider()),
      ...(input.settingsOverride ?? {})
    });
    const elapsedSec = Math.min(
      Math.max(0, input.currentPlayback.elapsedSec),
      input.currentTrack.durationSec
    );

    const [currentAnalysis, nextAnalysis] = await Promise.all([
      this.analysisService.getTrackAnalysis(input.currentTrack.id),
      this.analysisService.getTrackAnalysis(input.nextTrack.id)
    ]);

    const request = buildPlannerRequest({
      currentTrack: input.currentTrack,
      nextTrack: input.nextTrack,
      elapsedSec,
      currentAnalysis,
      nextAnalysis,
      settings
    });

    if (!settings.aiDjEnabled) {
      return {
        plan: null,
        source: 'fallback',
        reason: 'ai_dj_disabled',
        request,
        response: null,
        analysis: { current: currentAnalysis, next: nextAnalysis }
      };
    }

    if (!isPlannerCommandConfigured(settings)) {
      return {
        plan: null,
        source: 'fallback',
        reason: 'planner_command_missing',
        request,
        response: null,
        analysis: { current: currentAnalysis, next: nextAnalysis }
      };
    }

    try {
      const response = await this.cliAdapter.execute(toPlannerCliConfig(settings), request);
      if (response.mixPlan === null) {
        return {
          plan: null,
          source: 'fallback',
          reason: response.error ?? 'planner_returned_no_plan',
          request,
          response,
          analysis: { current: currentAnalysis, next: nextAnalysis }
        };
      }

      const validated = validateAndClampMixPlan(response.mixPlan, {
        currentPlaybackElapsedSec: elapsedSec,
        currentTrackDurationSec: input.currentTrack.durationSec,
        nextTrackDurationSec: input.nextTrack.durationSec,
        maxFadeDurationSec: settings.fadeDurationSec
      });

      if (!validated.plan) {
        return {
          plan: null,
          source: 'fallback',
          reason: validated.reason,
          request,
          response,
          analysis: { current: currentAnalysis, next: nextAnalysis }
        };
      }

      return {
        plan: validated.plan,
        source: 'cli',
        reason: null,
        request,
        response,
        analysis: { current: currentAnalysis, next: nextAnalysis }
      };
    } catch (error) {
      return {
        plan: null,
        source: 'fallback',
        reason: error instanceof Error ? error.message : String(error),
        request,
        response: null,
        analysis: { current: currentAnalysis, next: nextAnalysis }
      };
    }
  }
}
