import {
  MIX_PLAN_EXPORT_SCHEMA_VERSION,
  MIX_PLAN_PLANNER_PRESET_DESCRIPTIONS,
  buildMixPlanExportContext,
  buildMixPlanExportEnvelope,
  buildMixPlanExportMetadata,
  parseMixPlanExportJson
} from '../../src/shared/mixPlanExport';

describe('mixPlanExport helpers', () => {
  const planner = {
    preset: 'codex' as const,
    presetLabel: MIX_PLAN_PLANNER_PRESET_DESCRIPTIONS.codex,
    source: 'cli',
    command: 'node',
    args: ['scripts/codex-mix-planner.cjs'],
    timeoutMs: 20000,
    plannerResponseSchemaVersion: 1
  };
  const context = buildMixPlanExportContext({
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
      current: {
        schemaVersion: 1,
        trackId: 'track-a',
        generatedAt: '2026-04-25T06:00:00.000Z',
        source: 'derived',
        bpm: 124,
        beatGridSec: [0, 0.48],
        downbeatsSec: [0],
        introCueSec: 0,
        outroCueSec: 184,
        energyProfile: [0.4, 0.7],
        analysisConfidence: 0.81
      },
      next: null
    }
  });

  it('builds export metadata with the shared schema version', () => {
    expect(buildMixPlanExportMetadata(planner)).toEqual({
      exportSchemaVersion: MIX_PLAN_EXPORT_SCHEMA_VERSION,
      planner
    });
  });

  it('builds an envelope with planner metadata and the provided mix plan', () => {
    expect(
      buildMixPlanExportEnvelope({
        planner,
        context,
        exportedAt: '2026-04-25T06:00:00.000Z',
        mixPlan: {
          transitionStartSec: 180,
          transitionEndSec: 188,
          nextTrackStartOffsetSec: 12,
          style: 'smooth_blend',
          confidence: 0.82,
          reasoningSummary: 'Start at the next stable outro phrase.',
          tempoSync: {
            enabled: true,
            targetRate: 0.988
          }
        }
      })
    ).toEqual({
      exportSchemaVersion: MIX_PLAN_EXPORT_SCHEMA_VERSION,
      exportedAt: '2026-04-25T06:00:00.000Z',
      planner,
      context,
      mixPlan: {
        transitionStartSec: 180,
        transitionEndSec: 188,
        nextTrackStartOffsetSec: 12,
        style: 'smooth_blend',
        confidence: 0.82,
        reasoningSummary: 'Start at the next stable outro phrase.',
        tempoSync: {
          enabled: true,
          targetRate: 0.988
        }
      }
    });
  });

  it('parses a valid export envelope JSON payload', () => {
    const payload = JSON.stringify(
      buildMixPlanExportEnvelope({
        planner,
        context,
        exportedAt: '2026-04-25T06:00:00.000Z',
        mixPlan: {
          transitionStartSec: 180,
          transitionEndSec: 188,
          nextTrackStartOffsetSec: 12,
          style: 'smooth_blend',
          confidence: 0.82,
          reasoningSummary: 'Start at the next stable outro phrase.',
          tempoSync: {
            enabled: true,
            targetRate: 0.988
          }
        }
      })
    );

    expect(parseMixPlanExportJson(payload)).toEqual({
      envelope: {
        exportSchemaVersion: MIX_PLAN_EXPORT_SCHEMA_VERSION,
        exportedAt: '2026-04-25T06:00:00.000Z',
        planner,
        context,
        mixPlan: {
          transitionStartSec: 180,
          transitionEndSec: 188,
          nextTrackStartOffsetSec: 12,
          style: 'smooth_blend',
          confidence: 0.82,
          reasoningSummary: 'Start at the next stable outro phrase.',
          tempoSync: {
            enabled: true,
            targetRate: 0.988
          }
        }
      },
      reason: null
    });
  });

  it('rejects malformed export envelopes', () => {
    expect(parseMixPlanExportJson('{')).toEqual({
      envelope: null,
      reason: 'mix_plan_export_invalid_json'
    });

    expect(
      parseMixPlanExportJson(
        JSON.stringify({
          exportSchemaVersion: 99,
          exportedAt: '2026-04-25T06:00:00.000Z',
          planner,
          mixPlan: {
            transitionStartSec: 180,
            transitionEndSec: 188,
            nextTrackStartOffsetSec: 12,
            style: 'smooth_blend',
            confidence: 0.82,
            reasoningSummary: 'x',
            tempoSync: {
              enabled: true,
              targetRate: 0.988
            }
          }
        })
      )
    ).toEqual({
      envelope: null,
      reason: 'mix_plan_export_invalid_schema_version'
    });
  });

  it('keeps old export files readable when context is missing', () => {
    expect(
      parseMixPlanExportJson(
        JSON.stringify({
          exportSchemaVersion: 1,
          exportedAt: '2026-04-25T06:00:00.000Z',
          planner,
          mixPlan: {
            transitionStartSec: 180,
            transitionEndSec: 188,
            nextTrackStartOffsetSec: 12,
            style: 'smooth_blend',
            confidence: 0.82,
            reasoningSummary: 'x',
            tempoSync: {
              enabled: true,
              targetRate: 0.988
            }
          }
        })
      )
    ).toEqual({
      envelope: {
        exportSchemaVersion: 1,
        exportedAt: '2026-04-25T06:00:00.000Z',
        planner,
        context: null,
        mixPlan: {
          transitionStartSec: 180,
          transitionEndSec: 188,
          nextTrackStartOffsetSec: 12,
          style: 'smooth_blend',
          confidence: 0.82,
          reasoningSummary: 'x',
          tempoSync: {
            enabled: true,
            targetRate: 0.988
          }
        }
      },
      reason: null
    });
  });
});
