import { TrackAnalysis } from './analysis';
import { MixPlan } from './mixPlan';
import { PlayerSettings, Track } from './types';

export type MixPlanQualityGrade = 'excellent' | 'good' | 'usable' | 'weak' | 'reject';
export type MixPlanQualityIssueSeverity = 'warning' | 'major' | 'critical';
export type MixPlanQualityIssueCode =
  | 'transition_before_playhead'
  | 'transition_out_of_bounds'
  | 'fade_window_invalid'
  | 'fade_window_too_short'
  | 'fade_window_too_long'
  | 'current_timing_far_from_outro'
  | 'current_timing_before_outro'
  | 'next_timing_far_from_intro'
  | 'bar_alignment_off'
  | 'phrase_alignment_mismatch'
  | 'tempo_sync_mismatch'
  | 'tempo_sync_missing'
  | 'tempo_sync_rate_out_of_range'
  | 'energy_strategy_mismatch'
  | 'energy_gap_large'
  | 'planner_confidence_low';

export interface MixPlanQualityIssue {
  code: MixPlanQualityIssueCode;
  severity: MixPlanQualityIssueSeverity;
  message: string;
}

export interface MixPlanQualityMetric {
  name:
    | 'fade_window'
    | 'current_out_timing'
    | 'next_in_timing'
    | 'bar_alignment'
    | 'phrase_alignment'
    | 'tempo'
    | 'energy'
    | 'planner_confidence';
  score: number;
  weight: number;
  summary: string;
}

export interface MixPlanQualityResult {
  score: number;
  grade: MixPlanQualityGrade;
  shouldApply: boolean;
  issues: MixPlanQualityIssue[];
  metrics: MixPlanQualityMetric[];
  summary: string;
}

export interface EvaluateMixPlanQualityInput {
  plan: MixPlan;
  currentTrack: Track;
  nextTrack: Track;
  currentAnalysis: TrackAnalysis | null;
  nextAnalysis: TrackAnalysis | null;
  settings: Pick<PlayerSettings, 'fadeDurationSec' | 'aiDjMode'>;
  currentPlaybackElapsedSec?: number;
}

interface NearestBar {
  index: number;
  startSec: number;
  distanceSec: number;
}

interface CueTime {
  timeSec: number;
  confidence: number;
}

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const isFiniteNumber = (value: number | null | undefined): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const formatSec = (value: number): string => `${value.toFixed(2)}s`;

const scoreDistance = (
  distance: number,
  perfectDistance: number,
  maxDistance: number
): number => {
  if (distance <= perfectDistance) {
    return 1;
  }
  if (maxDistance <= perfectDistance) {
    return distance <= perfectDistance ? 1 : 0;
  }
  return clamp(1 - (distance - perfectDistance) / (maxDistance - perfectDistance), 0, 1);
};

const nearestBar = (analysis: TrackAnalysis | null, timeSec: number): NearestBar | null => {
  if (!analysis || analysis.barGrid.length === 0) {
    return null;
  }

  let best = analysis.barGrid[0];
  let bestDistance = Math.abs(best.startSec - timeSec);
  for (const marker of analysis.barGrid) {
    const distance = Math.abs(marker.startSec - timeSec);
    if (distance < bestDistance) {
      best = marker;
      bestDistance = distance;
    }
  }

  return {
    index: best.index,
    startSec: best.startSec,
    distanceSec: bestDistance
  };
};

const medianBarLengthSec = (analysis: TrackAnalysis | null): number | null => {
  if (!analysis || analysis.barGrid.length < 2) {
    return isFiniteNumber(analysis?.bpm) && analysis.bpm > 0 ? 240 / analysis.bpm : null;
  }

  const distances = analysis.barGrid
    .slice(1)
    .map((marker, index) => marker.startSec - analysis.barGrid[index].startSec)
    .filter((distance) => distance > 0.05)
    .sort((left, right) => left - right);
  if (distances.length === 0) {
    return isFiniteNumber(analysis.bpm) && analysis.bpm > 0 ? 240 / analysis.bpm : null;
  }

  return distances[Math.floor(distances.length / 2)];
};

