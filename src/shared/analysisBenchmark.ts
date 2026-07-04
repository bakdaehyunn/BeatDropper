import {
  AnalysisWarning,
  CueCandidateOrigin,
  CueCandidateType,
  MusicalKeyMode,
  TRACK_ANALYSIS_SCHEMA_VERSION,
  TrackAnalysis,
  hasPlannerReadyTrackAnalysis,
  sanitizeTrackAnalysis
} from './analysis';

export type AnalysisBenchmarkGrade = 'pass' | 'warn' | 'fail';
export type AnalysisBenchmarkFixtureKind = 'synthetic' | 'snapshot';
export type AnalysisBenchmarkIssueCode =
  | 'bpm_missing'
  | 'bpm_error_high'
  | 'first_downbeat_missing'
  | 'first_downbeat_far'
  | 'outro_missing'
  | 'outro_far'
  | 'bar_grid_missing'
  | 'bar_grid_drift_high'
  | 'phrase_missing'
  | 'phrase_boundary_far'
  | 'planner_ready_mismatch'
  | 'key_missing'
  | 'key_mismatch'
  | 'key_confidence_low'
  | 'loudness_missing'
  | 'loudness_lufs_missing'
  | 'loudness_rms_delta_high'
  | 'loudness_lufs_delta_high'
  | 'loudness_peak_delta_high'
  | 'loudness_true_peak_missing'
  | 'loudness_true_peak_delta_high'
  | 'headroom_low'
  | 'loudness_confidence_low'
  | 'cue_missing'
  | 'cue_far'
  | 'cue_confidence_low'
  | 'cue_origin_mismatch'
  | 'stereo_missing'
  | 'stereo_channel_count_mismatch'
  | 'stereo_width_low'
  | 'stereo_width_high'
  | 'stereo_phase_correlation_low'
  | 'stereo_mid_side_balance_high'
  | 'stereo_confidence_low'
  | 'analysis_confidence_low'
  | 'harmonic_key_quality_low'
  | 'forbidden_warning_present';

export interface AnalysisBenchmarkKeyExpectation {
  tonic?: string | null;
  mode?: MusicalKeyMode | null;
  minConfidence?: number | null;
}

export interface AnalysisBenchmarkLoudnessExpectation {
  integratedRMSDb?: number | null;
  integratedLUFS?: number | null;
  peakDb?: number | null;
  truePeakDb?: number | null;
  minHeadroomDb?: number | null;
  minConfidence?: number | null;
}

export interface AnalysisBenchmarkCueExpectation {
  type: CueCandidateType;
  startSec: number;
  minConfidence?: number | null;
  origin?: CueCandidateOrigin | null;
}

export interface AnalysisBenchmarkMixReadinessExpectation {
  minAnalysisConfidence?: number | null;
  minHarmonicKeyQuality?: number | null;
  minLoudnessConfidence?: number | null;
  forbiddenWarnings?: AnalysisWarning[];
}

export interface AnalysisBenchmarkStereoExpectation {
  channelCount?: number | null;
  minStereoWidth?: number | null;
  maxStereoWidth?: number | null;
  minPhaseCorrelation?: number | null;
  maxMidSideBalance?: number | null;
  minConfidence?: number | null;
}

export interface AnalysisBenchmarkExpectation {
  bpm?: number | null;
  firstDownbeatSec?: number | null;
  outroCueSec?: number | null;
  barGridSec?: number[];
  phraseBoundarySec?: number[];
  plannerReady?: boolean;
  musicalKey?: AnalysisBenchmarkKeyExpectation | null;
  loudness?: AnalysisBenchmarkLoudnessExpectation | null;
  stereo?: AnalysisBenchmarkStereoExpectation | null;
  cueCandidates?: AnalysisBenchmarkCueExpectation[];
  mixReadiness?: AnalysisBenchmarkMixReadinessExpectation | null;
}

export interface AnalysisBenchmarkFixture {
  id: string;
  title: string;
  kind?: AnalysisBenchmarkFixtureKind;
  tags?: string[];
  trackReference?: {
    artist?: string;
    title?: string;
    source?: 'synthetic' | 'private-library' | 'external-reference';
    notes?: string;
  };
  expectedGrade?: AnalysisBenchmarkGrade;
  expected: AnalysisBenchmarkExpectation;
  groundTruthLabels?: {
    schemaVersion?: number;
    reviewedBy?: string;
    reviewedAt?: string;
    notes?: string;
    expected: AnalysisBenchmarkExpectation;
  } | null;
  analysis: Partial<TrackAnalysis>;
  thresholds?: Partial<AnalysisBenchmarkThresholds>;
}

export interface AnalysisBenchmarkThresholds {
  bpmWarnError: number;
  bpmFailError: number;
  cueWarnDistanceSec: number;
  cueFailDistanceSec: number;
  barWarnAverageDriftSec: number;
  barFailAverageDriftSec: number;
  barWarnMaxDriftSec: number;
  barFailMaxDriftSec: number;
  phraseWarnAverageDistanceSec: number;
  phraseFailAverageDistanceSec: number;
  keyWarnConfidence: number;
  keyFailConfidence: number;
  loudnessWarnDeltaDb: number;
  loudnessFailDeltaDb: number;
  headroomWarnDb: number;
  headroomFailDb: number;
  cueWarnConfidence: number;
  cueFailConfidence: number;
}

export interface AnalysisBenchmarkIssue {
  code: AnalysisBenchmarkIssueCode;
  grade: AnalysisBenchmarkGrade;
  message: string;
}

export interface AnalysisBenchmarkDistanceMetric {
  expectedSec: number;
  actualSec: number | null;
  distanceSec: number | null;
}

