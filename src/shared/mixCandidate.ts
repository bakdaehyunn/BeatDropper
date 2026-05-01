import { TrackAnalysis } from './analysis';
import { MixStyle } from './mixPlan';
import { Track } from './types';

export interface MixCandidate {
  id: string;
  currentTrackId: string;
  nextTrackId: string;
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
  const currentOutCandidates = [
    ...(input.currentAnalysis?.cueCandidates
      .filter((cue) => cue.type === 'outro' || cue.type === 'low_energy_break')
      .map((cue) => cue.startSec) ?? []),
    input.currentAnalysis?.outroCueSec,
    Math.max(0, currentDuration - 16),
    Math.max(0, currentDuration - 8)
  ].filter((value): value is number => typeof value === 'number' && Number.isFinite(value));
  const nextInCandidates = [
    ...(input.nextAnalysis?.cueCandidates
      .filter((cue) => cue.type === 'intro' || cue.type === 'first_downbeat')
      .map((cue) => cue.startSec) ?? []),
    input.nextAnalysis?.introCueSec,
    0
  ].filter((value): value is number => typeof value === 'number' && Number.isFinite(value));

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
  for (const rawOutSec of currentOutCandidates.slice(0, 4)) {
    for (const rawInSec of nextInCandidates.slice(0, 3)) {
      const currentMixOutSec = clamp(rawOutSec, 0, currentDuration);
      const nextMixInSec = clamp(rawInSec, 0, nextDuration);
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
      const cueScore =
        (input.currentAnalysis?.analysisConfidence ?? 0.2) * 0.14 +
        (input.nextAnalysis?.analysisConfidence ?? 0.2) * 0.14;
      const score = clamp(phraseScore + bpmScore + energyScore + cueScore, 0, 1);
      const style = resolveStyle(phraseAlignment, bpmDelta, energyDelta);
      candidates.push({
        id: `${input.currentTrack.id}:${Math.round(currentMixOutSec * 100)}->${input.nextTrack.id}:${Math.round(nextMixInSec * 100)}`,
        currentTrackId: input.currentTrack.id,
        nextTrackId: input.nextTrack.id,
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
        reason: buildReason({
          phraseAlignment,
          bpmDelta,
          energyDelta,
          currentBarIndex,
          nextBarIndex
        })
      });
    }
  }

  const deduped = Array.from(
    new Map(candidates.map((candidate) => [candidate.id, candidate])).values()
  )
    .sort((left, right) => right.score - left.score)
    .slice(0, input.maxCandidates ?? 5);

  return {
    currentTrackId: input.currentTrack.id,
    nextTrackId: input.nextTrack.id,
    candidates: deduped,
    recommendedCandidateId: deduped[0]?.id ?? null
  };
};
