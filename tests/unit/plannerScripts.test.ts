import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const { buildPrompt } = require('../../scripts/codex-mix-planner.cjs') as {
  buildPrompt: (request: Record<string, unknown>) => string;
};

const { buildHeuristicResponse } = require('../../scripts/heuristic-mix-planner.cjs') as {
  buildHeuristicResponse: (request: Record<string, unknown>) => {
    schemaVersion: number;
    error: string | null;
    mixPlan: {
      transitionStartSec: number;
      transitionEndSec: number;
      nextTrackStartOffsetSec: number;
      style: string;
      confidence: number;
      reasoningSummary: string | null;
      tempoSync: {
        enabled: boolean;
        targetRate: number | null;
      };
    };
  };
};

const baseRequest = {
  currentTrack: {
    id: 'current-track',
    title: 'Current Track',
    durationSec: 210,
    bpm: 124
  },
  nextTrack: {
    id: 'next-track',
    title: 'Next Track',
    durationSec: 200,
    bpm: 126
  },
  currentPlayback: {
    elapsedSec: 176
  },
  analysis: {
    current: {
      outroCueSec: 188,
      downbeatsSec: [172, 176, 180, 184, 188],
      beatGridSec: [171, 173, 175, 177, 179, 181, 183, 185, 187]
    },
    next: {
      introCueSec: 12,
      downbeatsSec: [0, 4, 8, 12, 16],
      beatGridSec: [0, 2, 4, 6, 8, 10, 12]
    }
  },
  settings: {
    fadeDurationSec: 8,
    aiDjMode: 'balanced'
  }
};

describe('planner scripts', () => {
  it('builds a codex prompt with mode guidance and cue-aware rules', () => {
    const prompt = buildPrompt(baseRequest);

    expect(prompt).toContain('Mode policy: balanced.');
    expect(prompt).toContain('Prefer aligning transition timing to outro cues, downbeats, or beat-grid points');
    expect(prompt).toContain('Prefer starting the next track from intro cue');
    expect(prompt).toContain('Analysis hints:');
  });

  it('includes distinct mode guidance in the codex prompt', () => {
    const safePrompt = buildPrompt({
      ...baseRequest,
      settings: { ...baseRequest.settings, aiDjMode: 'safe' }
    });
    const adventurousPrompt = buildPrompt({
      ...baseRequest,
      settings: { ...baseRequest.settings, aiDjMode: 'adventurous' }
    });

    expect(safePrompt).toContain('Mode policy: safe.');
    expect(safePrompt).toContain('Avoid hard_cut unless no safe overlap exists.');
    expect(adventurousPrompt).toContain('Mode policy: adventurous.');
    expect(adventurousPrompt).toContain('Shorter transitions are acceptable');
  });

  it('builds a safe heuristic plan with cue-aware offset and smooth blend style', () => {
    const response = buildHeuristicResponse({
      ...baseRequest,
      settings: {
        fadeDurationSec: 8,
        aiDjMode: 'safe'
      }
    });

    expect(response.error).toBeNull();
    expect(response.mixPlan.style).toBe('smooth_blend');
    expect(response.mixPlan.nextTrackStartOffsetSec).toBe(12);
    expect(response.mixPlan.transitionStartSec).toBeGreaterThanOrEqual(176);
    expect(response.mixPlan.transitionEndSec).toBeLessThanOrEqual(188);
    expect(response.mixPlan.reasoningSummary).toContain('Mode safe');
  });

  it('builds an adventurous heuristic plan that can choose a harder transition policy', () => {
    const response = buildHeuristicResponse({
      ...baseRequest,
      nextTrack: {
        ...baseRequest.nextTrack,
        bpm: 144
      },
      analysis: {
        current: {
          outroCueSec: null,
          downbeatsSec: [],
          beatGridSec: []
        },
        next: {
          introCueSec: null,
          downbeatsSec: [],
          beatGridSec: []
        }
      },
      settings: {
        fadeDurationSec: 8,
        aiDjMode: 'adventurous'
      }
    });

    expect(response.mixPlan.style).toBe('hard_cut');
    expect(response.mixPlan.tempoSync.enabled).toBe(false);
    expect(response.mixPlan.reasoningSummary).toContain('Mode adventurous');
  });

  it('differentiates heuristic policy across safe, balanced, and adventurous modes', () => {
    const safe = buildHeuristicResponse({
      ...baseRequest,
      settings: { ...baseRequest.settings, aiDjMode: 'safe' }
    });
    const balanced = buildHeuristicResponse({
      ...baseRequest,
      settings: { ...baseRequest.settings, aiDjMode: 'balanced' }
    });
    const adventurous = buildHeuristicResponse({
      ...baseRequest,
      settings: { ...baseRequest.settings, aiDjMode: 'adventurous' }
    });

    expect(safe.mixPlan.style).toBe('smooth_blend');
    expect(balanced.mixPlan.style).toBe('smooth_blend');
    expect(adventurous.mixPlan.style).toBe('energy_swap');
    expect(safe.mixPlan.transitionStartSec).toBeLessThan(balanced.mixPlan.transitionStartSec);
    expect(balanced.mixPlan.transitionStartSec).toBeLessThan(adventurous.mixPlan.transitionStartSec);
  });
});