export interface AnalysisBenchmarkKeyMetric {
  expectedTonic: string | null;
  expectedMode: MusicalKeyMode | null;
  actualTonic: string | null;
  actualMode: MusicalKeyMode | null;
  confidence: number | null;
  matched: boolean | null;
}

export interface AnalysisBenchmarkLoudnessMetric {
  expectedIntegratedRMSDb: number | null;
  actualIntegratedRMSDb: number | null;
  integratedRMSDeltaDb: number | null;
  expectedIntegratedLUFS: number | null;
  actualIntegratedLUFS: number | null;
  integratedLUFSDelta: number | null;
  expectedPeakDb: number | null;
  actualPeakDb: number | null;
  peakDeltaDb: number | null;
  expectedTruePeakDb: number | null;
  actualTruePeakDb: number | null;
  truePeakDeltaDb: number | null;
  headroomDb: number | null;
  loudnessRangeLU: number | null;
  measurement: string | null;
  confidence: number | null;
}

export interface AnalysisBenchmarkCueMetric {
  type: CueCandidateType;
  expectedSec: number;
  actualSec: number | null;
  distanceSec: number | null;
  confidence: number | null;
  origin: CueCandidateOrigin | null;
}

export interface AnalysisBenchmarkMixReadinessMetric {
  analysisConfidence: number;
  harmonicKeyQuality: number;
  loudnessConfidence: number | null;
  forbiddenWarningsPresent: AnalysisWarning[];
}

export interface AnalysisBenchmarkStereoMetric {
  expectedChannelCount: number | null;
  actualChannelCount: number | null;
  stereoWidth: number | null;
  phaseCorrelation: number | null;
  midSideBalance: number | null;
  confidence: number | null;
}

export interface AnalysisBenchmarkResult {
  grade: AnalysisBenchmarkGrade;
  score: number;
  issues: AnalysisBenchmarkIssue[];
  metrics: {
    bpmError: number | null;
    firstDownbeat: AnalysisBenchmarkDistanceMetric | null;
    outro: AnalysisBenchmarkDistanceMetric | null;
    barGrid: {
      checkedCount: number;
      averageDriftSec: number | null;
      maxDriftSec: number | null;
    };
    phraseBoundaries: {
      checkedCount: number;
      averageDistanceSec: number | null;
      maxDistanceSec: number | null;
    };
    plannerReadyMatch: boolean | null;
    musicalKey: AnalysisBenchmarkKeyMetric | null;
    loudness: AnalysisBenchmarkLoudnessMetric | null;
    stereo: AnalysisBenchmarkStereoMetric | null;
    cueCandidates: AnalysisBenchmarkCueMetric[];
    mixReadiness: AnalysisBenchmarkMixReadinessMetric | null;
  };
}

export interface AnalysisBenchmarkFixtureResult extends AnalysisBenchmarkResult {
  fixtureId: string;
  title: string;
  trackId: string;
  kind: AnalysisBenchmarkFixtureKind;
  tags: string[];
  expectedGrade: AnalysisBenchmarkGrade | null;
  trackReference: AnalysisBenchmarkFixture['trackReference'] | null;
}

export interface AnalysisBenchmarkKindSummary {
  kind: AnalysisBenchmarkFixtureKind;
  grade: AnalysisBenchmarkGrade;
  score: number;
  total: number;
  passed: number;
  warned: number;
  failed: number;
}

export interface AnalysisBenchmarkSuiteResult {
  grade: AnalysisBenchmarkGrade;
  score: number;
  passed: number;
  warned: number;
  failed: number;
  byKind: AnalysisBenchmarkKindSummary[];
  results: AnalysisBenchmarkFixtureResult[];
}

export const DEFAULT_ANALYSIS_BENCHMARK_THRESHOLDS: AnalysisBenchmarkThresholds = {
  bpmWarnError: 1.5,
  bpmFailError: 4,
  cueWarnDistanceSec: 1,
  cueFailDistanceSec: 4,
  barWarnAverageDriftSec: 0.18,
  barFailAverageDriftSec: 0.55,
  barWarnMaxDriftSec: 0.45,
  barFailMaxDriftSec: 1.25,
  phraseWarnAverageDistanceSec: 2,
  phraseFailAverageDistanceSec: 8,
  keyWarnConfidence: 0.35,
  keyFailConfidence: 0.24,
  loudnessWarnDeltaDb: 1.5,
  loudnessFailDeltaDb: 3,
  headroomWarnDb: 1,
  headroomFailDb: 0.2,
  cueWarnConfidence: 0.55,
  cueFailConfidence: 0.35
};

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const round = (value: number, digits = 3): number => {
  const multiplier = 10 ** digits;
  return Math.round(value * multiplier) / multiplier;
};