const collectCueTimes = (
  analysis: TrackAnalysis | null,
  fallbackCueSec: number | null | undefined,
  types: Array<TrackAnalysis['cueCandidates'][number]['type']>
): CueTime[] => {
  if (!analysis) {
    return [];
  }

  const cues = analysis.cueCandidates
    .filter((cue) => types.includes(cue.type))
    .map((cue) => ({
      timeSec: cue.startSec,
      confidence: cue.confidence
    }));

  if (isFiniteNumber(fallbackCueSec)) {
    cues.push({
      timeSec: fallbackCueSec,
      confidence: 0.5
    });
  }

  return cues.filter((cue) => cue.timeSec >= 0);
};

const nearestCue = (cues: CueTime[], timeSec: number): (CueTime & { distanceSec: number }) | null => {
  if (cues.length === 0) {
    return null;
  }

  let best = cues[0];
  let bestDistance = Math.abs(best.timeSec - timeSec);
  for (const cue of cues.slice(1)) {
    const distance = Math.abs(cue.timeSec - timeSec);
    if (distance < bestDistance) {
      best = cue;
      bestDistance = distance;
    }
  }

  return {
    ...best,
    distanceSec: bestDistance
  };
};

const getEnergyAt = (
  analysis: TrackAnalysis | null,
  timeSec: number,
  durationSec: number
): number | null => {
  if (!analysis || analysis.energyProfile.length === 0 || durationSec <= 0) {
    return null;
  }

  const index = clamp(
    Math.floor((timeSec / durationSec) * analysis.energyProfile.length),
    0,
    analysis.energyProfile.length - 1
  );
  return analysis.energyProfile[index] ?? null;
};

const resolveTrackBpm = (track: Track, analysis: TrackAnalysis | null): number | null => {
  return isFiniteNumber(analysis?.bpm)
    ? analysis.bpm
    : isFiniteNumber(track.bpm)
      ? track.bpm
      : null;
};

const resolvePhraseAlignment = (
  currentBarIndex: number | null,
  nextBarIndex: number | null
): NonNullable<MixPlan['phraseAlignment']> | null => {
  if (currentBarIndex === null || nextBarIndex === null) {
    return null;
  }

  const currentPhrase = currentBarIndex % 8;
  const nextPhrase = nextBarIndex % 8;
  if (currentPhrase === nextPhrase) {
    return 'aligned';
  }
  return Math.abs(currentPhrase - nextPhrase) <= 1 ? 'near' : 'free';
};

const pushIssue = (
  issues: MixPlanQualityIssue[],
  code: MixPlanQualityIssueCode,
  severity: MixPlanQualityIssueSeverity,
  message: string
): void => {
  issues.push({ code, severity, message });
};

const gradeFromScore = (score: number): MixPlanQualityGrade => {
  if (score >= 0.85) {
    return 'excellent';
  }
  if (score >= 0.72) {
    return 'good';
  }
  if (score >= 0.58) {
    return 'usable';
  }
  if (score >= 0.42) {
    return 'weak';
  }
  return 'reject';
};

const shouldApplyThreshold = (mode: PlayerSettings['aiDjMode']): number => {
  if (mode === 'safe') {
    return 0.62;
  }
  if (mode === 'adventurous') {
    return 0.54;
  }
  return 0.58;
};

const allowedMajorIssueCount = (mode: PlayerSettings['aiDjMode']): number => {
  if (mode === 'safe') {
    return 0;
  }
  if (mode === 'adventurous') {
    return 2;
  }
  return 1;
};

