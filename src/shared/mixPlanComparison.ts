import { MixPlan } from './mixPlan';
import {
  MixPlanExportContext,
  parseMixPlanExportContextFromUnknown
} from './mixPlanExport';

export const MIX_PLAN_COMPARISON_EXPORT_SCHEMA_VERSION = 1;

export interface MixPlanComparisonSubject {
  id: string;
  label: string;
  summary: string;
  mixPlan: MixPlan;
  context?: MixPlanExportContext | null;
}

export interface MixPlanComparisonRow {
  label: string;
  primary: string;
  target: string;
  delta: string;
}

export interface MixPlanComparisonExportEnvelope {
  exportSchemaVersion: typeof MIX_PLAN_COMPARISON_EXPORT_SCHEMA_VERSION;
  exportedAt: string;
  comparison: {
    primary: Omit<MixPlanComparisonSubject, 'mixPlan'>;
    target: Omit<MixPlanComparisonSubject, 'mixPlan'>;
    rows: MixPlanComparisonRow[];
  };
}

export interface ParseMixPlanComparisonExportResult {
  envelope: MixPlanComparisonExportEnvelope | null;
  reason: string | null;
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null && !Array.isArray(value);
};

const isString = (value: unknown): value is string => typeof value === 'string';

const parseMixPlanComparisonRow = (value: unknown): MixPlanComparisonRow | null => {
  if (!isRecord(value)) {
    return null;
  }

  if (
    !isString(value.label) ||
    !isString(value.primary) ||
    !isString(value.target) ||
    !isString(value.delta)
  ) {
    return null;
  }

  return {
    label: value.label,
    primary: value.primary,
    target: value.target,
    delta: value.delta
  };
};

const parseMixPlanComparisonSubjectMeta = (
  value: unknown
): Omit<MixPlanComparisonSubject, 'mixPlan'> | null => {
  if (!isRecord(value) || !isString(value.id) || !isString(value.label) || !isString(value.summary)) {
    return null;
  }

  return {
    id: value.id,
    label: value.label,
    summary: value.summary,
    context: parseMixPlanExportContextFromUnknown(value.context)
  };
};

const formatSigned = (value: number, suffix = ''): string => {
  const sign = value > 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}${suffix}`;
};

const formatTempo = (value: number | null): string => {
  return value === null ? 'off' : `${value.toFixed(3)}x`;
};

export const buildMixPlanComparisonRows = (input: {
  primary: MixPlanComparisonSubject;
  target: MixPlanComparisonSubject;
}): MixPlanComparisonRow[] => {
  return [
    {
      label: 'Transition start',
      primary: `${input.primary.mixPlan.transitionStartSec.toFixed(2)}s`,
      target: `${input.target.mixPlan.transitionStartSec.toFixed(2)}s`,
      delta: formatSigned(
        input.primary.mixPlan.transitionStartSec - input.target.mixPlan.transitionStartSec,
        's'
      )
    },
    {
      label: 'Transition end',
      primary: `${input.primary.mixPlan.transitionEndSec.toFixed(2)}s`,
      target: `${input.target.mixPlan.transitionEndSec.toFixed(2)}s`,
      delta: formatSigned(
        input.primary.mixPlan.transitionEndSec - input.target.mixPlan.transitionEndSec,
        's'
      )
    },
    {
      label: 'Next-track offset',
      primary: `${input.primary.mixPlan.nextTrackStartOffsetSec.toFixed(2)}s`,
      target: `${input.target.mixPlan.nextTrackStartOffsetSec.toFixed(2)}s`,
      delta: formatSigned(
        input.primary.mixPlan.nextTrackStartOffsetSec -
          input.target.mixPlan.nextTrackStartOffsetSec,
        's'
      )
    },
    {
      label: 'Style',
      primary: input.primary.mixPlan.style,
      target: input.target.mixPlan.style,
      delta:
        input.primary.mixPlan.style === input.target.mixPlan.style ? 'same' : 'changed'
    },
    {
      label: 'Tempo sync',
      primary: formatTempo(input.primary.mixPlan.tempoSync.targetRate),
      target: formatTempo(input.target.mixPlan.tempoSync.targetRate),
      delta:
        input.primary.mixPlan.tempoSync.targetRate ===
        input.target.mixPlan.tempoSync.targetRate
          ? 'same'
          : 'changed'
    },
    {
      label: 'Confidence',
      primary: input.primary.mixPlan.confidence.toFixed(2),
      target: input.target.mixPlan.confidence.toFixed(2),
      delta: formatSigned(
        input.primary.mixPlan.confidence - input.target.mixPlan.confidence
      )
    }
  ];
};

export const buildMixPlanComparisonExportEnvelope = (input: {
  primary: MixPlanComparisonSubject;
  target: MixPlanComparisonSubject;
  exportedAt?: string;
}): MixPlanComparisonExportEnvelope => {
  return {
    exportSchemaVersion: MIX_PLAN_COMPARISON_EXPORT_SCHEMA_VERSION,
    exportedAt: input.exportedAt ?? new Date().toISOString(),
    comparison: {
      primary: {
        id: input.primary.id,
        label: input.primary.label,
        summary: input.primary.summary,
        context: input.primary.context ?? null
      },
      target: {
        id: input.target.id,
        label: input.target.label,
        summary: input.target.summary,
        context: input.target.context ?? null
      },
      rows: buildMixPlanComparisonRows(input)
    }
  };
};

export const parseMixPlanComparisonExportJson = (
  payload: string
): ParseMixPlanComparisonExportResult => {
  let parsed: unknown;

  try {
    parsed = JSON.parse(payload);
  } catch {
    return {
      envelope: null,
      reason: 'mix_plan_comparison_invalid_json'
    };
  }

  if (!isRecord(parsed) || !isRecord(parsed.comparison)) {
    return {
      envelope: null,
      reason: 'mix_plan_comparison_not_object'
    };
  }

  if (parsed.exportSchemaVersion !== MIX_PLAN_COMPARISON_EXPORT_SCHEMA_VERSION) {
    return {
      envelope: null,
      reason: 'mix_plan_comparison_invalid_schema_version'
    };
  }

  if (!isString(parsed.exportedAt)) {
    return {
      envelope: null,
      reason: 'mix_plan_comparison_invalid_exported_at'
    };
  }

  const primary = parseMixPlanComparisonSubjectMeta(parsed.comparison.primary);
  const target = parseMixPlanComparisonSubjectMeta(parsed.comparison.target);
  const rows = Array.isArray(parsed.comparison.rows)
    ? parsed.comparison.rows
        .map((row) => parseMixPlanComparisonRow(row))
        .filter((row): row is MixPlanComparisonRow => row !== null)
    : null;

  if (!primary || !target || rows === null || rows.length === 0) {
    return {
      envelope: null,
      reason: 'mix_plan_comparison_invalid_payload'
    };
  }

  return {
    envelope: {
      exportSchemaVersion: MIX_PLAN_COMPARISON_EXPORT_SCHEMA_VERSION,
      exportedAt: parsed.exportedAt,
      comparison: {
        primary,
        target,
        rows
      }
    },
    reason: null
  };
};