const average = (values: number[]): number | null => {
  if (values.length === 0) {
    return null;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
};

const gradeFromIssues = (issues: AnalysisBenchmarkIssue[]): AnalysisBenchmarkGrade => {
  if (issues.some((issue) => issue.grade === 'fail')) {
    return 'fail';
  }
  if (issues.some((issue) => issue.grade === 'warn')) {
    return 'warn';
  }
  return 'pass';
};

const resolveFixtureKind = (kind: unknown): AnalysisBenchmarkFixtureKind => {
  return kind === 'snapshot' ? 'snapshot' : 'synthetic';
};

const normalizeTags = (tags: unknown): string[] => {
  return Array.isArray(tags)
    ? tags.filter((tag): tag is string => typeof tag === 'string' && tag.trim().length > 0)
    : [];
};

const pushIssue = (
  issues: AnalysisBenchmarkIssue[],
  code: AnalysisBenchmarkIssueCode,
  grade: AnalysisBenchmarkGrade,
  message: string
): void => {
  issues.push({ code, grade, message });
};

const nearestValue = (
  values: number[],
  expected: number
): { value: number; distance: number } | null => {
  const finiteValues = values.filter(isFiniteNumber);
  if (finiteValues.length === 0) {
    return null;
  }

  let best = finiteValues[0];
  let bestDistance = Math.abs(best - expected);
  for (const value of finiteValues.slice(1)) {
    const distance = Math.abs(value - expected);
    if (distance < bestDistance) {
      best = value;
      bestDistance = distance;
    }
  }

  return { value: best, distance: bestDistance };
};

const collectCueTimes = (
  analysis: TrackAnalysis,
  type: CueCandidateType,
  fallbackSec: number | null
): number[] => {
  return [
    ...analysis.cueCandidates
      .filter((cue) => cue.type === type)
      .map((cue) => cue.startSec)
      .filter(isFiniteNumber),
    ...(fallbackSec !== null && isFiniteNumber(fallbackSec) ? [fallbackSec] : [])
  ];
};

const distanceMetric = (
  actualValues: number[],
  expectedSec: number
): AnalysisBenchmarkDistanceMetric => {
  const nearest = nearestValue(actualValues, expectedSec);
  return {
    expectedSec,
    actualSec: nearest ? round(nearest.value, 3) : null,
    distanceSec: nearest ? round(nearest.distance, 3) : null
  };
};

const scoreDistance = (value: number | null, warn: number, fail: number): number => {
  if (value === null) {
    return 0;
  }
  if (value <= warn) {
    return 1;
  }
  if (value >= fail) {
    return 0;
  }
  return clamp(1 - (value - warn) / (fail - warn), 0, 1);
};

const evaluateDistanceIssue = (input: {
  metric: AnalysisBenchmarkDistanceMetric;
  missingCode: AnalysisBenchmarkIssueCode;
  farCode: AnalysisBenchmarkIssueCode;
  label: string;
  warnDistanceSec: number;
  failDistanceSec: number;
  issues: AnalysisBenchmarkIssue[];
}): void => {
  if (input.metric.distanceSec === null) {
    pushIssue(input.issues, input.missingCode, 'fail', `${input.label} is missing.`);
    return;
  }

  if (input.metric.distanceSec > input.failDistanceSec) {
    pushIssue(
      input.issues,
      input.farCode,
      'fail',
      `${input.label} is ${input.metric.distanceSec.toFixed(2)}s from expected.`
    );
    return;
  }

  if (input.metric.distanceSec > input.warnDistanceSec) {
    pushIssue(
      input.issues,
      input.farCode,
      'warn',
      `${input.label} is ${input.metric.distanceSec.toFixed(2)}s from expected.`
    );
  }
};

const evaluateSeriesDistances = (
  actualValues: number[],
  expectedValues: number[]
): { checkedCount: number; averageDistanceSec: number | null; maxDistanceSec: number | null } => {
  const distances = expectedValues
    .filter(isFiniteNumber)
    .map((expected) => nearestValue(actualValues, expected)?.distance ?? null)
    .filter(isFiniteNumber);

  return {
    checkedCount: expectedValues.length,
    averageDistanceSec: average(distances) === null ? null : round(average(distances) as number),
    maxDistanceSec: distances.length > 0 ? round(Math.max(...distances)) : null
  };
};

const scoreLowerBound = (value: number | null, warn: number, fail: number): number => {
  if (value === null) {
    return 0;
  }
  if (value >= warn) {
    return 1;
  }
  if (value <= fail) {
    return 0;
  }
  return clamp((value - fail) / (warn - fail), 0, 1);
};

const evaluateDbDeltaIssue = (input: {
  delta: number | null;
  code: AnalysisBenchmarkIssueCode;
  label: string;
  thresholds: AnalysisBenchmarkThresholds;
  issues: AnalysisBenchmarkIssue[];
}): void => {
  if (input.delta === null) {
    return;
  }
  if (input.delta > input.thresholds.loudnessFailDeltaDb) {
    pushIssue(input.issues, input.code, 'fail', `${input.label} delta is ${input.delta.toFixed(2)} dB.`);
  } else if (input.delta > input.thresholds.loudnessWarnDeltaDb) {
    pushIssue(input.issues, input.code, 'warn', `${input.label} delta is ${input.delta.toFixed(2)} dB.`);
  }
};

const evaluateMusicalKey = (
  analysis: TrackAnalysis,
  expected: AnalysisBenchmarkKeyExpectation,
  thresholds: AnalysisBenchmarkThresholds,
  issues: AnalysisBenchmarkIssue[]
): AnalysisBenchmarkKeyMetric => {
  const key = analysis.musicalKey ?? null;
  const tonicMatches = expected.tonic == null || key?.tonic === expected.tonic;
  const modeMatches = expected.mode == null || key?.mode === expected.mode;
  const matched = key === null ? null : tonicMatches && modeMatches;
  if (!key) {
    pushIssue(issues, 'key_missing', 'fail', 'Musical key evidence is missing.');
  } else if (matched === false) {
    pushIssue(
      issues,
      'key_mismatch',
      key.confidence >= thresholds.keyWarnConfidence ? 'fail' : 'warn',
      `Musical key expected ${expected.tonic ?? '--'} ${expected.mode ?? '--'}, got ${key.tonic} ${key.mode}.`
    );
  }
  if (isFiniteNumber(expected.minConfidence) && (key?.confidence ?? 0) < expected.minConfidence) {
    pushIssue(
      issues,
      'key_confidence_low',
      (key?.confidence ?? 0) < thresholds.keyFailConfidence ? 'fail' : 'warn',
      `Musical key confidence ${(key?.confidence ?? 0).toFixed(2)} is below expected ${expected.minConfidence.toFixed(2)}.`
    );
  }
  return {
    expectedTonic: expected.tonic ?? null,
    expectedMode: expected.mode ?? null,
    actualTonic: key?.tonic ?? null,
    actualMode: key?.mode ?? null,
    confidence: isFiniteNumber(key?.confidence) ? round(key.confidence) : null,
    matched
  };
};

const evaluateLoudness = (
  analysis: TrackAnalysis,
  expected: AnalysisBenchmarkLoudnessExpectation,
  thresholds: AnalysisBenchmarkThresholds,
  issues: AnalysisBenchmarkIssue[]
): AnalysisBenchmarkLoudnessMetric => {
  const loudness = analysis.loudness ?? null;
  if (!loudness) {
    pushIssue(issues, 'loudness_missing', 'fail', 'Loudness evidence is missing.');
    return {
      expectedIntegratedRMSDb: expected.integratedRMSDb ?? null,
      actualIntegratedRMSDb: null,
      integratedRMSDeltaDb: null,
      expectedIntegratedLUFS: expected.integratedLUFS ?? null,
      actualIntegratedLUFS: null,
      integratedLUFSDelta: null,
      expectedPeakDb: expected.peakDb ?? null,
      actualPeakDb: null,
      peakDeltaDb: null,
      expectedTruePeakDb: expected.truePeakDb ?? null,
      actualTruePeakDb: null,
      truePeakDeltaDb: null,
      headroomDb: null,
      loudnessRangeLU: null,
      measurement: null,
      confidence: null
    };
  }
  const integratedRMSDeltaDb = isFiniteNumber(expected.integratedRMSDb)
    ? round(Math.abs(loudness.integratedRMSDb - expected.integratedRMSDb), 2)
    : null;
  evaluateDbDeltaIssue({
    delta: integratedRMSDeltaDb,
    code: 'loudness_rms_delta_high',
    label: 'Integrated RMS',
    thresholds,
    issues
  });
  const integratedLUFSDelta = isFiniteNumber(expected.integratedLUFS) && isFiniteNumber(loudness.integratedLUFS)
    ? round(Math.abs(loudness.integratedLUFS - expected.integratedLUFS), 2)
    : null;
  if (isFiniteNumber(expected.integratedLUFS) && !isFiniteNumber(loudness.integratedLUFS)) {
    pushIssue(issues, 'loudness_lufs_missing', 'fail', 'Integrated LUFS evidence is missing.');
  }
  evaluateDbDeltaIssue({
    delta: integratedLUFSDelta,
    code: 'loudness_lufs_delta_high',
    label: 'Integrated LUFS',
    thresholds,
    issues
  });
  const peakDeltaDb = isFiniteNumber(expected.peakDb)
    ? round(Math.abs(loudness.peakDb - expected.peakDb), 2)
    : null;
  evaluateDbDeltaIssue({
    delta: peakDeltaDb,
    code: 'loudness_peak_delta_high',
    label: 'Peak',
    thresholds,
    issues
  });
  const truePeakDeltaDb = isFiniteNumber(expected.truePeakDb) && isFiniteNumber(loudness.truePeakDb)
    ? round(Math.abs(loudness.truePeakDb - expected.truePeakDb), 2)
    : null;
  if (isFiniteNumber(expected.truePeakDb) && !isFiniteNumber(loudness.truePeakDb)) {
    pushIssue(issues, 'loudness_true_peak_missing', 'fail', 'True-peak evidence is missing.');
  }
  evaluateDbDeltaIssue({
    delta: truePeakDeltaDb,
    code: 'loudness_true_peak_delta_high',
    label: 'True peak',
    thresholds,
    issues
  });
  if (isFiniteNumber(expected.minHeadroomDb) && loudness.headroomDb < expected.minHeadroomDb) {
    pushIssue(
      issues,
      'headroom_low',
      loudness.headroomDb < thresholds.headroomFailDb ? 'fail' : 'warn',
      `Headroom ${loudness.headroomDb.toFixed(2)} dB is below expected ${expected.minHeadroomDb.toFixed(2)} dB.`
    );
  }
  if (isFiniteNumber(expected.minConfidence) && loudness.confidence < expected.minConfidence) {
    pushIssue(
      issues,
      'loudness_confidence_low',
      loudness.confidence < 0.45 ? 'fail' : 'warn',
      `Loudness confidence ${loudness.confidence.toFixed(2)} is below expected ${expected.minConfidence.toFixed(2)}.`
    );
  }
  return {
    expectedIntegratedRMSDb: expected.integratedRMSDb ?? null,
    actualIntegratedRMSDb: round(loudness.integratedRMSDb, 2),
    integratedRMSDeltaDb,
    expectedIntegratedLUFS: expected.integratedLUFS ?? null,
    actualIntegratedLUFS: isFiniteNumber(loudness.integratedLUFS) ? round(loudness.integratedLUFS, 2) : null,
    integratedLUFSDelta,
    expectedPeakDb: expected.peakDb ?? null,
    actualPeakDb: round(loudness.peakDb, 2),
    peakDeltaDb,
    expectedTruePeakDb: expected.truePeakDb ?? null,
    actualTruePeakDb: isFiniteNumber(loudness.truePeakDb) ? round(loudness.truePeakDb, 2) : null,
    truePeakDeltaDb,
    headroomDb: round(loudness.headroomDb, 2),
    loudnessRangeLU: isFiniteNumber(loudness.loudnessRangeLU) ? round(loudness.loudnessRangeLU, 2) : null,
    measurement: loudness.measurement ?? null,
    confidence: round(loudness.confidence)
  };
};

const evaluateCueCandidate = (
  analysis: TrackAnalysis,
  expected: AnalysisBenchmarkCueExpectation,
  thresholds: AnalysisBenchmarkThresholds,
  issues: AnalysisBenchmarkIssue[]
): AnalysisBenchmarkCueMetric => {
  const nearest = analysis.cueCandidates
    .filter((cue) => cue.type === expected.type)
    .map((cue) => ({ cue, distance: Math.abs(cue.startSec - expected.startSec) }))
    .sort((left, right) => left.distance - right.distance)[0] ?? null;
  if (!nearest) {
    pushIssue(issues, 'cue_missing', 'fail', `Cue ${expected.type} is missing.`);
  } else if (nearest.distance > thresholds.cueFailDistanceSec) {
    pushIssue(issues, 'cue_far', 'fail', `Cue ${expected.type} is ${nearest.distance.toFixed(2)}s from expected.`);
  } else if (nearest.distance > thresholds.cueWarnDistanceSec) {
    pushIssue(issues, 'cue_far', 'warn', `Cue ${expected.type} is ${nearest.distance.toFixed(2)}s from expected.`);
  }
  if (isFiniteNumber(expected.minConfidence) && (nearest?.cue.confidence ?? 0) < expected.minConfidence) {
    pushIssue(
      issues,
      'cue_confidence_low',
      (nearest?.cue.confidence ?? 0) < thresholds.cueFailConfidence ? 'fail' : 'warn',
      `Cue ${expected.type} confidence ${(nearest?.cue.confidence ?? 0).toFixed(2)} is below expected ${expected.minConfidence.toFixed(2)}.`
    );
  }
  if (expected.origin && nearest?.cue.origin !== expected.origin) {
    pushIssue(
      issues,
      'cue_origin_mismatch',
      'warn',
      `Cue ${expected.type} origin expected ${expected.origin}, got ${nearest?.cue.origin ?? '--'}.`
    );
  }
  return {
    type: expected.type,
    expectedSec: expected.startSec,
    actualSec: nearest ? round(nearest.cue.startSec) : null,
    distanceSec: nearest ? round(nearest.distance) : null,
    confidence: nearest ? round(nearest.cue.confidence) : null,
    origin: nearest?.cue.origin ?? null
  };
};

const evaluateStereo = (
  analysis: TrackAnalysis,
  expected: AnalysisBenchmarkStereoExpectation,
  issues: AnalysisBenchmarkIssue[]
): AnalysisBenchmarkStereoMetric => {
  const stereo = analysis.stereo ?? null;
  if (!stereo) {
    pushIssue(issues, 'stereo_missing', 'fail', 'Stereo evidence is missing.');
    return {
      expectedChannelCount: expected.channelCount ?? null,
      actualChannelCount: null,
      stereoWidth: null,
      phaseCorrelation: null,
      midSideBalance: null,
      confidence: null
    };
  }
  if (isFiniteNumber(expected.channelCount) && stereo.channelCount !== expected.channelCount) {
    pushIssue(issues, 'stereo_channel_count_mismatch', 'fail', `Channel count expected ${expected.channelCount}, got ${stereo.channelCount}.`);
  }
  if (isFiniteNumber(expected.minStereoWidth) && stereo.stereoWidth < expected.minStereoWidth) {
    pushIssue(issues, 'stereo_width_low', 'warn', `Stereo width ${stereo.stereoWidth.toFixed(2)} is below expected ${expected.minStereoWidth.toFixed(2)}.`);
  }
  if (isFiniteNumber(expected.maxStereoWidth) && stereo.stereoWidth > expected.maxStereoWidth) {
    pushIssue(issues, 'stereo_width_high', 'warn', `Stereo width ${stereo.stereoWidth.toFixed(2)} is above expected ${expected.maxStereoWidth.toFixed(2)}.`);
  }
  if (isFiniteNumber(expected.minPhaseCorrelation) && stereo.phaseCorrelation < expected.minPhaseCorrelation) {
    pushIssue(
      issues,
      'stereo_phase_correlation_low',
      stereo.phaseCorrelation < 0 ? 'fail' : 'warn',
      `Phase correlation ${stereo.phaseCorrelation.toFixed(2)} is below expected ${expected.minPhaseCorrelation.toFixed(2)}.`
    );
  }
  if (isFiniteNumber(expected.maxMidSideBalance) && stereo.midSideBalance > expected.maxMidSideBalance) {
    pushIssue(issues, 'stereo_mid_side_balance_high', 'warn', `Mid/side balance ${stereo.midSideBalance.toFixed(2)} is above expected ${expected.maxMidSideBalance.toFixed(2)}.`);
  }
  if (isFiniteNumber(expected.minConfidence) && stereo.confidence < expected.minConfidence) {
    pushIssue(issues, 'stereo_confidence_low', 'warn', `Stereo confidence ${stereo.confidence.toFixed(2)} is below expected ${expected.minConfidence.toFixed(2)}.`);
  }
  return {
    expectedChannelCount: expected.channelCount ?? null,
    actualChannelCount: stereo.channelCount,
    stereoWidth: round(stereo.stereoWidth),
    phaseCorrelation: round(stereo.phaseCorrelation),
    midSideBalance: round(stereo.midSideBalance),
    confidence: round(stereo.confidence)
  };
};

const evaluateMixReadiness = (
  analysis: TrackAnalysis,
  expected: AnalysisBenchmarkMixReadinessExpectation,
  issues: AnalysisBenchmarkIssue[]
): AnalysisBenchmarkMixReadinessMetric => {
  if (isFiniteNumber(expected.minAnalysisConfidence) && analysis.analysisConfidence < expected.minAnalysisConfidence) {
    pushIssue(issues, 'analysis_confidence_low', 'warn', `Analysis confidence ${analysis.analysisConfidence.toFixed(2)} is below expected ${expected.minAnalysisConfidence.toFixed(2)}.`);
  }
  const harmonicKeyQuality = analysis.analysisQuality.harmonicKey ?? 0;
  if (isFiniteNumber(expected.minHarmonicKeyQuality) && harmonicKeyQuality < expected.minHarmonicKeyQuality) {
    pushIssue(issues, 'harmonic_key_quality_low', 'warn', `Harmonic key quality ${harmonicKeyQuality.toFixed(2)} is below expected ${expected.minHarmonicKeyQuality.toFixed(2)}.`);
  }
  if (isFiniteNumber(expected.minLoudnessConfidence) && (analysis.loudness?.confidence ?? 0) < expected.minLoudnessConfidence) {
    pushIssue(issues, 'loudness_confidence_low', 'warn', `Loudness confidence ${(analysis.loudness?.confidence ?? 0).toFixed(2)} is below expected ${expected.minLoudnessConfidence.toFixed(2)}.`);
  }
  const forbiddenWarningsPresent = (expected.forbiddenWarnings ?? []).filter((warning) =>
    analysis.analysisWarnings.includes(warning)
  );
  for (const warning of forbiddenWarningsPresent) {
    pushIssue(issues, 'forbidden_warning_present', 'warn', `Forbidden analysis warning is present: ${warning}.`);
  }
  return {
    analysisConfidence: round(analysis.analysisConfidence),
    harmonicKeyQuality: round(harmonicKeyQuality),
    loudnessConfidence: isFiniteNumber(analysis.loudness?.confidence) ? round(analysis.loudness.confidence) : null,
    forbiddenWarningsPresent
  };
};

export const evaluateTrackAnalysisBenchmark = (input: {
  analysis: TrackAnalysis;
  expected: AnalysisBenchmarkExpectation;
  thresholds?: Partial<AnalysisBenchmarkThresholds>;
}): AnalysisBenchmarkResult => {
  const thresholds = {
    ...DEFAULT_ANALYSIS_BENCHMARK_THRESHOLDS,
    ...(input.thresholds ?? {})
  };
  const { analysis, expected } = input;
  const issues: AnalysisBenchmarkIssue[] = [];

  const bpmError =
    isFiniteNumber(expected.bpm) && isFiniteNumber(analysis.bpm)
      ? round(Math.abs(analysis.bpm - expected.bpm))
      : null;
  if (isFiniteNumber(expected.bpm) && !isFiniteNumber(analysis.bpm)) {
    pushIssue(issues, 'bpm_missing', 'fail', 'BPM is missing.');
  } else if (bpmError !== null && bpmError > thresholds.bpmFailError) {
    pushIssue(issues, 'bpm_error_high', 'fail', `BPM error is ${bpmError.toFixed(2)}.`);
  } else if (bpmError !== null && bpmError > thresholds.bpmWarnError) {
    pushIssue(issues, 'bpm_error_high', 'warn', `BPM error is ${bpmError.toFixed(2)}.`);
  }

  const firstDownbeat = isFiniteNumber(expected.firstDownbeatSec)
    ? distanceMetric(
        [
          ...collectCueTimes(analysis, 'first_downbeat', null),
          ...analysis.downbeatsSec.filter(isFiniteNumber)
        ],
        expected.firstDownbeatSec
      )
    : null;
  if (firstDownbeat) {
    evaluateDistanceIssue({
      metric: firstDownbeat,
      missingCode: 'first_downbeat_missing',
      farCode: 'first_downbeat_far',
      label: 'First downbeat',
      warnDistanceSec: thresholds.cueWarnDistanceSec,
      failDistanceSec: thresholds.cueFailDistanceSec,
      issues
    });
  }

  const outro = isFiniteNumber(expected.outroCueSec)
    ? distanceMetric(collectCueTimes(analysis, 'outro', analysis.outroCueSec), expected.outroCueSec)
    : null;
  if (outro) {
    evaluateDistanceIssue({
      metric: outro,
      missingCode: 'outro_missing',
      farCode: 'outro_far',
      label: 'Outro cue',
      warnDistanceSec: thresholds.cueWarnDistanceSec,
      failDistanceSec: thresholds.cueFailDistanceSec,
      issues
    });
  }

  const expectedBarGrid = expected.barGridSec?.filter(isFiniteNumber) ?? [];
  const barGridDistances = evaluateSeriesDistances(
    analysis.barGrid.map((bar) => bar.startSec),
    expectedBarGrid
  );
  const barGrid = {
    checkedCount: barGridDistances.checkedCount,
    averageDriftSec: barGridDistances.averageDistanceSec,
    maxDriftSec: barGridDistances.maxDistanceSec
  };
  if (expectedBarGrid.length > 0 && analysis.barGrid.length === 0) {
    pushIssue(issues, 'bar_grid_missing', 'fail', 'Bar grid is missing.');
  } else if (
    barGrid.averageDriftSec !== null &&
    (barGrid.averageDriftSec > thresholds.barFailAverageDriftSec ||
      (barGrid.maxDriftSec ?? 0) > thresholds.barFailMaxDriftSec)
  ) {
    pushIssue(
      issues,
      'bar_grid_drift_high',
      'fail',
      `Bar grid drift avg ${barGrid.averageDriftSec.toFixed(2)}s, max ${(barGrid.maxDriftSec ?? 0).toFixed(2)}s.`
    );
  } else if (
    barGrid.averageDriftSec !== null &&
    (barGrid.averageDriftSec > thresholds.barWarnAverageDriftSec ||
      (barGrid.maxDriftSec ?? 0) > thresholds.barWarnMaxDriftSec)
  ) {
    pushIssue(
      issues,
      'bar_grid_drift_high',
      'warn',
      `Bar grid drift avg ${barGrid.averageDriftSec.toFixed(2)}s, max ${(barGrid.maxDriftSec ?? 0).toFixed(2)}s.`
    );
  }

  const expectedPhraseBoundaries = expected.phraseBoundarySec?.filter(isFiniteNumber) ?? [];
  const phraseDistances = evaluateSeriesDistances(
    analysis.phraseMarkers.map((marker) => marker.startSec),
    expectedPhraseBoundaries
  );
  const phraseBoundaries = {
    checkedCount: phraseDistances.checkedCount,
    averageDistanceSec: phraseDistances.averageDistanceSec,
    maxDistanceSec: phraseDistances.maxDistanceSec
  };
  if (expectedPhraseBoundaries.length > 0 && analysis.phraseMarkers.length === 0) {
    pushIssue(issues, 'phrase_missing', 'fail', 'Phrase boundaries are missing.');
  } else if (
    phraseBoundaries.averageDistanceSec !== null &&
    phraseBoundaries.averageDistanceSec > thresholds.phraseFailAverageDistanceSec
  ) {
    pushIssue(
      issues,
      'phrase_boundary_far',
      'fail',
      `Phrase boundary distance avg ${phraseBoundaries.averageDistanceSec.toFixed(2)}s.`
    );
  } else if (
    phraseBoundaries.averageDistanceSec !== null &&
    phraseBoundaries.averageDistanceSec > thresholds.phraseWarnAverageDistanceSec
  ) {
    pushIssue(
      issues,
      'phrase_boundary_far',
      'warn',
      `Phrase boundary distance avg ${phraseBoundaries.averageDistanceSec.toFixed(2)}s.`
    );
  }

  const plannerReadyActual = hasPlannerReadyTrackAnalysis(analysis);
  const plannerReadyMatch =
    typeof expected.plannerReady === 'boolean'
      ? plannerReadyActual === expected.plannerReady
      : null;
  if (plannerReadyMatch === false) {
    pushIssue(
      issues,
      'planner_ready_mismatch',
      'warn',
      `Planner-ready expected ${expected.plannerReady}, got ${plannerReadyActual}.`
    );
  }

  const musicalKey = expected.musicalKey
    ? evaluateMusicalKey(analysis, expected.musicalKey, thresholds, issues)
    : null;
  const loudness = expected.loudness
    ? evaluateLoudness(analysis, expected.loudness, thresholds, issues)
    : null;
  const stereo = expected.stereo
    ? evaluateStereo(analysis, expected.stereo, issues)
    : null;
  const cueCandidates = (expected.cueCandidates ?? []).map((cue) =>
    evaluateCueCandidate(analysis, cue, thresholds, issues)
  );
  const mixReadiness = expected.mixReadiness
    ? evaluateMixReadiness(analysis, expected.mixReadiness, issues)
    : null;

  const scoreParts = [
    scoreDistance(bpmError, thresholds.bpmWarnError, thresholds.bpmFailError),
    firstDownbeat
      ? scoreDistance(firstDownbeat.distanceSec, thresholds.cueWarnDistanceSec, thresholds.cueFailDistanceSec)
      : null,
    outro
      ? scoreDistance(outro.distanceSec, thresholds.cueWarnDistanceSec, thresholds.cueFailDistanceSec)
      : null,
    expectedBarGrid.length > 0
      ? scoreDistance(
          barGrid.averageDriftSec,
          thresholds.barWarnAverageDriftSec,
          thresholds.barFailAverageDriftSec
        )
      : null,
    expectedPhraseBoundaries.length > 0
      ? scoreDistance(
          phraseBoundaries.averageDistanceSec,
          thresholds.phraseWarnAverageDistanceSec,
          thresholds.phraseFailAverageDistanceSec
        )
      : null,
    plannerReadyMatch === null ? null : plannerReadyMatch ? 1 : 0.5,
    musicalKey
      ? ((musicalKey.matched === false ? 0 : 1) * 0.68) +
        (scoreLowerBound(
          musicalKey.confidence,
          expected.musicalKey?.minConfidence ?? thresholds.keyWarnConfidence,
          thresholds.keyFailConfidence
        ) * 0.32)
      : null,
    loudness
      ? average([
          expected.loudness?.integratedRMSDb == null
            ? null
            : scoreDistance(loudness.integratedRMSDeltaDb, thresholds.loudnessWarnDeltaDb, thresholds.loudnessFailDeltaDb),
          expected.loudness?.integratedLUFS == null
            ? null
            : scoreDistance(loudness.integratedLUFSDelta, thresholds.loudnessWarnDeltaDb, thresholds.loudnessFailDeltaDb),
          expected.loudness?.peakDb == null
            ? null
            : scoreDistance(loudness.peakDeltaDb, thresholds.loudnessWarnDeltaDb, thresholds.loudnessFailDeltaDb),
          expected.loudness?.truePeakDb == null
            ? null
            : scoreDistance(loudness.truePeakDeltaDb, thresholds.loudnessWarnDeltaDb, thresholds.loudnessFailDeltaDb),
          expected.loudness?.minHeadroomDb == null
            ? null
            : scoreLowerBound(loudness.headroomDb, thresholds.headroomWarnDb, thresholds.headroomFailDb),
          expected.loudness?.minConfidence == null
            ? null
            : scoreLowerBound(loudness.confidence, expected.loudness.minConfidence, 0.45)
        ].filter(isFiniteNumber))
      : null,
    stereo
      ? average([
          expected.stereo?.channelCount == null
            ? null
            : stereo.actualChannelCount === expected.stereo.channelCount ? 1 : 0,
          expected.stereo?.minStereoWidth == null
            ? null
            : (stereo.stereoWidth ?? 0) >= expected.stereo.minStereoWidth ? 1 : 0.5,
          expected.stereo?.maxStereoWidth == null
            ? null
            : (stereo.stereoWidth ?? 1) <= expected.stereo.maxStereoWidth ? 1 : 0.5,
          expected.stereo?.minPhaseCorrelation == null
            ? null
            : (stereo.phaseCorrelation ?? -1) >= expected.stereo.minPhaseCorrelation ? 1 : 0.5,
          expected.stereo?.maxMidSideBalance == null
            ? null
            : (stereo.midSideBalance ?? 99) <= expected.stereo.maxMidSideBalance ? 1 : 0.5,
          expected.stereo?.minConfidence == null
            ? null
            : (stereo.confidence ?? 0) >= expected.stereo.minConfidence ? 1 : 0.5
        ].filter(isFiniteNumber))
      : null,
    cueCandidates.length === 0
      ? null
      : average(cueCandidates.map((cue) =>
          scoreDistance(cue.distanceSec, thresholds.cueWarnDistanceSec, thresholds.cueFailDistanceSec)
        )),
    mixReadiness
      ? average([
          expected.mixReadiness?.minAnalysisConfidence == null
            ? null
            : mixReadiness.analysisConfidence >= expected.mixReadiness.minAnalysisConfidence ? 1 : 0.5,
          expected.mixReadiness?.minHarmonicKeyQuality == null
            ? null
            : mixReadiness.harmonicKeyQuality >= expected.mixReadiness.minHarmonicKeyQuality ? 1 : 0.5,
          expected.mixReadiness?.minLoudnessConfidence == null
            ? null
            : (mixReadiness.loudnessConfidence ?? 0) >= expected.mixReadiness.minLoudnessConfidence ? 1 : 0.5,
          expected.mixReadiness?.forbiddenWarnings?.length
            ? (mixReadiness.forbiddenWarningsPresent.length === 0 ? 1 : 0.5)
            : null
        ].filter(isFiniteNumber))
      : null
  ].filter(isFiniteNumber);

  return {
    grade: gradeFromIssues(issues),
    score: scoreParts.length > 0
      ? round(scoreParts.reduce((sum, value) => sum + value, 0) / scoreParts.length)
      : 0,
    issues,
    metrics: {
      bpmError,
      firstDownbeat,
      outro,
      barGrid,
      phraseBoundaries,
      plannerReadyMatch,
      musicalKey,
      loudness,
      stereo,
      cueCandidates,
      mixReadiness
    }
  };
};

export const evaluateAnalysisBenchmarkFixture = (
  fixture: AnalysisBenchmarkFixture
): AnalysisBenchmarkFixtureResult => {
  const trackId =
    typeof fixture.analysis.trackId === 'string' && fixture.analysis.trackId.length > 0
      ? fixture.analysis.trackId
      : fixture.id;
  const analysis = sanitizeTrackAnalysis(trackId, {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    ...fixture.analysis
  });
  const result = evaluateTrackAnalysisBenchmark({
    analysis,
    expected: fixture.groundTruthLabels?.expected ?? fixture.expected,
    thresholds: fixture.thresholds
  });

  return {
    ...result,
    fixtureId: fixture.id,
    title: fixture.title,
    trackId,
    kind: resolveFixtureKind(fixture.kind),
    tags: normalizeTags(fixture.tags),
    expectedGrade: fixture.expectedGrade ?? null,
    trackReference: fixture.trackReference ?? null
  };
};

const summarizeKindResults = (
  kind: AnalysisBenchmarkFixtureKind,
  results: AnalysisBenchmarkFixtureResult[]
): AnalysisBenchmarkKindSummary | null => {
  const kindResults = results.filter((result) => result.kind === kind);
  if (kindResults.length === 0) {
    return null;
  }

  const passed = kindResults.filter((result) => result.grade === 'pass').length;
  const warned = kindResults.filter((result) => result.grade === 'warn').length;
  const failed = kindResults.filter((result) => result.grade === 'fail').length;
  const score = round(
    kindResults.reduce((sum, result) => sum + result.score, 0) / kindResults.length
  );

  return {
    kind,
    grade: failed > 0 ? 'fail' : warned > 0 ? 'warn' : 'pass',
    score,
    total: kindResults.length,
    passed,
    warned,
    failed
  };
};

export const evaluateAnalysisBenchmarkSuite = (
  fixtures: AnalysisBenchmarkFixture[]
): AnalysisBenchmarkSuiteResult => {
  const results = fixtures.map(evaluateAnalysisBenchmarkFixture);
  const passed = results.filter((result) => result.grade === 'pass').length;
  const warned = results.filter((result) => result.grade === 'warn').length;
  const failed = results.filter((result) => result.grade === 'fail').length;
  const score =
    results.length > 0
      ? round(results.reduce((sum, result) => sum + result.score, 0) / results.length)
      : 0;

  return {
    grade: failed > 0 ? 'fail' : warned > 0 ? 'warn' : 'pass',
    score,
    passed,
    warned,
    failed,
    byKind: (['synthetic', 'snapshot'] as const)
      .map((kind) => summarizeKindResults(kind, results))
      .filter((summary): summary is AnalysisBenchmarkKindSummary => summary !== null),
    results
  };
};
