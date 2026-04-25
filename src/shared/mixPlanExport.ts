import { TrackAnalysis, TrackAnalysisSource } from './analysis';
import { MixPlan } from './mixPlan';
import { PlannerRequest, PlannerTrackSnapshot } from './plannerContract';

export const MIX_PLAN_EXPORT_SCHEMA_VERSION = 1;

export type MixPlanPlannerPreset = 'codex' | 'heuristic' | 'custom' | 'none';

export const MIX_PLAN_PLANNER_PRESET_DESCRIPTIONS: Record<
  MixPlanPlannerPreset,
  string
> = {
  codex: 'Codex sample wrapper',
  heuristic: 'Local heuristic wrapper',
  custom: 'Custom planner command',
  none: 'No preset'
};

export interface MixPlanExportPlannerMetadata {
  preset: MixPlanPlannerPreset;
  presetLabel: string;
  source: string | null;
  command: string | null;
  args: string[];
  timeoutMs: number;
  plannerResponseSchemaVersion: number | null;
}

export interface MixPlanAnalysisSummary {
  trackId: string;
  generatedAt: string;
  source: TrackAnalysisSource;
  bpm: number | null;
  introCueSec: number | null;
  outroCueSec: number | null;
  analysisConfidence: number;
  beatGridCount: number;
  downbeatCount: number;
  energySampleCount: number;
}

export interface MixPlanExportContext {
  currentTrack: PlannerTrackSnapshot;
  nextTrack: PlannerTrackSnapshot;
  analysis: {
    current: MixPlanAnalysisSummary | null;
    next: MixPlanAnalysisSummary | null;
  };
}

export interface MixPlanExportEnvelope {
  exportSchemaVersion: typeof MIX_PLAN_EXPORT_SCHEMA_VERSION;
  exportedAt: string;
  planner: MixPlanExportPlannerMetadata;
  context: MixPlanExportContext | null;
  mixPlan: MixPlan;
}

export interface MixPlanExportMetadata {
  exportSchemaVersion: typeof MIX_PLAN_EXPORT_SCHEMA_VERSION;
  planner: MixPlanExportPlannerMetadata;
}

