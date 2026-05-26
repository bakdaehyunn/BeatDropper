import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const { buildPrompt, plannerSchema } = require('../../scripts/codex-mix-planner.cjs') as {
  buildPrompt: (request: Record<string, unknown>) => string;
  plannerSchema: {
    properties: {
      mixPlan: {
        anyOf: Array<{
          type: string;
          properties?: Record<string, unknown>;
          required?: string[];
        }>;
      };
    };
  };
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
      candidateId?: string | null;
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
    expect(prompt).toContain('Treat source=tail_fallback candidates as safety fallbacks');
    expect(prompt).toContain('tempoSync.targetRate is a playback-rate ratio');
  });

  it('prefers compact analysis summary evidence when present', () => {
    const prompt = buildPrompt({
      ...baseRequest,
      analysisSummary: {
        current: {
          plannerReady: true,
          bpm: 124,
          bpmConfidence: 0.86,
          analysisQuality: {
            beatGrid: 0.82,
            spectralBands: 0.78,
            transientMarkers: 0.72
          },
          analysisWarnings: [],
          beatStability: {
            score: 0.8,
            label: 'stable',
            beatGridQuality: 0.82,
            transientQuality: 0.72
          },
          cues: {
            intro: null,
            firstDownbeat: null,
            outro: {
              type: 'outro',
              startSec: 188,
              confidence: 0.82,
              label: 'Outro mix-out'
            }
          },
          energyTrend: {
            early: 0.82,
            mid: 0.48,
            late: 0.24,
            direction: 'falling'
          },
          transients: {
            count: 120,
            strongCount: 44,
            densityPerSec: 0.57
          },
          phrases: {
            phraseCount: 8,
            barCount: 32,
            strongestBoundaries: [{ startSec: 188, confidence: 0.82 }]
          }
        },
        next: {
          plannerReady: true,
          bpm: 126,
          bpmConfidence: 0.84,
          analysisQuality: {
            beatGrid: 0.8,
            spectralBands: 0.76,
            transientMarkers: 0.7
          },
          analysisWarnings: [],
          beatStability: {
            score: 0.77,
            label: 'stable',
            beatGridQuality: 0.8,
            transientQuality: 0.7
          },
          cues: {
            intro: null,
            firstDownbeat: {
              type: 'first_downbeat',
              startSec: 12,
              confidence: 0.8,
              label: 'First downbeat'
            },
            outro: null
          },
          energyTrend: {
            early: 0.32,
            mid: 0.5,
            late: 0.72,
            direction: 'rising'
          },
          transients: {
            count: 100,
            strongCount: 38,
            densityPerSec: 0.5
          },
          phrases: {
            phraseCount: 7,
            barCount: 30,
            strongestBoundaries: [{ startSec: 12, confidence: 0.8 }]
          }
        }
      }
    });

    expect(prompt).toContain('Prefer analysisSummary and pairContext');
    expect(prompt).toContain('current: plannerReady true');
    expect(prompt).toContain('beat stability stable score 0.8');
    expect(prompt).toContain('energy falling early 0.82 mid 0.48 late 0.24');
    expect(prompt).toContain('first downbeat 12.00s confidence 0.80');
  });

  it('includes user preparation hints in the codex prompt', () => {
    const prompt = buildPrompt({
      ...baseRequest,
      preparation: {
        current: {
          bpmOverride: 123.8,
          hotCues: [{ kind: 'outro', timeSec: 158, label: 'Prep outro' }]
        },
        next: {
          bpmOverride: null,
          hotCues: [{ kind: 'drop', timeSec: 32, label: 'Drop' }]
        }
      }
    });

    expect(prompt).toContain('Preparation hints:');
    expect(prompt).toContain('human intent');
    expect(prompt).toContain('current: prep BPM 123.8; Prep outro 158.00s');
    expect(prompt).toContain('next: prep BPM --; Drop 32.00s');
  });

  it('keeps the codex output schema strict-compatible for nullable mix plan fields', () => {
    const mixPlanObjectSchema = plannerSchema.properties.mixPlan.anyOf.find(
      (entry) => entry.type === 'object'
    );

    expect(mixPlanObjectSchema).toBeDefined();
    expect(mixPlanObjectSchema?.required?.sort()).toEqual(
      Object.keys(mixPlanObjectSchema?.properties ?? {}).sort()
    );
    const tempoSyncSchema = mixPlanObjectSchema?.properties?.tempoSync as
      | {
          properties?: {
            targetRate?: {
              anyOf?: Array<{ type: string; minimum?: number; maximum?: number }>;
            };
          };
        }
      | undefined;
    const targetRateNumberSchema = tempoSyncSchema?.properties?.targetRate?.anyOf?.find(
      (entry) => entry.type === 'number'
    );
    expect(targetRateNumberSchema).toMatchObject({ minimum: 0.85, maximum: 1.15 });
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

  it('does not promote tail fallback candidates as selected AI candidates', () => {
    const response = buildHeuristicResponse({
      ...baseRequest,
      pairContext: {
        readiness: 'analysis_pending',
        recommendedCandidateId: null,
        candidates: [
          {
            id: 'tail:current-track:20200->next-track:0',
            source: 'tail_fallback',
            evidenceLevel: 'fallback',
            requiresAnalysisUpgrade: true,
            currentMixOutSec: 202,
            nextMixInSec: 0,
            score: 0.38,
            style: 'smooth_blend',
            reason: 'tail fallback only'
          }
        ]
      }
    });

    expect(response.mixPlan.candidateId).toBeNull();
    expect(response.mixPlan.reasoningSummary).toContain('readiness analysis_pending');
  });
});