export const evaluateMixPlanQuality = (
  input: EvaluateMixPlanQualityInput
): MixPlanQualityResult => {
  const { plan, currentTrack, nextTrack, currentAnalysis, nextAnalysis, settings } = input;
  const issues: MixPlanQualityIssue[] = [];
  const metrics: MixPlanQualityMetric[] = [];
  const currentDurationSec = Math.max(0, currentTrack.durationSec);
  const nextDurationSec = Math.max(0, nextTrack.durationSec);
  const elapsedSec = Math.max(0, input.currentPlaybackElapsedSec ?? 0);
  const fadeWindowSec = plan.transitionEndSec - plan.transitionStartSec;

  if (plan.transitionStartSec + 0.05 < elapsedSec) {
    pushIssue(
      issues,
      'transition_before_playhead',
      'critical',
      `Transition starts before the current playhead (${formatSec(plan.transitionStartSec)} < ${formatSec(elapsedSec)}).`
    );
  }
  if (
    plan.transitionStartSec < 0 ||
    plan.transitionEndSec > currentDurationSec ||
    plan.nextTrackStartOffsetSec < 0 ||
    plan.nextTrackStartOffsetSec > nextDurationSec
  ) {
    pushIssue(
      issues,
      'transition_out_of_bounds',
      'critical',
      'Transition timing falls outside the available track duration.'
    );
  }
  if (fadeWindowSec <= 0) {
    pushIssue(issues, 'fade_window_invalid', 'critical', 'Fade window must be positive.');
  }

  const targetFadeSec = Math.max(0.25, settings.fadeDurationSec);
  const fadeIdealSec =
    plan.style === 'hard_cut'
      ? Math.min(1.5, targetFadeSec * 0.25)
      : plan.style === 'energy_swap'
        ? targetFadeSec * 0.75
        : targetFadeSec;
  const fadeScore =
    fadeWindowSec <= 0
      ? 0
      : scoreDistance(Math.abs(fadeWindowSec - fadeIdealSec), targetFadeSec * 0.15, targetFadeSec);
  if (plan.style !== 'hard_cut' && fadeWindowSec < Math.max(1, targetFadeSec * 0.35)) {
    pushIssue(
      issues,
      'fade_window_too_short',
      'major',
      `Fade window ${formatSec(fadeWindowSec)} is short for ${plan.style}.`
    );
  }
  if (fadeWindowSec > targetFadeSec * 1.15) {
    pushIssue(
      issues,
      'fade_window_too_long',
      'major',
      `Fade window ${formatSec(fadeWindowSec)} exceeds the configured fade duration.`
    );
  }
  metrics.push({
    name: 'fade_window',
    score: fadeScore,
    weight: 0.14,
    summary: `fade ${formatSec(fadeWindowSec)}`
  });

  const currentOutCues = collectCueTimes(currentAnalysis, currentAnalysis?.outroCueSec, [
    'outro',
    'low_energy_break'
  ]);
  const currentCue = nearestCue(currentOutCues, plan.transitionStartSec);
  let currentOutScore = 0.55;
  if (currentCue) {
    currentOutScore = scoreDistance(currentCue.distanceSec, 2, 24);
    if (plan.transitionStartSec < currentCue.timeSec - 8) {
      pushIssue(
        issues,
        'current_timing_before_outro',
        'major',
        `Transition starts ${formatSec(currentCue.timeSec - plan.transitionStartSec)} before the nearest outro cue.`
      );
    } else if (currentCue.distanceSec > 24) {
      pushIssue(
        issues,
        'current_timing_far_from_outro',
        'major',
        `Transition is ${formatSec(currentCue.distanceSec)} away from the nearest outro cue.`
      );
    }
  } else if (currentDurationSec > 0) {
    const relativeStart = plan.transitionStartSec / currentDurationSec;
    currentOutScore = clamp((relativeStart - 0.35) / 0.4, 0, 1);
  }
  metrics.push({
    name: 'current_out_timing',
    score: currentOutScore,
    weight: 0.13,
    summary: currentCue
      ? `out cue distance ${formatSec(currentCue.distanceSec)}`
      : 'out cue unavailable'
  });

  const nextInCues = collectCueTimes(nextAnalysis, nextAnalysis?.introCueSec, [
    'intro',
    'first_downbeat'
  ]);
  const nextCue = nearestCue(nextInCues, plan.nextTrackStartOffsetSec);
  let nextInScore = 0.55;
  if (nextCue) {
    nextInScore = scoreDistance(nextCue.distanceSec, 1, 16);
    if (nextCue.distanceSec > 16) {
      pushIssue(
        issues,
        'next_timing_far_from_intro',
        'major',
        `Next-track offset is ${formatSec(nextCue.distanceSec)} away from the nearest intro/downbeat cue.`
      );
    }
  } else if (nextDurationSec > 0) {
    nextInScore = plan.nextTrackStartOffsetSec <= Math.min(32, nextDurationSec * 0.25) ? 0.7 : 0.25;
  }
  metrics.push({
    name: 'next_in_timing',
    score: nextInScore,
    weight: 0.11,
    summary: nextCue ? `in cue distance ${formatSec(nextCue.distanceSec)}` : 'in cue unavailable'
  });

  const currentBar = nearestBar(currentAnalysis, plan.transitionStartSec);
  const nextBar = nearestBar(nextAnalysis, plan.nextTrackStartOffsetSec);
  const currentBarLength = medianBarLengthSec(currentAnalysis);
  const nextBarLength = medianBarLengthSec(nextAnalysis);
  const currentBarTolerance = Math.max(0.35, (currentBarLength ?? 4) * 0.2);
  const nextBarTolerance = Math.max(0.35, (nextBarLength ?? 4) * 0.2);
  const currentBarScore = currentBar
    ? scoreDistance(currentBar.distanceSec, 0.12, currentBarTolerance)
    : 0.55;
  const nextBarScore = nextBar
    ? scoreDistance(nextBar.distanceSec, 0.12, nextBarTolerance)
    : 0.55;
  const barAlignmentScore = (currentBarScore + nextBarScore) / 2;
  if (
    (currentBar && currentBar.distanceSec > currentBarTolerance) ||
    (nextBar && nextBar.distanceSec > nextBarTolerance)
  ) {
    pushIssue(
      issues,
      'bar_alignment_off',
      'major',
      'Transition timing is not close to the nearest detected bar marker.'
    );
  }
  metrics.push({
    name: 'bar_alignment',
    score: barAlignmentScore,
    weight: 0.17,
    summary: `bar distance ${formatSec(currentBar?.distanceSec ?? 0)} / ${formatSec(nextBar?.distanceSec ?? 0)}`
  });

  const actualPhraseAlignment = resolvePhraseAlignment(
    currentBar?.index ?? null,
    nextBar?.index ?? null
  );
  const phraseScore =
    actualPhraseAlignment === 'aligned'
      ? 1
      : actualPhraseAlignment === 'near'
        ? 0.76
        : actualPhraseAlignment === 'free'
          ? 0.42
          : 0.55;
  if (
    plan.phraseAlignment &&
    actualPhraseAlignment &&
    plan.phraseAlignment !== actualPhraseAlignment &&
    !(plan.phraseAlignment === 'aligned' && actualPhraseAlignment === 'near')
  ) {
    pushIssue(
      issues,
      'phrase_alignment_mismatch',
      'major',
      `Plan reports ${plan.phraseAlignment} phrase alignment, detected ${actualPhraseAlignment}.`
    );
  }
  metrics.push({
    name: 'phrase_alignment',
    score: phraseScore,
    weight: 0.14,
    summary: actualPhraseAlignment ?? 'phrase unavailable'
  });

  const currentBpm = resolveTrackBpm(currentTrack, currentAnalysis);
  const nextBpm = resolveTrackBpm(nextTrack, nextAnalysis);
  let tempoScore = 0.55;
  if (isFiniteNumber(currentBpm) && isFiniteNumber(nextBpm) && nextBpm > 0) {
    const expectedRate = currentBpm / nextBpm;
    const bpmDelta = Math.abs(currentBpm - nextBpm);
    if (plan.tempoSync.enabled) {
      if (!isFiniteNumber(plan.tempoSync.targetRate)) {
        tempoScore = 0;
        pushIssue(
          issues,
          'tempo_sync_rate_out_of_range',
          'critical',
          'Tempo sync is enabled without a finite target rate.'
        );
      } else if (plan.tempoSync.targetRate < 0.85 || plan.tempoSync.targetRate > 1.15) {
        tempoScore = 0;
        pushIssue(
          issues,
          'tempo_sync_rate_out_of_range',
          'critical',
          `Tempo sync target rate ${plan.tempoSync.targetRate.toFixed(3)} is outside the safe range.`
        );
      } else {
        const rateDelta = Math.abs(plan.tempoSync.targetRate - expectedRate);
        tempoScore = scoreDistance(rateDelta, 0.015, 0.08);
        if (rateDelta > 0.06) {
          pushIssue(
            issues,
            'tempo_sync_mismatch',
            'major',
            `Tempo sync target ${plan.tempoSync.targetRate.toFixed(3)} does not match expected ${expectedRate.toFixed(3)}.`
          );
        }
      }
    } else {
      tempoScore =
        bpmDelta <= 4 ? 1 : bpmDelta <= 8 ? 0.68 : bpmDelta <= 14 ? 0.38 : 0.12;
      if (bpmDelta > 10) {
        pushIssue(
          issues,
          'tempo_sync_missing',
          'major',
          `BPM delta ${bpmDelta.toFixed(1)} is high but tempo sync is disabled.`
        );
      }
    }
  }
  metrics.push({
    name: 'tempo',
    score: tempoScore,
    weight: 0.17,
    summary: currentBpm && nextBpm ? `bpm ${currentBpm.toFixed(1)} -> ${nextBpm.toFixed(1)}` : 'tempo unavailable'
  });

  const currentEnergy = getEnergyAt(currentAnalysis, plan.transitionStartSec, currentDurationSec);
  const nextEnergy = getEnergyAt(nextAnalysis, plan.nextTrackStartOffsetSec, nextDurationSec);
  let energyScore = 0.55;
  if (isFiniteNumber(currentEnergy) && isFiniteNumber(nextEnergy)) {
    const energyDelta = nextEnergy - currentEnergy;
    const expectedDelta =
      plan.energyStrategy === 'drop'
        ? -0.12
        : plan.energyStrategy === 'maintain'
          ? 0
          : plan.energyStrategy === 'lift'
            ? 0.12
            : 0.08;
    const maxDistance = plan.energyStrategy ? 0.45 : 0.55;
    energyScore = scoreDistance(Math.abs(energyDelta - expectedDelta), 0.08, maxDistance);
    if (
      (plan.energyStrategy === 'lift' && energyDelta < -0.15) ||
      (plan.energyStrategy === 'drop' && energyDelta > 0.15) ||
      (plan.energyStrategy === 'maintain' && Math.abs(energyDelta) > 0.3)
    ) {
      pushIssue(
        issues,
        'energy_strategy_mismatch',
        'major',
        `Energy delta ${energyDelta.toFixed(2)} conflicts with ${plan.energyStrategy}.`
      );
    } else if (Math.abs(energyDelta) > 0.65) {
      pushIssue(
        issues,
        'energy_gap_large',
        'warning',
        `Energy delta ${energyDelta.toFixed(2)} is large for a smooth transition.`
      );
    }
  }
  metrics.push({
    name: 'energy',
    score: energyScore,
    weight: 0.09,
    summary:
      currentEnergy !== null && nextEnergy !== null
        ? `energy ${currentEnergy.toFixed(2)} -> ${nextEnergy.toFixed(2)}`
        : 'energy unavailable'
  });

  const confidenceScore = clamp(plan.confidence, 0, 1);
  if (confidenceScore < 0.35) {
    pushIssue(
      issues,
      'planner_confidence_low',
      'warning',
      `Planner confidence ${confidenceScore.toFixed(2)} is low.`
    );
  }
  metrics.push({
    name: 'planner_confidence',
    score: confidenceScore,
    weight: 0.04,
    summary: `confidence ${confidenceScore.toFixed(2)}`
  });

  const totalWeight = metrics.reduce((sum, metric) => sum + metric.weight, 0);
  const score = totalWeight > 0
    ? clamp(
        metrics.reduce((sum, metric) => sum + metric.score * metric.weight, 0) / totalWeight,
        0,
        1
      )
    : 0;
  const criticalIssueCount = issues.filter((issue) => issue.severity === 'critical').length;
  const majorIssueCount = issues.filter((issue) => issue.severity === 'major').length;
  const grade = criticalIssueCount > 0 ? 'reject' : gradeFromScore(score);
  const shouldApply =
    criticalIssueCount === 0 &&
    score >= shouldApplyThreshold(settings.aiDjMode) &&
    majorIssueCount <= allowedMajorIssueCount(settings.aiDjMode);

  return {
    score,
    grade,
    shouldApply,
    issues,
    metrics,
    summary: `${grade} (${Math.round(score * 100)}%)`
  };
};
