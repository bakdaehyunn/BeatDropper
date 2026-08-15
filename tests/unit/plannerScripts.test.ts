import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const { buildPrompt, buildPromptRequest, plannerSchema } = require('../../scripts/codex-mix-planner.cjs') as {
  buildPrompt: (request: Record<string, unknown>) => string;
  buildPromptRequest: (request: Record<string, unknown>) => Record<string, unknown>;
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
      mixControls?: {
        gain: {
          outgoingTrimDb: number | null;
          incomingTrimDb: number | null;
        };
        eq: Record<string, number | null>;
        clipProtection: {
          enabled: boolean;
          mode: string;
          ceilingDb: number | null;
        };
        qualityNotes: string[];
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

const buildLargeAnalysis = (trackId: string) => ({
  schemaVersion: 6,
  trackId,
  generatedAt: '2026-05-29T00:00:00Z',
  source: 'native_dsp',
  bpm: 124,
  bpmConfidence: 0.82,
  beatGridSec: Array.from({ length: 800 }, (_, index) => index * 0.48),
  downbeatsSec: Array.from({ length: 200 }, (_, index) => index * 1.92),
  barGrid: Array.from({ length: 200 }, (_, index) => ({
    index,
    startSec: index * 1.92,
    confidence: 0.74
  })),
  phraseMarkers: Array.from({ length: 25 }, (_, index) => ({
    index,
    startSec: index * 15.36,
    bars: 8,
    confidence: 0.7
  })),
  introCueSec: 12,
  outroCueSec: 188,
  energyProfile: Array.from({ length: 64 }, (_, index) => index / 64),
  waveformPeaks: Array.from({ length: 240 }, (_, index) => ({
    startSec: index,
    endSec: index + 1,
    peak: 0.4,
    rms: 0.2
  })),
  waveformDetail: Array.from({ length: 1200 }, (_, index) => ({
    startSec: index * 0.2,
    endSec: index * 0.2 + 0.2,
    low: 0.2,
    mid: 0.3,
    high: 0.1,
    peak: 0.5,
    rms: 0.25
  })),
  spectralBands: Array.from({ length: 512 }, (_, index) => ({
    timeSec: index * 0.1,
    low: 0.2,
    mid: 0.3,
    high: 0.4
  })),
  transientMarkers: Array.from({ length: 180 }, (_, index) => ({
    timeSec: index * 0.5,
    strength: 0.7,
    band: 'mid',
    beatIndex: index
  })),
  cueCandidates: [
    {
      id: `${trackId}-outro`,
      type: 'outro',
      startSec: 188,
      endSec: 196,
      confidence: 0.83,
      label: 'Outro mix-out'
    }
  ],
  analysisConfidence: 0.78,
  analysisQuality: {
    beatGrid: 0.82,
    spectralBands: 0.78,
    transientMarkers: 0.76
  },
  analysisWarnings: ['beat_grid_estimated']
});

describe('planner scripts', () => {
  it('builds a codex prompt with mode guidance and cue-aware rules', () => {
    const prompt = buildPrompt(baseRequest);

    expect(prompt).toContain('Mode policy: balanced.');
    expect(prompt).toContain('Prefer aligning transition timing to outro cues, downbeats, or beat-grid points');
    expect(prompt).toContain('Prefer starting the next track from intro cue');
    expect(prompt).toContain('Analysis hints:');
    expect(prompt).toContain('Treat source=tail_fallback candidates as safety fallbacks');
    expect(prompt).toContain('tempoSync.targetRate is a playback-rate ratio');
    expect(prompt).toContain('mixControls is executed deterministically by the native audio engine');
    expect(prompt).toContain('Do not request realtime AI control');
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
          },
          mixWindows: {
            mixIn: [],
            mixOut: [
              {
                kind: 'outro',
                source: 'cue',
                startSec: 188,
                endSec: 196,
                confidence: 0.82,
                label: 'Outro mix-out'
              }
            ]
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
          },
          mixWindows: {
            mixIn: [
              {
                kind: 'first_downbeat',
                source: 'cue',
                startSec: 12,
                endSec: 20,
                confidence: 0.8,
                label: 'First downbeat'
              }
            ],
            mixOut: []
          }
        }
      }
    });

    expect(prompt).toContain('Prefer analysisSummary and pairContext');
    expect(prompt).toContain('current: plannerReady true');
    expect(prompt).toContain('beat stability stable score 0.8');
    expect(prompt).toContain('energy falling early 0.82 mid 0.48 late 0.24');
    expect(prompt).toContain('out outro 188.00-196.00s confidence 0.82');
    expect(prompt).toContain('in first_downbeat 12.00-20.00s confidence 0.80');
    expect(prompt).toContain('first downbeat 12.00s confidence 0.80');
  });

  it('compacts heavy TrackAnalysis arrays before building the codex prompt', () => {
    const promptRequest = buildPromptRequest({
      ...baseRequest,
      analysis: {
        current: buildLargeAnalysis('current-track'),
        next: buildLargeAnalysis('next-track')
      },
      pairContext: {
        currentTrackId: 'current-track',
        nextTrackId: 'next-track',
        recommendedCandidateId: 'analysis:candidate',
        readiness: 'ready',
        candidates: [
          {
            id: 'analysis:candidate',
            currentTrackId: 'current-track',
            nextTrackId: 'next-track',
            source: 'analysis',
            evidenceLevel: 'strong',
            requiresAnalysisUpgrade: false,
            currentMixOutSec: 188,
            nextMixInSec: 12,
            currentBarIndex: 96,
            nextBarIndex: 8,
            phraseAlignment: 'aligned',
            bpmDelta: 2,
            tempoSyncRate: 0.98,
            energyDelta: 0.12,
            style: 'smooth_blend',
            score: 0.86,
            confidence: 0.82,
            reason: 'analysis phrase candidate'
          }
        ]
      }
    }) as any;

    expect(promptRequest.analysis.current.waveformDetail).toBeUndefined();
    expect(promptRequest.analysis.current.waveformPeaks).toBeUndefined();
    expect(promptRequest.analysis.current.spectralBands).toBeUndefined();
    expect(promptRequest.analysis.current.transientMarkers).toBeUndefined();
    expect(promptRequest.analysis.current.beatGridSec).toBeUndefined();
    expect(promptRequest.analysis.current.counts.waveformDetail).toBe(1200);
    expect(promptRequest.analysis.current.counts.spectralBands).toBe(512);
    expect(promptRequest.analysis.current.counts.transientMarkers).toBe(180);
    expect(promptRequest.analysis.current.cueCandidates).toHaveLength(1);
    expect(promptRequest.pairContext.candidates).toHaveLength(1);
  });

  it('keeps the codex prompt bounded for large analysis payloads', () => {
    const prompt = buildPrompt({
      ...baseRequest,
      analysis: {
        current: buildLargeAnalysis('current-track'),
        next: buildLargeAnalysis('next-track')
      }
    });

    expect(Buffer.byteLength(prompt, 'utf8')).toBeLessThan(30000);
    expect(prompt).toContain('Raw DSP arrays are intentionally omitted');
    expect(prompt).toContain('"waveformDetail": 1200');
    expect(prompt).not.toContain('"waveformDetail": [');
    expect(prompt).not.toContain('"spectralBands": [');
    expect(prompt).not.toContain('"transientMarkers": [');
    expect(prompt).not.toContain('"peak": 0.5');
    expect(prompt).not.toContain('"strength": 0.7');
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
    const optionalFields = ['mixControls'];
    expect(mixPlanObjectSchema?.required?.sort()).toEqual(
      Object.keys(mixPlanObjectSchema?.properties ?? {})
        .filter((key) => !optionalFields.includes(key))
        .sort()
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

    const mixControlsSchema = mixPlanObjectSchema?.properties?.mixControls as
      | {
          anyOf?: Array<{
            type: string;
            properties?: {
              gain?: {
                properties?: {
                  incomingTrimDb?: {
                    anyOf?: Array<{ type: string; minimum?: number; maximum?: number }>;
                  };
                };
              };
            };
          }>;
        }
      | undefined;
    const mixControlsObjectSchema = mixControlsSchema?.anyOf?.find((entry) => entry.type === 'object');
    const incomingTrimNumberSchema = mixControlsObjectSchema?.properties?.gain?.properties
      ?.incomingTrimDb?.anyOf?.find((entry) => entry.type === 'number');
    expect(incomingTrimNumberSchema).toMatchObject({ minimum: -12, maximum: 6 });
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
    expect(response.mixPlan.mixControls?.clipProtection.mode).toBe('monitor_only');
    expect(response.mixPlan.mixControls?.gain.incomingTrimDb).toBe(-2);
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
    expect(response.mixPlan.mixControls?.gain.incomingTrimDb).toBe(-1);
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
