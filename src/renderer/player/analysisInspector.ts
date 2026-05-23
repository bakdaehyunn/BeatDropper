import {
  CueCandidate,
  hasPlannerReadyTrackAnalysis,
  PLANNER_READY_MIN_BEAT_GRID_QUALITY,
  PLANNER_READY_MIN_BPM_CONFIDENCE,
  PLANNER_READY_MIN_WAVEFORM_DETAIL_QUALITY,
  TrackAnalysis
} from '../../shared/analysis';

export type AnalysisInspectorStatus = 'pending' | 'cue_only' | 'needs_upgrade' | 'planner_ready';

export interface AnalysisInspectorIssue {
  id:
    | 'analysis_missing'
    | 'waveform_detail_low'
    | 'beat_grid_low'
    | 'bpm_confidence_low'
    | 'phrase_markers_missing'
    | 'phrase_confidence_low'
    | 'cue_confidence_low';
  label: string;
}

export interface AnalysisInspectorCueSummary {
  id: string;
  label: string;
  startSec: number;
  confidence: number;
}

export interface AnalysisInspectorSummary {
  status: AnalysisInspectorStatus;
  statusLabel: string;
  plannerReady: boolean;
  bars: number;
  transientMarkers: number;
  bpmConfidence: number | null;
  beatGridQuality: number | null;
  waveformDetailQuality: number | null;
  transientQuality: number | null;
  phraseMarkers: number;
  phraseAverageConfidence: number | null;
  phraseMaxConfidence: number | null;
  strongPhraseMarkers: number;
  cueConfidenceMin: number | null;
  cues: AnalysisInspectorCueSummary[];
  issues: AnalysisInspectorIssue[];
}

const average = (values: number[]): number | null => {
  if (values.length === 0) {
    return null;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
};

const pickBestCue = (
  analysis: TrackAnalysis,
  types: Array<CueCandidate['type']>
): CueCandidate | null => {
  const cues = analysis.cueCandidates
    .filter((cue) => types.includes(cue.type))
    .sort((left, right) => right.confidence - left.confidence);
  return cues[0] ?? null;
};

export const buildAnalysisInspectorSummary = (
  analysis: TrackAnalysis | null | undefined
): AnalysisInspectorSummary => {
  if (!analysis) {
    return {
      status: 'pending',
      statusLabel: 'Pending',
      plannerReady: false,
      bars: 0,
      transientMarkers: 0,
      bpmConfidence: null,
      beatGridQuality: null,
      waveformDetailQuality: null,
      transientQuality: null,
      phraseMarkers: 0,
      phraseAverageConfidence: null,
      phraseMaxConfidence: null,
      strongPhraseMarkers: 0,
      cueConfidenceMin: null,
      cues: [],
      issues: [{ id: 'analysis_missing', label: 'analysis missing' }]
    };
  }

  const phraseConfidences = analysis.phraseMarkers.map((marker) => marker.confidence);
  const phraseAverageConfidence = average(phraseConfidences);
  const phraseMaxConfidence =
    phraseConfidences.length > 0 ? Math.max(...phraseConfidences) : null;
  const strongPhraseMarkers = phraseConfidences.filter((confidence) => confidence >= 0.65).length;
  const cueCandidates = [
    pickBestCue(analysis, ['first_downbeat', 'intro']),
    pickBestCue(analysis, ['outro', 'low_energy_break'])
  ].filter((cue): cue is CueCandidate => cue !== null);
  const cueConfidences = cueCandidates.map((cue) => cue.confidence);
  const cueConfidenceMin =
    cueConfidences.length > 0 ? Math.min(...cueConfidences) : null;
  const plannerReady = hasPlannerReadyTrackAnalysis(analysis);
  const hasDetailedWaveform = analysis.waveformDetail.length > 0 || analysis.waveformPeaks.length > 0;
  const issues: AnalysisInspectorIssue[] = [];

  if (analysis.analysisQuality.waveformDetail < PLANNER_READY_MIN_WAVEFORM_DETAIL_QUALITY) {
    issues.push({ id: 'waveform_detail_low', label: 'waveform weak' });
  }
  if (analysis.analysisQuality.beatGrid < PLANNER_READY_MIN_BEAT_GRID_QUALITY) {
    issues.push({ id: 'beat_grid_low', label: 'beat grid weak' });
  }
  if (!analysis.bpm || analysis.bpmConfidence < PLANNER_READY_MIN_BPM_CONFIDENCE) {
    issues.push({ id: 'bpm_confidence_low', label: 'BPM weak' });
  }
  if (analysis.phraseMarkers.length === 0) {
    issues.push({ id: 'phrase_markers_missing', label: 'phrases missing' });
  } else if ((phraseMaxConfidence ?? 0) < 0.55) {
    issues.push({ id: 'phrase_confidence_low', label: 'phrases weak' });
  }
  if (cueConfidenceMin !== null && cueConfidenceMin < 0.5) {
    issues.push({ id: 'cue_confidence_low', label: 'cue confidence weak' });
  }

  const status: AnalysisInspectorStatus = plannerReady
    ? 'planner_ready'
    : hasDetailedWaveform
      ? 'needs_upgrade'
      : 'cue_only';

  return {
    status,
    statusLabel:
      status === 'planner_ready'
        ? 'Planner ready'
        : status === 'needs_upgrade'
          ? 'Needs upgrade'
          : 'Cue only',
    plannerReady,
    bars: analysis.barGrid.length,
    transientMarkers: analysis.transientMarkers.length,
    bpmConfidence: analysis.bpmConfidence,
    beatGridQuality: analysis.analysisQuality.beatGrid,
    waveformDetailQuality: analysis.analysisQuality.waveformDetail,
    transientQuality: analysis.analysisQuality.transientMarkers,
    phraseMarkers: analysis.phraseMarkers.length,
    phraseAverageConfidence,
    phraseMaxConfidence,
    strongPhraseMarkers,
    cueConfidenceMin,
    cues: cueCandidates.map((cue) => ({
      id: cue.id,
      label: cue.label,
      startSec: cue.startSec,
      confidence: cue.confidence
    })),
    issues
  };
};
