import {
  MIX_PLAN_COMPARISON_EXPORT_SCHEMA_VERSION,
  buildMixPlanComparisonExportEnvelope,
  buildMixPlanComparisonRows,
  parseMixPlanComparisonExportJson
} from '../../src/shared/mixPlanComparison';

describe('mixPlanComparison helpers', () => {
  const primary = {
    id: 'artifact-a',
    label: 'Artifact A',
    summary: 'Codex · cli',
    context: {
      currentTrack: {
        id: 'track-a',
        title: 'Track A',
        durationSec: 210,
        bpm: 124
      },
      nextTrack: {
        id: 'track-b',
        title: 'Track B',
        durationSec: 205,
        bpm: 126
      },
      analysis: {
        current: null,
        next: null
      }
    },
    mixPlan: {
      transitionStartSec: 180,
      transitionEndSec: 188,
      nextTrackStartOffsetSec: 12,
      style: 'smooth_blend' as const,
      confidence: 0.82,
      reasoningSummary: 'A',
      tempoSync: {
        enabled: true,
        targetRate: 0.988
      }
    }
  };

  const target = {
    id: 'artifact-b',
    label: 'Artifact B',
    summary: 'Heuristic · cli',
    context: null,
    mixPlan: {
      transitionStartSec: 176,
      transitionEndSec: 184,
      nextTrackStartOffsetSec: 8,
      style: 'energy_swap' as const,
      confidence: 0.71,
      reasoningSummary: 'B',
      tempoSync: {
        enabled: false,
        targetRate: null
      }
    }
  };

  it('builds pairwise comparison rows', () => {
    expect(buildMixPlanComparisonRows({ primary, target })).toEqual([
      {
        label: 'Transition start',
        primary: '180.00s',
        target: '176.00s',
        delta: '+4.00s'
      },
      {
        label: 'Transition end',
        primary: '188.00s',
        target: '184.00s',
        delta: '+4.00s'
      },
      {
        label: 'Next-track offset',
        primary: '12.00s',
        target: '8.00s',
        delta: '+4.00s'
      },
      {
        label: 'Style',
        primary: 'smooth_blend',
        target: 'energy_swap',
        delta: 'changed'
      },
      {
        label: 'Tempo sync',
        primary: '0.988x',
        target: 'off',
        delta: 'changed'
      },
      {
        label: 'Confidence',
        primary: '0.82',
        target: '0.71',
        delta: '+0.11'
      }
    ]);
  });

  it('builds a comparison export envelope', () => {
    expect(
      buildMixPlanComparisonExportEnvelope({
        primary,
        target,
        exportedAt: '2026-04-25T06:00:00.000Z'
      })
    ).toEqual({
      exportSchemaVersion: MIX_PLAN_COMPARISON_EXPORT_SCHEMA_VERSION,
      exportedAt: '2026-04-25T06:00:00.000Z',
      comparison: {
        primary: {
          id: 'artifact-a',
          label: 'Artifact A',
          summary: 'Codex · cli',
          context: {
            currentTrack: {
              id: 'track-a',
              title: 'Track A',
              durationSec: 210,
              bpm: 124
            },
            nextTrack: {
              id: 'track-b',
              title: 'Track B',
              durationSec: 205,
              bpm: 126
            },
            analysis: {
              current: null,
              next: null
            }
          }
        },
        target: {
          id: 'artifact-b',
          label: 'Artifact B',
          summary: 'Heuristic · cli',
          context: null
        },
        rows: buildMixPlanComparisonRows({ primary, target })
      }
    });
  });

  it('parses a valid comparison export envelope and keeps missing context backward-compatible', () => {
    expect(
      parseMixPlanComparisonExportJson(
        JSON.stringify({
          exportSchemaVersion: 1,
          exportedAt: '2026-04-25T06:00:00.000Z',
          comparison: {
            primary: {
              id: 'artifact-a',
              label: 'Artifact A',
              summary: 'Codex · cli'
            },
            target: {
              id: 'artifact-b',
              label: 'Artifact B',
              summary: 'Heuristic · cli',
              context: null
            },
            rows: buildMixPlanComparisonRows({ primary, target })
          }
        })
      )
    ).toEqual({
      envelope: {
        exportSchemaVersion: 1,
        exportedAt: '2026-04-25T06:00:00.000Z',
        comparison: {
          primary: {
            id: 'artifact-a',
            label: 'Artifact A',
            summary: 'Codex · cli',
            context: null
          },
          target: {
            id: 'artifact-b',
            label: 'Artifact B',
            summary: 'Heuristic · cli',
            context: null
          },
          rows: buildMixPlanComparisonRows({ primary, target })
        }
      },
      reason: null
    });
  });

  it('rejects malformed comparison export envelopes', () => {
    expect(parseMixPlanComparisonExportJson('{')).toEqual({
      envelope: null,
      reason: 'mix_plan_comparison_invalid_json'
    });

    expect(
      parseMixPlanComparisonExportJson(
        JSON.stringify({
          exportSchemaVersion: 99,
          exportedAt: '2026-04-25T06:00:00.000Z',
          comparison: {}
        })
      )
    ).toEqual({
      envelope: null,
      reason: 'mix_plan_comparison_invalid_schema_version'
    });
  });
});
