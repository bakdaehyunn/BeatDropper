import {
  CueCandidateType,
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
  | 'planner_ready_mismatch';

export interface AnalysisBenchmarkExpectation {
  bpm?: number | null;
  firstDownbeatSec?: number | null;
  outroCueSec?: number | null;
  barGridSec?: number[];
  phraseBoundarySec?: number[];
  plannerReady?: boolean;
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
  phraseFailAverageDistanceSec: 8
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
    plannerReadyMatch === null ? null : plannerReadyMatch ? 1 : 0.5
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
      plannerReadyMatch
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
    expected: fixture.expected,
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
