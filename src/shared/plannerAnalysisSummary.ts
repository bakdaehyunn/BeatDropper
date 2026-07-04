import {
  AnalysisQuality,
  AnalysisWarning,
  CueCandidate,
  CueCandidateOrigin,
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
  origin: CueCandidateOrigin;
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

export interface PlannerHarmonicSummary {
  key: string | null;
  mode: 'major' | 'minor' | null;
  confidence: number;
  evidence: 'strong' | 'partial' | 'fallback';
}

export interface PlannerLoudnessSummary {
  integratedRMSDb: number | null;
  peakDb: number | null;
  headroomDb: number | null;
  dynamicRangeDb: number | null;
  confidence: number;
  evidence: 'strong' | 'partial' | 'fallback';
}

export type PlannerMixWindowKind =
  | 'intro'
  | 'first_downbeat'
  | 'outro'
  | 'low_energy_break'
  | 'high_energy_drop'
  | 'phrase'
  | 'transient'
  | 'track_start';

export interface PlannerMixWindowSummary {
  kind: PlannerMixWindowKind;
  source: 'analysis' | 'cue' | 'tail_fallback';
  startSec: number;
  endSec: number;
  confidence: number;
  label: string;
}

export interface PlannerMixWindowGroupSummary {
  mixIn: PlannerMixWindowSummary[];
  mixOut: PlannerMixWindowSummary[];
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
  harmonic: PlannerHarmonicSummary;
  loudness: PlannerLoudnessSummary;
  mixWindows: PlannerMixWindowGroupSummary;
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

const buildHarmonicSummary = (analysis: TrackAnalysis): PlannerHarmonicSummary => {
  const key = analysis.musicalKey ?? null;
  if (!key) {
    return { key: null, mode: null, confidence: 0, evidence: 'fallback' };
  }
  const confidence = round(clamp(key.confidence, 0, 1));
  return {
    key: key.tonic,
    mode: key.mode,
    confidence,
    evidence: confidence >= 0.62 ? 'strong' : confidence >= 0.35 ? 'partial' : 'fallback'
  };
};

const buildLoudnessSummary = (analysis: TrackAnalysis): PlannerLoudnessSummary => {
  const loudness = analysis.loudness ?? null;
  if (!loudness) {
    return {
      integratedRMSDb: null,
      peakDb: null,
      headroomDb: null,
      dynamicRangeDb: null,
      confidence: 0,
      evidence: 'fallback'
    };
  }
  const confidence = round(clamp(loudness.confidence, 0, 1));
  return {
    integratedRMSDb: round(loudness.integratedRMSDb, 2),
    peakDb: round(loudness.peakDb, 2),
    headroomDb: round(loudness.headroomDb, 2),
    dynamicRangeDb: round(loudness.dynamicRangeDb, 2),
    confidence,
    evidence: confidence >= 0.68 ? 'strong' : confidence >= 0.45 ? 'partial' : 'fallback'
  };
};

const pickBestCue = (
  analysis: TrackAnalysis,
  types: CueCandidateType[]
): PlannerCueSummary | null => {
  const cue = analysis.cueCandidates
    .filter((candidate) => types.includes(candidate.type))
    .sort((left, right) => {
      const originRank = (cue: CueCandidate): number =>
        cue.origin === 'heuristic_placeholder' ? 1 : 0;
      return originRank(left) - originRank(right) || right.confidence - left.confidence;
    })[0];
  if (cue) {
    return cueToSummary(cue);
  }

  if (types.includes('intro') && analysis.introCueSec !== null) {
    return {
      type: 'intro',
      startSec: round(analysis.introCueSec, 2),
      confidence: 0.42,
      label: 'Intro',
      origin: 'heuristic_placeholder'
    };
  }

  if (types.includes('outro') && analysis.outroCueSec !== null) {
    return {
      type: 'outro',
      startSec: round(analysis.outroCueSec, 2),
      confidence: 0.42,
      label: 'Outro mix-out',
      origin: 'heuristic_placeholder'
    };
  }

  return null;
};

const cueToSummary = (cue: CueCandidate): PlannerCueSummary => ({
  type: cue.type,
  startSec: round(cue.startSec, 2),
  confidence: round(clamp(cue.confidence, 0, 1)),
  label: cue.label,
  origin: cue.origin
});

const sourceRank = (source: PlannerMixWindowSummary['source']): number => {
  if (source === 'cue') {
    return 0;
  }
  if (source === 'analysis') {
    return 1;
  }
  return 2;
};

const mixWindowSpan = (analysis: TrackAnalysis, durationSec: number): number => {
  const barIntervals = analysis.barGrid
    .slice(1)
    .map((marker, index) => marker.startSec - analysis.barGrid[index].startSec)
    .filter((interval) => Number.isFinite(interval) && interval > 0.5 && interval < 20);
  const averageBar = average(barIntervals);
  if (averageBar !== null) {
    return clamp(averageBar * 2, 4, 16);
  }
  return clamp(durationSec * 0.05, 4, 12);
};

const buildWindow = (input: {
  kind: PlannerMixWindowKind;
  source: PlannerMixWindowSummary['source'];
  startSec: number;
  durationSec: number;
  spanSec: number;
  confidence: number;
  label: string;
}): PlannerMixWindowSummary => {
  const safeStart = clamp(input.startSec, 0, input.durationSec);
  return {
    kind: input.kind,
    source: input.source,
    startSec: round(safeStart, 2),
    endSec: round(clamp(safeStart + input.spanSec, safeStart + 0.25, input.durationSec), 2),
    confidence: round(clamp(input.confidence, 0, 1)),
    label: input.label
  };
};

const cueWindow = (
  cue: CueCandidate,
  durationSec: number,
  spanSec: number
): PlannerMixWindowSummary => {
  const startSec = clamp(cue.startSec, 0, durationSec);
  const preferredEnd = cue.endSec > cue.startSec ? cue.endSec : cue.startSec + spanSec;
  return {
    kind: cue.type,
    source: 'cue',
    startSec: round(startSec, 2),
    endSec: round(clamp(preferredEnd, startSec + 0.25, Math.min(durationSec, startSec + spanSec)), 2),
    confidence: round(clamp(cue.confidence, 0, 1)),
    label: cue.label
  };
};

const dedupeWindows = (windows: PlannerMixWindowSummary[]): PlannerMixWindowSummary[] => {
  const sorted = [...windows].sort((left, right) => {
    const sourceDelta = sourceRank(left.source) - sourceRank(right.source);
    if (sourceDelta !== 0) {
      return sourceDelta;
    }
    return right.confidence - left.confidence || left.startSec - right.startSec;
  });
  const result: PlannerMixWindowSummary[] = [];
  for (const window of sorted) {
    if (result.some((item) => Math.abs(item.startSec - window.startSec) < 0.75)) {
      continue;
    }
    result.push(window);
  }
  return result;
};

const buildMixWindows = (
  analysis: TrackAnalysis,
  durationSec: number
): PlannerMixWindowGroupSummary => {
  if (durationSec <= 0) {
    return { mixIn: [], mixOut: [] };
  }

  const spanSec = mixWindowSpan(analysis, durationSec);
  const earlyLimit = Math.min(48, durationSec * 0.35);
  const mixIn: PlannerMixWindowSummary[] = [
    ...analysis.cueCandidates
      .filter((cue) => cue.type === 'intro' || cue.type === 'first_downbeat')
      .map((cue) => cueWindow(cue, durationSec, spanSec))
  ];
  if (mixIn.length === 0 && analysis.introCueSec !== null) {
    mixIn.push(buildWindow({
      kind: 'intro',
      source: 'cue',
      startSec: analysis.introCueSec,
      durationSec,
      spanSec,
      confidence: 0.42,
      label: 'Intro'
    }));
  }
  if (mixIn.length === 0) {
    mixIn.push(buildWindow({
      kind: 'track_start',
      source: 'cue',
      startSec: 0,
      durationSec,
      spanSec,
      confidence: 0.34,
      label: 'Track start'
    }));
  }
  mixIn.push(
    ...analysis.phraseMarkers
      .filter((marker) => marker.startSec <= earlyLimit)
      .slice(0, 4)
      .map((marker) => buildWindow({
        kind: 'phrase',
        source: 'analysis',
        startSec: marker.startSec,
        durationSec,
        spanSec,
        confidence: marker.confidence,
        label: `Phrase marker ${marker.index + 1}`
      })),
    ...analysis.transientMarkers
      .filter((marker) => marker.timeSec <= earlyLimit && marker.strength >= 0.55)
      .slice(0, 3)
      .map((marker) => buildWindow({
        kind: 'transient',
        source: 'analysis',
        startSec: marker.timeSec,
        durationSec,
        spanSec: Math.min(spanSec, 6),
        confidence: marker.strength,
        label: `Transient ${marker.index + 1}`
      }))
  );

  const mixOut: PlannerMixWindowSummary[] = [
    ...analysis.cueCandidates
      .filter((cue) => cue.type === 'outro' || cue.type === 'low_energy_break')
      .map((cue) => cueWindow(cue, durationSec, spanSec))
  ];
  if (analysis.outroCueSec !== null) {
    mixOut.push(buildWindow({
      kind: 'outro',
      source: 'cue',
      startSec: analysis.outroCueSec,
      durationSec,
      spanSec,
      confidence: 0.42,
      label: 'Outro mix-out'
    }));
  }
  mixOut.push(
    ...analysis.phraseMarkers
      .filter((marker) => marker.startSec >= durationSec * 0.45 && marker.startSec <= durationSec * 0.92)
      .slice(-4)
      .map((marker) => buildWindow({
        kind: 'phrase',
        source: 'analysis',
        startSec: marker.startSec,
        durationSec,
        spanSec,
        confidence: marker.confidence,
        label: `Phrase marker ${marker.index + 1}`
      })),
    ...analysis.transientMarkers
      .filter((marker) => marker.timeSec >= durationSec * 0.45 && marker.timeSec <= durationSec * 0.9 && marker.strength >= 0.55)
      .slice(-3)
      .map((marker) => buildWindow({
        kind: 'transient',
        source: 'analysis',
        startSec: marker.timeSec,
        durationSec,
        spanSec: Math.min(spanSec, 6),
        confidence: marker.strength,
        label: `Transient ${marker.index + 1}`
      }))
  );

  return {
    mixIn: dedupeWindows(mixIn).slice(0, 5),
    mixOut: dedupeWindows(mixOut).slice(0, 5)
  };
};

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
      beatGrid: round(clamp(analysis.analysisQuality.beatGrid, 0, 1)),
      harmonicKey: round(clamp(analysis.analysisQuality.harmonicKey ?? 0, 0, 1))
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
    },
    harmonic: buildHarmonicSummary(analysis),
    loudness: buildLoudnessSummary(analysis),
    mixWindows: buildMixWindows(analysis, durationSec)
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
