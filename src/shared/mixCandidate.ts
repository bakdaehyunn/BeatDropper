import { TrackAnalysis } from './analysis';
import { MixStyle } from './mixPlan';
import { Track } from './types';

export type MixCandidateSource = 'analysis' | 'cue' | 'tail_fallback';
export type MixEvidenceLevel = 'strong' | 'partial' | 'fallback';
export type MixPairReadiness = 'ready' | 'analysis_pending' | 'fallback_only';

export interface MixCandidate {
  id: string;
  currentTrackId: string;
  nextTrackId: string;
  source: MixCandidateSource;
  evidenceLevel: MixEvidenceLevel;
  requiresAnalysisUpgrade: boolean;
  currentMixOutSec: number;
  nextMixInSec: number;
  currentBarIndex: number | null;
  nextBarIndex: number | null;
  phraseAlignment: 'aligned' | 'near' | 'free';
  bpmDelta: number | null;
  tempoSyncRate: number | null;
  energyDelta: number | null;
  style: MixStyle;
  score: number;
  confidence: number;
  reason: string;
}

export interface MixPairContext {
  currentTrackId: string;
  nextTrackId: string;
  candidates: MixCandidate[];
  recommendedCandidateId: string | null;
  readiness: MixPairReadiness;
}

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const nearestBarIndex = (
  analysis: TrackAnalysis | null,
  timeSec: number
): number | null => {
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
  return best.index;
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

interface CandidatePoint {
  timeSec: number;
  source: MixCandidateSource;
  evidenceLevel: MixEvidenceLevel;
  confidence: number;
  reason: string;
}

const hasDetailedAnalysis = (analysis: TrackAnalysis | null): boolean => {
  if (!analysis) {
    return false;
  }

  return (
    analysis.analysisQuality.waveformDetail >= 0.2 &&
    analysis.analysisQuality.beatGrid >= 0.35 &&
    analysis.barGrid.length > 0 &&
    analysis.energyProfile.length > 0
  );
};

const hasPendingAnalysisUpgrade = (analysis: TrackAnalysis | null): boolean => {
  return !analysis || analysis.waveformDetail.length === 0 || analysis.analysisWarnings.includes('analysis_upgrade_available');
};

const dedupePoints = (points: CandidatePoint[]): CandidatePoint[] => {
  const sorted = [...points].sort((left, right) => {
    const sourceRank = { analysis: 0, cue: 1, tail_fallback: 2 };
    return sourceRank[left.source] - sourceRank[right.source] || left.timeSec - right.timeSec;
  });
  const result: CandidatePoint[] = [];
  for (const point of sorted) {
    if (result.some((item) => Math.abs(item.timeSec - point.timeSec) < 0.75)) {
      continue;
    }
    result.push(point);
  }
  return result;
};

const buildAnalysisOutPoints = (
  analysis: TrackAnalysis | null,
  durationSec: number
): CandidatePoint[] => {
  if (!hasDetailedAnalysis(analysis) || durationSec <= 0) {
    return [];
  }

  const phrasePoints =
    analysis?.phraseMarkers
      .filter((marker) => marker.startSec >= durationSec * 0.45 && marker.startSec <= durationSec * 0.92)
      .slice(-4)
      .map((marker) => ({
        timeSec: marker.startSec,
        source: 'analysis' as const,
        evidenceLevel: marker.confidence >= 0.65 ? 'strong' as const : 'partial' as const,
        confidence: marker.confidence,
        reason: `phrase marker ${marker.index + 1}`
      })) ?? [];
  const transientPoints =
    analysis?.transientMarkers
      .filter((marker) => marker.timeSec >= durationSec * 0.45 && marker.timeSec <= durationSec * 0.9 && marker.strength >= 0.55)
      .slice(-3)
      .map((marker) => ({
        timeSec: marker.timeSec,
        source: 'analysis' as const,
        evidenceLevel: marker.strength >= 0.75 ? 'strong' as const : 'partial' as const,
        confidence: marker.strength,
        reason: `transient ${marker.index + 1}`
      })) ?? [];

  return dedupePoints([...phrasePoints, ...transientPoints]);
};

const buildAnalysisInPoints = (
  analysis: TrackAnalysis | null,
  durationSec: number
): CandidatePoint[] => {
  if (!hasDetailedAnalysis(analysis) || durationSec <= 0) {
    return [];
  }

  const phrasePoints =
    analysis?.phraseMarkers
      .filter((marker) => marker.startSec <= Math.min(48, durationSec * 0.35))
      .slice(0, 4)
      .map((marker) => ({
        timeSec: marker.startSec,
        source: 'analysis' as const,
        evidenceLevel: marker.confidence >= 0.65 ? 'strong' as const : 'partial' as const,
        confidence: marker.confidence,
        reason: `phrase marker ${marker.index + 1}`
      })) ?? [];
  const transientPoints =
    analysis?.transientMarkers
      .filter((marker) => marker.timeSec <= Math.min(48, durationSec * 0.35) && marker.strength >= 0.55)
      .slice(0, 3)
      .map((marker) => ({
        timeSec: marker.timeSec,
        source: 'analysis' as const,
        evidenceLevel: marker.strength >= 0.75 ? 'strong' as const : 'partial' as const,
        confidence: marker.strength,
        reason: `transient ${marker.index + 1}`
      })) ?? [];

  return dedupePoints([...phrasePoints, ...transientPoints]);
};

const buildCueOutPoints = (analysis: TrackAnalysis | null): CandidatePoint[] => {
  return dedupePoints([
    ...(analysis?.cueCandidates
      .filter((cue) => cue.type === 'outro' || cue.type === 'low_energy_break')
      .map((cue) => ({
        timeSec: cue.startSec,
        source: 'cue' as const,
        evidenceLevel: cue.confidence >= 0.65 ? 'strong' as const : 'partial' as const,
        confidence: cue.confidence,
        reason: cue.label
      })) ?? []),
    ...(typeof analysis?.outroCueSec === 'number'
      ? [
          {
            timeSec: analysis.outroCueSec,
            source: 'cue' as const,
            evidenceLevel: 'partial' as const,
            confidence: 0.48,
            reason: 'outro cue'
          }
        ]
      : [])
  ]);
};

const buildCueInPoints = (analysis: TrackAnalysis | null): CandidatePoint[] => {
  const cuePoints = dedupePoints([
    ...(analysis?.cueCandidates
      .filter((cue) => cue.type === 'intro' || cue.type === 'first_downbeat')
      .map((cue) => ({
        timeSec: cue.startSec,
        source: 'cue' as const,
        evidenceLevel: cue.confidence >= 0.65 ? 'strong' as const : 'partial' as const,
        confidence: cue.confidence,
        reason: cue.label
      })) ?? []),
    ...(typeof analysis?.introCueSec === 'number'
      ? [
          {
          timeSec: analysis.introCueSec,
          source: 'cue' as const,
          evidenceLevel: 'partial' as const,
          confidence: 0.48,
          reason: 'intro cue'
        }
        ]
      : []),
  ]);

  if (cuePoints.length > 0) {
    return cuePoints;
  }

  return [
    {
      timeSec: 0,
      source: 'cue' as const,
      evidenceLevel: 'partial' as const,
      confidence: 0.36,
      reason: 'track start'
    }
  ];
};

const resolvePhraseAlignment = (
  currentBarIndex: number | null,
  nextBarIndex: number | null
): MixCandidate['phraseAlignment'] => {
  if (currentBarIndex === null || nextBarIndex === null) {
    return 'free';
  }

  const currentPhrase = currentBarIndex % 8;
  const nextPhrase = nextBarIndex % 8;
  if (currentPhrase === nextPhrase) {
    return 'aligned';
  }
  return Math.abs(currentPhrase - nextPhrase) <= 1 ? 'near' : 'free';
};

const resolveStyle = (
  phraseAlignment: MixCandidate['phraseAlignment'],
  bpmDelta: number | null,
  energyDelta: number | null
): MixStyle => {
  if (bpmDelta !== null && bpmDelta > 10) {
    return 'hard_cut';
  }
  if (energyDelta !== null && energyDelta > 0.28 && phraseAlignment !== 'free') {
    return 'energy_swap';
  }
  return 'smooth_blend';
};

const buildReason = (input: {
  phraseAlignment: MixCandidate['phraseAlignment'];
  bpmDelta: number | null;
  energyDelta: number | null;
  currentBarIndex: number | null;
  nextBarIndex: number | null;
}): string => {
  const parts = [];
  if (input.currentBarIndex !== null && input.nextBarIndex !== null) {
    parts.push(`bar ${input.currentBarIndex + 1} -> ${input.nextBarIndex + 1}`);
  }
  parts.push(
    input.phraseAlignment === 'aligned'
      ? 'phrase aligned'
      : input.phraseAlignment === 'near'
        ? 'near phrase boundary'
        : 'free timing'
  );
  if (input.bpmDelta !== null) {
    parts.push(`BPM delta ${input.bpmDelta.toFixed(1)}`);
  }
  if (input.energyDelta !== null) {
    parts.push(
      input.energyDelta >= 0
        ? `energy lift ${input.energyDelta.toFixed(2)}`
        : `energy drop ${Math.abs(input.energyDelta).toFixed(2)}`
    );
  }
  return parts.join('; ');
};

export const buildMixPairContext = (input: {
  currentTrack: Track;
  nextTrack: Track;
  currentAnalysis: TrackAnalysis | null;
  nextAnalysis: TrackAnalysis | null;
  maxCandidates?: number;
}): MixPairContext => {
  const currentDuration = Math.max(0, input.currentTrack.durationSec);
  const nextDuration = Math.max(0, input.nextTrack.durationSec);
  const currentAnalysisPoints = buildAnalysisOutPoints(input.currentAnalysis, currentDuration);
  const nextAnalysisPoints = buildAnalysisInPoints(input.nextAnalysis, nextDuration);
  const currentCuePoints = buildCueOutPoints(input.currentAnalysis);
  const nextCuePoints = buildCueInPoints(input.nextAnalysis);
  const tailFallbackPoints: CandidatePoint[] = [
    {
      timeSec: Math.max(0, currentDuration - 16),
      source: 'tail_fallback',
      evidenceLevel: 'fallback',
      confidence: 0.22,
      reason: 'tail fallback -16s'
    },
    {
      timeSec: Math.max(0, currentDuration - 8),
      source: 'tail_fallback',
      evidenceLevel: 'fallback',
      confidence: 0.18,
      reason: 'tail fallback -8s'
    }
  ];
  const currentOutCandidates =
    currentAnalysisPoints.length > 0
      ? [...currentAnalysisPoints, ...currentCuePoints, ...tailFallbackPoints]
      : currentCuePoints.length > 0
        ? [...currentCuePoints, ...tailFallbackPoints]
        : tailFallbackPoints;
  const nextInCandidates =
    nextAnalysisPoints.length > 0
      ? [...nextAnalysisPoints, ...nextCuePoints]
      : nextCuePoints;
  const hasAnalysisCandidate = currentAnalysisPoints.length > 0 && nextAnalysisPoints.length > 0;
  const hasCueCandidate = currentCuePoints.length > 0 && nextCuePoints.length > 0;
  const readiness: MixPairReadiness =
    hasAnalysisCandidate || hasCueCandidate
      ? 'ready'
      : hasPendingAnalysisUpgrade(input.currentAnalysis) || hasPendingAnalysisUpgrade(input.nextAnalysis)
        ? 'analysis_pending'
        : 'fallback_only';
  const requiresAnalysisUpgrade = readiness !== 'ready';

  const bpmCurrent = input.currentAnalysis?.bpm ?? input.currentTrack.bpm ?? null;
  const bpmNext = input.nextAnalysis?.bpm ?? input.nextTrack.bpm ?? null;
  const bpmDelta =
    typeof bpmCurrent === 'number' && typeof bpmNext === 'number'
      ? Math.abs(bpmCurrent - bpmNext)
      : null;
  const tempoSyncRate =
    typeof bpmCurrent === 'number' && typeof bpmNext === 'number' && bpmNext > 0
      ? clamp(bpmCurrent / bpmNext, 0.85, 1.15)
      : null;

  const candidates: MixCandidate[] = [];
  for (const outPoint of currentOutCandidates.slice(0, 6)) {
    for (const inPoint of nextInCandidates.slice(0, 4)) {
      const currentMixOutSec = clamp(outPoint.timeSec, 0, currentDuration);
      const nextMixInSec = clamp(inPoint.timeSec, 0, nextDuration);
      const source: MixCandidateSource =
        outPoint.source === 'tail_fallback'
          ? 'tail_fallback'
          : outPoint.source === 'analysis' || inPoint.source === 'analysis'
            ? 'analysis'
            : 'cue';
      const evidenceLevel: MixEvidenceLevel =
        source === 'tail_fallback'
          ? 'fallback'
          : outPoint.evidenceLevel === 'strong' || inPoint.evidenceLevel === 'strong'
            ? 'strong'
            : 'partial';
      const currentBarIndex = nearestBarIndex(input.currentAnalysis, currentMixOutSec);
      const nextBarIndex = nearestBarIndex(input.nextAnalysis, nextMixInSec);
      const phraseAlignment = resolvePhraseAlignment(currentBarIndex, nextBarIndex);
      const currentEnergy = getEnergyAt(input.currentAnalysis, currentMixOutSec, currentDuration);
      const nextEnergy = getEnergyAt(input.nextAnalysis, nextMixInSec, nextDuration);
      const energyDelta =
        currentEnergy !== null && nextEnergy !== null ? nextEnergy - currentEnergy : null;
      const phraseScore =
        phraseAlignment === 'aligned' ? 0.28 : phraseAlignment === 'near' ? 0.16 : 0.06;
      const bpmScore =
        bpmDelta === null ? 0.08 : clamp(1 - bpmDelta / 18, 0, 1) * 0.24;
      const energyScore =
        energyDelta === null
          ? 0.08
          : clamp(1 - Math.abs(energyDelta - 0.12) / 0.5, 0, 1) * 0.2;
      const pointConfidenceScore =
        ((outPoint.confidence + inPoint.confidence) / 2) *
        (source === 'tail_fallback' ? 0.06 : 0.16);
      const analysisQualityScore =
        (input.currentAnalysis?.analysisConfidence ?? 0.2) * 0.14 +
        (input.nextAnalysis?.analysisConfidence ?? 0.2) * 0.14;
      const sourceScore = source === 'analysis' ? 0.12 : source === 'cue' ? 0.08 : -0.24;
      const evidenceScore = evidenceLevel === 'strong' ? 0.08 : evidenceLevel === 'partial' ? 0.03 : -0.08;
      const maxScore = source === 'tail_fallback' ? 0.42 : source === 'cue' ? 0.72 : 1;
      const score = clamp(
        phraseScore +
          bpmScore +
          energyScore +
          pointConfidenceScore +
          analysisQualityScore +
          sourceScore +
          evidenceScore,
        0,
        maxScore
      );
      const style = resolveStyle(phraseAlignment, bpmDelta, energyDelta);
      candidates.push({
        id: `${source}:${input.currentTrack.id}:${Math.round(currentMixOutSec * 100)}->${input.nextTrack.id}:${Math.round(nextMixInSec * 100)}`,
        currentTrackId: input.currentTrack.id,
        nextTrackId: input.nextTrack.id,
        source,
        evidenceLevel,
        requiresAnalysisUpgrade,
        currentMixOutSec,
        nextMixInSec,
        currentBarIndex,
        nextBarIndex,
        phraseAlignment,
        bpmDelta,
        tempoSyncRate,
        energyDelta,
        style,
        score,
        confidence: score,
        reason: [
          buildReason({
            phraseAlignment,
            bpmDelta,
            energyDelta,
            currentBarIndex,
            nextBarIndex
          }),
          source === 'tail_fallback' ? 'tail fallback only' : `${outPoint.reason} -> ${inPoint.reason}`
        ].join('; ')
      });
    }
  }

  const deduped = Array.from(
    new Map(candidates.map((candidate) => [candidate.id, candidate])).values()
  )
    .sort((left, right) => right.score - left.score)
    .slice(0, input.maxCandidates ?? 5);
  const recommended = deduped.find((candidate) => candidate.source !== 'tail_fallback') ?? null;

  return {
    currentTrackId: input.currentTrack.id,
    nextTrackId: input.nextTrack.id,
    candidates: deduped,
    recommendedCandidateId: recommended?.id ?? null,
    readiness
  };
};