export interface ParseMixPlanExportResult {
  envelope: MixPlanExportEnvelope | null;
  reason: string | null;
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const isStringArray = (value: unknown): value is string[] => {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
};

const parsePlannerTrackSnapshot = (value: unknown): PlannerTrackSnapshot | null => {
  if (!isRecord(value)) {
    return null;
  }

  if (
    typeof value.id !== 'string' ||
    typeof value.title !== 'string' ||
    !isFiniteNumber(value.durationSec) ||
    (value.bpm !== null && !isFiniteNumber(value.bpm))
  ) {
    return null;
  }

  return {
    id: value.id,
    title: value.title,
    durationSec: value.durationSec,
    bpm: value.bpm
  };
};

const summarizeTrackAnalysis = (analysis: TrackAnalysis | null): MixPlanAnalysisSummary | null => {
  if (!analysis) {
    return null;
  }

  return {
    trackId: analysis.trackId,
    generatedAt: analysis.generatedAt,
    source: analysis.source,
    bpm: analysis.bpm,
    introCueSec: analysis.introCueSec,
    outroCueSec: analysis.outroCueSec,
    analysisConfidence: analysis.analysisConfidence,
    beatGridCount: analysis.beatGridSec.length,
    downbeatCount: analysis.downbeatsSec.length,
    energySampleCount: analysis.energyProfile.length
  };
};

const parseMixPlanAnalysisSummary = (value: unknown): MixPlanAnalysisSummary | null => {
  if (value === null) {
    return null;
  }

  if (!isRecord(value)) {
    return null;
  }

  if (
    typeof value.trackId !== 'string' ||
    typeof value.generatedAt !== 'string' ||
    (value.source !== 'metadata' && value.source !== 'derived' && value.source !== 'external') ||
    (value.bpm !== null && !isFiniteNumber(value.bpm)) ||
    (value.introCueSec !== null && !isFiniteNumber(value.introCueSec)) ||
    (value.outroCueSec !== null && !isFiniteNumber(value.outroCueSec)) ||
    !isFiniteNumber(value.analysisConfidence) ||
    !isFiniteNumber(value.beatGridCount) ||
    !isFiniteNumber(value.downbeatCount) ||
    !isFiniteNumber(value.energySampleCount)
  ) {
    return null;
  }

  return {
    trackId: value.trackId,
    generatedAt: value.generatedAt,
    source: value.source,
    bpm: value.bpm,
    introCueSec: value.introCueSec,
    outroCueSec: value.outroCueSec,
    analysisConfidence: value.analysisConfidence,
    beatGridCount: value.beatGridCount,
    downbeatCount: value.downbeatCount,
    energySampleCount: value.energySampleCount
  };
};

const parseMixPlanExportContext = (value: unknown): MixPlanExportContext | null => {
  if (value === null || value === undefined) {
    return null;
  }

  if (!isRecord(value) || !isRecord(value.analysis)) {
    return null;
  }

  const currentTrack = parsePlannerTrackSnapshot(value.currentTrack);
  const nextTrack = parsePlannerTrackSnapshot(value.nextTrack);
  const currentAnalysis = parseMixPlanAnalysisSummary(value.analysis.current);
  const nextAnalysis = parseMixPlanAnalysisSummary(value.analysis.next);

  if (!currentTrack || !nextTrack) {
    return null;
  }

  return {
    currentTrack,
    nextTrack,
    analysis: {
      current: currentAnalysis,
      next: nextAnalysis
    }
  };
};

const parseMixPlan = (value: unknown): MixPlan | null => {
  if (!isRecord(value)) {
    return null;
  }

  if (
    !isFiniteNumber(value.transitionStartSec) ||
    !isFiniteNumber(value.transitionEndSec) ||
    !isFiniteNumber(value.nextTrackStartOffsetSec) ||
    !isFiniteNumber(value.confidence)
  ) {
    return null;
  }

  if (
    value.style !== 'smooth_blend' &&
    value.style !== 'energy_swap' &&
    value.style !== 'hard_cut'
  ) {
    return null;
  }

  if (value.reasoningSummary !== null && typeof value.reasoningSummary !== 'string') {
    return null;
  }

  if (!isRecord(value.tempoSync) || typeof value.tempoSync.enabled !== 'boolean') {
    return null;
  }

  if (
    value.tempoSync.targetRate !== null &&
    !isFiniteNumber(value.tempoSync.targetRate)
  ) {
    return null;
  }

  return {
    transitionStartSec: value.transitionStartSec,
    transitionEndSec: value.transitionEndSec,
    nextTrackStartOffsetSec: value.nextTrackStartOffsetSec,
    style: value.style,
    confidence: value.confidence,
    reasoningSummary: value.reasoningSummary,
    tempoSync: {
      enabled: value.tempoSync.enabled,
      targetRate: value.tempoSync.targetRate
    }
  };
};

const parsePlannerMetadata = (value: unknown): MixPlanExportPlannerMetadata | null => {
  if (!isRecord(value)) {
    return null;
  }

  if (
    value.preset !== 'codex' &&
    value.preset !== 'heuristic' &&
    value.preset !== 'custom' &&
    value.preset !== 'none'
  ) {
    return null;
  }

  if (
    typeof value.presetLabel !== 'string' ||
    (value.source !== null && typeof value.source !== 'string') ||
    (value.command !== null && typeof value.command !== 'string') ||
    !isStringArray(value.args) ||
    !isFiniteNumber(value.timeoutMs) ||
    (value.plannerResponseSchemaVersion !== null &&
      !isFiniteNumber(value.plannerResponseSchemaVersion))
  ) {
    return null;
  }

  return {
    preset: value.preset,
    presetLabel: value.presetLabel,
    source: value.source,
    command: value.command,
    args: value.args,
    timeoutMs: value.timeoutMs,
    plannerResponseSchemaVersion: value.plannerResponseSchemaVersion
  };
};

export const buildMixPlanExportMetadata = (
  planner: MixPlanExportPlannerMetadata
): MixPlanExportMetadata => {
  return {
    exportSchemaVersion: MIX_PLAN_EXPORT_SCHEMA_VERSION,
    planner
  };
};

export const buildMixPlanExportContext = (input: {
  currentTrack: PlannerTrackSnapshot;
  nextTrack: PlannerTrackSnapshot;
  analysis: {
    current: TrackAnalysis | null;
    next: TrackAnalysis | null;
  };
}): MixPlanExportContext => {
  return {
    currentTrack: input.currentTrack,
    nextTrack: input.nextTrack,
    analysis: {
      current: summarizeTrackAnalysis(input.analysis.current),
      next: summarizeTrackAnalysis(input.analysis.next)
    }
  };
};

export const buildMixPlanExportContextFromPlannerRequest = (
  request: PlannerRequest
): MixPlanExportContext => {
  return buildMixPlanExportContext({
    currentTrack: request.currentTrack,
    nextTrack: request.nextTrack,
    analysis: request.analysis
  });
};

export const parseMixPlanExportContextFromUnknown = (
  value: unknown
): MixPlanExportContext | null => {
  return parseMixPlanExportContext(value);
};

export const buildMixPlanExportEnvelope = (input: {
  planner: MixPlanExportPlannerMetadata;
  context?: MixPlanExportContext | null;
  mixPlan: MixPlan;
  exportedAt?: string;
}): MixPlanExportEnvelope => {
  return {
    ...buildMixPlanExportMetadata(input.planner),
    exportedAt: input.exportedAt ?? new Date().toISOString(),
    context: input.context ?? null,
    mixPlan: input.mixPlan
  };
};

export const parseMixPlanExportJson = (payload: string): ParseMixPlanExportResult => {
  let parsed: unknown;

  try {
    parsed = JSON.parse(payload);
  } catch {
    return {
      envelope: null,
      reason: 'mix_plan_export_invalid_json'
    };
  }

  if (!isRecord(parsed)) {
    return {
      envelope: null,
      reason: 'mix_plan_export_not_object'
    };
  }

  if (parsed.exportSchemaVersion !== MIX_PLAN_EXPORT_SCHEMA_VERSION) {
    return {
      envelope: null,
      reason: 'mix_plan_export_invalid_schema_version'
    };
  }

  if (typeof parsed.exportedAt !== 'string') {
    return {
      envelope: null,
      reason: 'mix_plan_export_invalid_exported_at'
    };
  }

  const planner = parsePlannerMetadata(parsed.planner);
  if (!planner) {
    return {
      envelope: null,
      reason: 'mix_plan_export_invalid_planner_metadata'
    };
  }

  const mixPlan = parseMixPlan(parsed.mixPlan);
  if (!mixPlan) {
    return {
      envelope: null,
      reason: 'mix_plan_export_invalid_mix_plan'
    };
  }

  return {
    envelope: {
      exportSchemaVersion: MIX_PLAN_EXPORT_SCHEMA_VERSION,
      exportedAt: parsed.exportedAt,
      planner,
      context: parseMixPlanExportContext(parsed.context),
      mixPlan
    },
    reason: null
  };
};
