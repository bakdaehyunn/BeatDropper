import {
  AnalysisQuality,
  AnalysisWarning,
  CueCandidate,
  CueCandidateType,
  TrackAnalysis,
  TrackAnalysisSource,
  hasPlannerReadyTrackAnalysis
} from './analysis';
import { Track } from './types';

export type PlannerEnergyTrendDirection = 'rising' | 'falling' | 'flat' | 'unknown';

export interface PlannerCueSummary {
  type: CueCandidateType;
  startSec: number;
  confidence: number;
  label: string;
}

export interface PlannerEnergyTrendSummary {
  early: number | null;
  mid: number | null;
  late: number | null;
  direction: PlannerEnergyTrendDirection;
}

export interface PlannerTransientSummary {
  count: number;
  strongCount: number;
  densityPerSec: number;
}

export interface PlannerPhraseBoundarySummary {
  index: number;
  startSec: number;
  bars: number;
  confidence: number;
}

export interface PlannerPhraseSummary {
  barCount: number;
  phraseCount: number;
  strongestBoundaries: PlannerPhraseBoundarySummary[];
}

export interface PlannerBeatStabilitySummary {
  score: number;
  label: 'stable' | 'usable' | 'weak';
  beatGridQuality: number;
  transientQuality: number;
}

export interface PlannerAnalysisTrackSummary {
  trackId: string;
  source: TrackAnalysisSource;
  plannerReady: boolean;
  bpm: number | null;
  bpmConfidence: number;
  analysisConfidence: number;
  analysisQuality: AnalysisQuality;
  analysisWarnings: AnalysisWarning[];
  cues: {
    intro: PlannerCueSummary | null;
    firstDownbeat: PlannerCueSummary | null;
    outro: PlannerCueSummary | null;
  };
  energyTrend: PlannerEnergyTrendSummary;
  beatStability: PlannerBeatStabilitySummary;
  transients: PlannerTransientSummary;
  phrases: PlannerPhraseSummary;
}

export interface PlannerAnalysisSummary {
  current: PlannerAnalysisTrackSummary | null;
  next: PlannerAnalysisTrackSummary | null;
}

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
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

const buildEnergyTrend = (energyProfile: number[]): PlannerEnergyTrendSummary => {
  if (energyProfile.length === 0) {
    return {
      early: null,
      mid: null,
      late: null,
      direction: 'unknown'
    };
  }

  const third = Math.max(1, Math.floor(energyProfile.length / 3));
  const early = average(energyProfile.slice(0, third));
  const mid = average(energyProfile.slice(third, Math.min(energyProfile.length, third * 2)));
  const late = average(energyProfile.slice(Math.min(energyProfile.length, third * 2)));
  const delta = early !== null && late !== null ? late - early : 0;
  const direction =
    Math.abs(delta) < 0.12
      ? 'flat'
      : delta > 0
        ? 'rising'
        : 'falling';

  return {
    early: early === null ? null : round(clamp(early, 0, 1)),
    mid: mid === null ? null : round(clamp(mid, 0, 1)),
    late: late === null ? null : round(clamp(late, 0, 1)),
    direction
  };
};

const pickBestCue = (
  analysis: TrackAnalysis,
  types: CueCandidateType[]
): PlannerCueSummary | null => {
  const cue = analysis.cueCandidates
    .filter((candidate) => types.includes(candidate.type))
    .sort((left, right) => right.confidence - left.confidence)[0];
  if (cue) {
    return cueToSummary(cue);
  }

  if (types.includes('intro') && analysis.introCueSec !== null) {
    return {
      type: 'intro',
      startSec: round(analysis.introCueSec, 2),
      confidence: 0.42,
      label: 'Intro'
    };
  }

  if (types.includes('outro') && analysis.outroCueSec !== null) {
    return {
      type: 'outro',
      startSec: round(analysis.outroCueSec, 2),
      confidence: 0.42,
      label: 'Outro mix-out'
    };
  }

  return null;
};

const cueToSummary = (cue: CueCandidate): PlannerCueSummary => ({
  type: cue.type,
  startSec: round(cue.startSec, 2),
  confidence: round(clamp(cue.confidence, 0, 1)),
  label: cue.label
});

const buildBeatStability = (analysis: TrackAnalysis): PlannerBeatStabilitySummary => {
  const beatGridQuality = clamp(analysis.analysisQuality.beatGrid, 0, 1);
  const transientQuality = clamp(analysis.analysisQuality.transientMarkers, 0, 1);
  const score = round(
    clamp(beatGridQuality * 0.66 + transientQuality * 0.22 + analysis.bpmConfidence * 0.12, 0, 1)
  );
  const label = score >= 0.72 ? 'stable' : score >= 0.48 ? 'usable' : 'weak';

  return {
    score,
    label,
    beatGridQuality: round(beatGridQuality),
    transientQuality: round(transientQuality)
  };
};

export const buildPlannerAnalysisTrackSummary = (
  track: Track,
  analysis: TrackAnalysis | null
): PlannerAnalysisTrackSummary | null => {
  if (!analysis) {
    return null;
  }

  const durationSec = Math.max(0, track.durationSec);
  const transientCount = analysis.transientMarkers.length;
  const strongestBoundaries = [...analysis.phraseMarkers]
    .sort((left, right) => right.confidence - left.confidence)
    .slice(0, 3)
    .map((marker) => ({
      index: marker.index,
      startSec: round(marker.startSec, 2),
      bars: marker.bars,
      confidence: round(clamp(marker.confidence, 0, 1))
    }));

  return {
    trackId: analysis.trackId,
    source: analysis.source,
    plannerReady: hasPlannerReadyTrackAnalysis(analysis),
    bpm: analysis.bpm,
    bpmConfidence: round(clamp(analysis.bpmConfidence, 0, 1)),
    analysisConfidence: round(clamp(analysis.analysisConfidence, 0, 1)),
    analysisQuality: {
      waveformDetail: round(clamp(analysis.analysisQuality.waveformDetail, 0, 1)),
      spectralBands: round(clamp(analysis.analysisQuality.spectralBands, 0, 1)),
      transientMarkers: round(clamp(analysis.analysisQuality.transientMarkers, 0, 1)),
      beatGrid: round(clamp(analysis.analysisQuality.beatGrid, 0, 1))
    },
    analysisWarnings: analysis.analysisWarnings,
    cues: {
      intro: pickBestCue(analysis, ['intro']),
      firstDownbeat: pickBestCue(analysis, ['first_downbeat']),
      outro: pickBestCue(analysis, ['outro'])
    },
    energyTrend: buildEnergyTrend(analysis.energyProfile),
    beatStability: buildBeatStability(analysis),
    transients: {
      count: transientCount,
      strongCount: analysis.transientMarkers.filter((marker) => marker.strength >= 0.65).length,
      densityPerSec: durationSec > 0 ? round(transientCount / durationSec) : 0
    },
    phrases: {
      barCount: analysis.barGrid.length,
      phraseCount: analysis.phraseMarkers.length,
      strongestBoundaries
    }
  };
};

export const buildPlannerAnalysisSummary = (input: {
  currentTrack: Track;
  nextTrack: Track;
  currentAnalysis: TrackAnalysis | null;
  nextAnalysis: TrackAnalysis | null;
}): PlannerAnalysisSummary => ({
  current: buildPlannerAnalysisTrackSummary(input.currentTrack, input.currentAnalysis),
  next: buildPlannerAnalysisTrackSummary(input.nextTrack, input.nextAnalysis)
});
