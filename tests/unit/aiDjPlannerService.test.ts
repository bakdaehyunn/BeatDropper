import { AiDjPlannerService } from '../../src/main/aiDj/aiDjPlannerService';
import { DEFAULT_SETTINGS } from '../../src/shared/settings';
import { Track } from '../../src/shared/types';

const currentTrack: Track = {
  id: 'track-1',
  title: 'Track 1',
  durationSec: 200,
  format: 'mp3',
  bpm: 124
};

const nextTrack: Track = {
  id: 'track-2',
  title: 'Track 2',
  durationSec: 220,
  format: 'mp3',
  bpm: 128
};

describe('AiDjPlannerService', () => {
  it('falls back when ai dj is disabled', async () => {
    const service = new AiDjPlannerService({
      analysisService: {
        getTrackAnalysis: vi.fn().mockResolvedValue(null)
      },
      settingsProvider: async () => DEFAULT_SETTINGS,
      cliAdapter: {
        execute: vi.fn()
      }
    });

    const result = await service.requestMixPlan({
      currentTrack,
      nextTrack,
      currentPlayback: {
        elapsedSec: 180
      }
    });

    expect(result.source).toBe('fallback');
    expect(result.reason).toBe('ai_dj_disabled');
    expect(result.plan).toBeNull();
  });

  it('returns fallback when cli output produces an invalid transition window', async () => {
    const service = new AiDjPlannerService({
      analysisService: {
        getTrackAnalysis: vi.fn().mockResolvedValue(null)
      },
      settingsProvider: async () => ({
        ...DEFAULT_SETTINGS,
        aiDjEnabled: true,
        plannerCommand: 'codex',
        plannerArgs: ['exec'],
        plannerTimeoutMs: 1500
      }),
      cliAdapter: {
        execute: vi.fn().mockResolvedValue({
          schemaVersion: 1,
          mixPlan: {
            transitionStartSec: 199.99,
            transitionEndSec: 200,
            nextTrackStartOffsetSec: 0,
            style: 'hard_cut',
            confidence: 0.9,
            reasoningSummary: null,
            tempoSync: {
              enabled: false,
              targetRate: null
            }
          },
          error: null
        })
      }
    });

    const result = await service.requestMixPlan({
      currentTrack,
      nextTrack,
      currentPlayback: {
        elapsedSec: 199.97
      }
    });

    expect(result.source).toBe('fallback');
    expect(result.reason).toBe('mix_plan_window_too_small');
  });

  it('executes the active ai agent profile instead of stale legacy planner fields', async () => {
    const execute = vi.fn().mockResolvedValue({
      schemaVersion: 1,
      mixPlan: {
        transitionStartSec: 180,
        transitionEndSec: 188,
        nextTrackStartOffsetSec: 4,
        style: 'smooth_blend',
        confidence: 0.82,
        reasoningSummary: 'test profile selected',
        tempoSync: {
          enabled: false,
          targetRate: null
        }
      },
      error: null
    });
    const service = new AiDjPlannerService({
      analysisService: {
        getTrackAnalysis: vi.fn().mockResolvedValue(null)
      },
      settingsProvider: async () => ({
        ...DEFAULT_SETTINGS,
        aiDjEnabled: true,
        activeAiAgentProfileId: 'test-agent',
        aiAgentProfiles: [
          ...DEFAULT_SETTINGS.aiAgentProfiles,
          {
            id: 'test-agent',
            name: 'Test Agent',
            kind: 'cli',
            command: 'node',
            args: ['scripts/test-agent.cjs'],
            timeoutMs: 1200,
            enabled: true
          }
        ],
        plannerCommand: 'stale',
        plannerArgs: ['legacy'],
        plannerTimeoutMs: 9999
      }),
      cliAdapter: {
        execute
      }
    });

    const result = await service.requestMixPlan({
      currentTrack,
      nextTrack,
      currentPlayback: {
        elapsedSec: 120
      }
    });

    expect(result.source).toBe('cli');
    expect(execute).toHaveBeenCalledWith(
      expect.objectContaining({
        command: 'node',
        args: ['scripts/test-agent.cjs'],
        timeoutMs: 1200,
        profileId: 'test-agent',
        profileName: 'Test Agent'
      }),
      expect.any(Object)
    );
  });
});
