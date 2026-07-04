import {
  BarMarker,
  PhraseMarker,
  TRACK_ANALYSIS_SCHEMA_VERSION,
  sanitizeTrackAnalysis,
  SpectralBandPoint,
  TrackAnalysis,
  TransientMarker,
  WaveformDetailPoint
} from '../../shared/analysis';
import { Track } from '../../shared/types';
import { AudioBufferForBpm, estimateTrackBpm } from './bpmEstimator';
import { buildSpectralBandsFromAudioBuffer } from './spectralAnalysis';

const WAVEFORM_BUCKETS = 160;
const WAVEFORM_DETAIL_MAX_BUCKETS = 1200;
const WAVEFORM_DETAIL_BUCKETS_PER_SEC = 12;
const ENERGY_BUCKETS = 64;
const MIN_VALID_BPM = 60;
const MAX_VALID_BPM = 200;
const DERIVED_BPM_CONFIDENCE_PRIORITY = 0.58;
const BPM_MISMATCH_DELTA = 3;

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const readMonoSample = (buffer: AudioBufferForBpm, sampleIndex: number): number => {
  let sum = 0;
  const channels = Math.max(1, buffer.numberOfChannels);
  for (let channel = 0; channel < channels; channel += 1) {
    sum += buffer.getChannelData(channel)[sampleIndex] ?? 0;
  }
  return sum / channels;
};

const buildWaveformPeaks = (buffer: AudioBufferForBpm) => {
  const totalSamples = Math.max(0, Math.floor(buffer.duration * buffer.sampleRate));
  const bucketCount = Math.min(WAVEFORM_BUCKETS, Math.max(1, Math.floor(buffer.duration * 2)));
  const samplesPerBucket = Math.max(1, Math.floor(totalSamples / bucketCount));

  return Array.from({ length: bucketCount }, (_, bucketIndex) => {
    const start = bucketIndex * samplesPerBucket;
    const end = Math.min(totalSamples, start + samplesPerBucket);
    let peak = 0;
    let sumSquares = 0;
    let count = 0;
    for (let sampleIndex = start; sampleIndex < end; sampleIndex += 1) {
      const sample = readMonoSample(buffer, sampleIndex);
      peak = Math.max(peak, Math.abs(sample));
      sumSquares += sample * sample;
      count += 1;
    }
    return {
      timeSec: (start / Math.max(1, totalSamples)) * buffer.duration,
      peak: clamp(peak, 0, 1),
      rms: count > 0 ? clamp(Math.sqrt(sumSquares / count), 0, 1) : 0
    };
  });
};

const buildEnergyProfile = (buffer: AudioBufferForBpm): number[] => {
  const totalSamples = Math.max(0, Math.floor(buffer.duration * buffer.sampleRate));
  const bucketCount = Math.min(ENERGY_BUCKETS, Math.max(1, Math.floor(buffer.duration)));
  const samplesPerBucket = Math.max(1, Math.floor(totalSamples / bucketCount));
  const values = Array.from({ length: bucketCount }, (_, bucketIndex) => {
    const start = bucketIndex * samplesPerBucket;
    const end = Math.min(totalSamples, start + samplesPerBucket);
    let sumSquares = 0;
    let count = 0;
    for (let sampleIndex = start; sampleIndex < end; sampleIndex += 1) {
      const sample = readMonoSample(buffer, sampleIndex);
      sumSquares += sample * sample;
      count += 1;
    }
    return count > 0 ? Math.sqrt(sumSquares / count) : 0;
  });
  const max = Math.max(1e-6, ...values);
  return values.map((value) => clamp(value / max, 0, 1));
};

const buildWaveformDetail = (buffer: AudioBufferForBpm): WaveformDetailPoint[] => {
  const totalSamples = Math.max(0, Math.floor(buffer.duration * buffer.sampleRate));
  const bucketCount = Math.min(
    WAVEFORM_DETAIL_MAX_BUCKETS,
    Math.max(WAVEFORM_BUCKETS, Math.floor(buffer.duration * WAVEFORM_DETAIL_BUCKETS_PER_SEC))
  );
  const samplesPerBucket = Math.max(1, Math.floor(totalSamples / bucketCount));

  return Array.from({ length: bucketCount }, (_, bucketIndex) => {
    const start = bucketIndex * samplesPerBucket;
    const end = Math.min(totalSamples, start + samplesPerBucket);
    let min = 0;
    let max = 0;
    let peak = 0;
    let sumSquares = 0;
    let count = 0;
    for (let sampleIndex = start; sampleIndex < end; sampleIndex += 1) {
      const sample = readMonoSample(buffer, sampleIndex);
      min = Math.min(min, sample);
      max = Math.max(max, sample);
      peak = Math.max(peak, Math.abs(sample));
      sumSquares += sample * sample;
      count += 1;
    }

    return {
      timeSec: (start / Math.max(1, totalSamples)) * buffer.duration,
      peak: clamp(peak, 0, 1),
      rms: count > 0 ? clamp(Math.sqrt(sumSquares / count), 0, 1) : 0,
      min: clamp(min, -1, 1),
      max: clamp(max, -1, 1)
    };
  });
};

interface OnsetEnvelopePoint {
  timeSec: number;
  strength: number;
}

const normalizeScores = (values: number[]): number[] => {
  const max = Math.max(1e-6, ...values);
  return values.map((value) => clamp(value / max, 0, 1));
};

const smoothScores = (values: number[], radius = 1): number[] => {
  if (values.length <= 2 || radius <= 0) {
    return values;
  }

  return values.map((_value, index) => {
    let sum = 0;
    let count = 0;
    for (let offset = -radius; offset <= radius; offset += 1) {
      const value = values[index + offset];
      if (typeof value === 'number') {
        sum += value;
        count += 1;
      }
    }
    return count > 0 ? sum / count : values[index];
  });
};

const resolveBandAt = (
  spectralBands: SpectralBandPoint[],
  waveformLength: number,
  index: number
): SpectralBandPoint | null => {
  if (spectralBands.length === 0) {
    return null;
  }
  if (spectralBands.length === waveformLength) {
    return spectralBands[index] ?? null;
  }
  const spectralIndex = Math.round(
    (index / Math.max(1, waveformLength - 1)) * (spectralBands.length - 1)
  );
  return spectralBands[clamp(spectralIndex, 0, spectralBands.length - 1)] ?? null;
};

const buildOnsetEnvelope = (
  waveformDetail: WaveformDetailPoint[],
  spectralBands: SpectralBandPoint[],
  durationSec: number
): OnsetEnvelopePoint[] => {
  if (waveformDetail.length < 4 || durationSec <= 0) {
    return [];
  }

  const onsetEvidence = waveformDetail.map((point, index) => {
    const previous = waveformDetail[Math.max(0, index - 1)]?.rms ?? 0;
    const previousPoint = waveformDetail[Math.max(0, index - 1)] ?? point;
    const band = resolveBandAt(spectralBands, waveformDetail.length, index);
    const previousBand = resolveBandAt(spectralBands, waveformDetail.length, Math.max(0, index - 1)) ?? band;
    const spectralFlux =
      band && previousBand
        ? Math.max(0, band.high - previousBand.high) * 0.56 +
          Math.max(0, band.mid - previousBand.mid) * 0.32 +
          Math.max(0, band.low - previousBand.low) * 0.12
        : 0;

    return {
      timeSec: point.timeSec,
      rmsRise: Math.max(0, point.rms - previous),
      peakRise: Math.max(0, point.peak - previousPoint.peak),
      spectralFlux
    };
  });
  const rmsScores = normalizeScores(onsetEvidence.map((item) => item.rmsRise));
  const peakScores = normalizeScores(onsetEvidence.map((item) => item.peakRise));
  const spectralScores = normalizeScores(onsetEvidence.map((item) => item.spectralFlux));
  const rawEnvelope = onsetEvidence.map((item, index) =>
    clamp(
      rmsScores[index] * 0.34 +
        peakScores[index] * 0.1 +
        spectralScores[index] * 0.56,
      0,
      1
    )
  );
  const smoothedEnvelope = smoothScores(rawEnvelope, 1);

  return onsetEvidence.map((item, index) => ({
    timeSec: item.timeSec,
    strength: clamp(Math.max(rawEnvelope[index], smoothedEnvelope[index] * 0.92), 0, 1)
  }));
};

const buildTransientMarkers = (
  onsetEnvelope: OnsetEnvelopePoint[],
  durationSec: number
): TransientMarker[] => {
  if (onsetEnvelope.length < 4 || durationSec <= 0) {
    return [];
  }

  const markers: TransientMarker[] = [];
  let lastTimeSec = -Infinity;
  const strengths = onsetEnvelope.map((point) => point.strength);
  const localAverage = smoothScores(strengths, 3);

  onsetEnvelope.forEach((point, index) => {
    const strength = point.strength;
    const previousStrength = strengths[Math.max(0, index - 1)] ?? 0;
    const nextStrength = strengths[Math.min(strengths.length - 1, index + 1)] ?? 0;
    const isLocalPeak = strength >= previousStrength && strength >= nextStrength;
    const adaptiveThreshold = Math.max(0.38, (localAverage[index] ?? 0) + 0.08);
    if (!isLocalPeak || strength < adaptiveThreshold || point.timeSec - lastTimeSec < 0.18) {
      return;
    }
    markers.push({
      index: markers.length,
      timeSec: point.timeSec,
      strength
    });
    lastTimeSec = point.timeSec;
  });

  return markers.slice(0, 256);
};

const normalizeBpm = (candidate: number | null | undefined): number | null => {
  if (
    typeof candidate !== 'number' ||
    !Number.isFinite(candidate) ||
    candidate < MIN_VALID_BPM ||
    candidate > MAX_VALID_BPM
  ) {
    return null;
  }
  return candidate;
};

const resolveAnalysisBpm = (
  track: Track,
  estimate: ReturnType<typeof estimateTrackBpm>
): { bpm: number | null; source: 'metadata' | 'derived'; metadataMismatch: boolean } => {
  const metadataBpm = normalizeBpm(track.bpm);
  const derivedBpm = normalizeBpm(estimate.bpm);
  const metadataMismatch =
    metadataBpm !== null && derivedBpm !== null && Math.abs(metadataBpm - derivedBpm) > BPM_MISMATCH_DELTA;

  if (
    derivedBpm !== null &&
    (metadataBpm === null ||
      (estimate.confidence >= DERIVED_BPM_CONFIDENCE_PRIORITY && metadataMismatch))
  ) {
    return {
      bpm: derivedBpm,
      source: 'derived',
      metadataMismatch
    };
  }

  if (metadataBpm !== null) {
    return {
      bpm: metadataBpm,
      source: 'metadata',
      metadataMismatch
    };
  }

  return {
    bpm: derivedBpm,
    source: 'derived',
    metadataMismatch
  };
};

const findNearestBeatTime = (timeSec: number, beatOffsetSec: number, beatIntervalSec: number): number => {
  const beatIndex = Math.round((timeSec - beatOffsetSec) / beatIntervalSec);
  return beatOffsetSec + beatIndex * beatIntervalSec;
};

const scoreBeatPhase = (
  phaseOffsetSec: number,
  beatIntervalSec: number,
  transientMarkers: TransientMarker[]
): number => {
  if (transientMarkers.length === 0) {
    return 0;
  }

  const windowSec = Math.min(0.14, beatIntervalSec * 0.3);
  let score = 0;
  let weight = 0;
  for (const marker of transientMarkers.slice(0, 160)) {
    const nearest = findNearestBeatTime(marker.timeSec, phaseOffsetSec, beatIntervalSec);
    const distance = Math.abs(nearest - marker.timeSec);
    weight += marker.strength;
    if (distance <= windowSec) {
      score += marker.strength * (1 - distance / windowSec);
    }
  }

  return weight > 0 ? score / weight : 0;
};

const resolveBeatPhaseOffset = (
  beatIntervalSec: number,
  transientMarkers: TransientMarker[]
): { offsetSec: number; confidence: number } => {
  if (beatIntervalSec <= 0) {
    return { offsetSec: 0, confidence: 0 };
  }

  const candidates = new Set<number>([0]);
  for (const marker of transientMarkers.filter((item) => item.strength >= 0.45).slice(0, 80)) {
    const modulo = marker.timeSec % beatIntervalSec;
    candidates.add(modulo);
  }

  let bestOffsetSec = 0;
  let bestScore = scoreBeatPhase(0, beatIntervalSec, transientMarkers);
  for (const candidate of candidates) {
    const score = scoreBeatPhase(candidate, beatIntervalSec, transientMarkers);
    if (score > bestScore) {
      bestScore = score;
      bestOffsetSec = candidate;
    }
  }

  return {
    offsetSec: bestOffsetSec,
    confidence: clamp(bestScore, 0, 1)
  };
};

const buildBeatGrid = (
  durationSec: number,
  beatIntervalSec: number,
  beatOffsetSec: number
): number[] => {
  const beatGrid: number[] = [];
  let current = beatOffsetSec;
  while (current > 0) {
    current -= beatIntervalSec;
  }
  while (current < 0) {
    current += beatIntervalSec;
  }

  for (let timeSec = current; timeSec <= durationSec + 0.001; timeSec += beatIntervalSec) {
    beatGrid.push(Number(timeSec.toFixed(4)));
    if (beatGrid.length >= 2200) {
      break;
    }
  }

  return beatGrid;
};

const scoreDownbeatPhase = (
  beatGridSec: number[],
  phase: number,
  transientMarkers: TransientMarker[],
  energyProfile: number[],
  durationSec: number
): number => {
  const bars = beatGridSec.filter((_beat, index) => index % 4 === phase);
  if (bars.length === 0) {
    return 0;
  }

  const windowSec = 0.16;
  let score = 0;
  for (const barStartSec of bars.slice(0, 96)) {
    const transientScore = transientMarkers.reduce((sum, marker) => {
      const distance = Math.abs(marker.timeSec - barStartSec);
      return distance <= windowSec
        ? sum + marker.strength * (1 - distance / windowSec)
        : sum;
    }, 0);
    const energyIndex = durationSec > 0
      ? Math.min(
          energyProfile.length - 1,
          Math.max(0, Math.floor((barStartSec / durationSec) * energyProfile.length))
        )
      : 0;
    const energyScore = energyProfile[energyIndex] ?? 0;
    score += transientScore + energyScore * 0.12;
  }

  return score / Math.max(1, bars.length);
};

const buildDownbeatGrid = (
  beatGridSec: number[],
  transientMarkers: TransientMarker[],
  energyProfile: number[],
  durationSec: number
): { downbeatsSec: number[]; barGrid: BarMarker[]; confidence: number } => {
  if (beatGridSec.length === 0) {
    return {
      downbeatsSec: [],
      barGrid: [],
      confidence: 0
    };
  }

  const phaseScores = Array.from({ length: 4 }, (_item, phase) => ({
    phase,
    score: scoreDownbeatPhase(beatGridSec, phase, transientMarkers, energyProfile, durationSec)
  }));
  const rankedScores = [...phaseScores].sort((left, right) => right.score - left.score);
  const best = rankedScores[0] ?? { phase: 0, score: 0 };
  const second = rankedScores[1] ?? { phase: 0, score: 0 };
  const bestPhase = best.phase;
  const bestScore = best.score;
  const phaseSeparation =
    bestScore > 0 ? clamp((bestScore - second.score) / bestScore, 0, 1) : 0;
  const evidenceConfidence = clamp(bestScore, 0, 1);
  const confidence = clamp(evidenceConfidence * 0.45 + phaseSeparation * 0.55, 0, 1);

  const downbeatsSec = beatGridSec.filter((_beat, index) => index % 4 === bestPhase);
  const barGrid = downbeatsSec.map((startSec, index) => ({
    index,
    startSec,
    beatIndex: bestPhase + index * 4
  }));

  return {
    downbeatsSec,
    barGrid,
    confidence
  };
};

const scoreTransientMarkerQuality = (input: {
  transientMarkers: TransientMarker[];
  beatGridSec: number[];
  durationSec: number;
  beatPhaseConfidence: number;
  downbeatConfidence: number;
}): number => {
  if (input.transientMarkers.length === 0 || input.durationSec <= 0) {
    return 0;
  }

  const averageStrength =
    input.transientMarkers.reduce((sum, marker) => sum + clamp(marker.strength, 0, 1), 0) /
    input.transientMarkers.length;
  const markerDensity = input.transientMarkers.length / Math.max(1, input.durationSec);
  const expectedBeatDensity =
    input.beatGridSec.length > 0
      ? input.beatGridSec.length / Math.max(1, input.durationSec)
      : 2;
  const densityRatio = markerDensity / Math.max(0.25, expectedBeatDensity);
  const densityScore = clamp(
    densityRatio <= 1 ? densityRatio : 1 - (densityRatio - 1) / 3,
    0,
    1
  );
  const beatAlignmentScore =
    input.beatGridSec.length > 0
      ? (() => {
          const windowSec = 0.14;
          let score = 0;
          let weight = 0;
          for (const marker of input.transientMarkers.slice(0, 256)) {
            let bestDistance = Infinity;
            for (const beatSec of input.beatGridSec) {
              const distance = Math.abs(marker.timeSec - beatSec);
              if (distance < bestDistance) {
                bestDistance = distance;
              }
              if (beatSec > marker.timeSec + windowSec) {
                break;
              }
            }
            const markerWeight = clamp(marker.strength, 0, 1);
            weight += markerWeight;
            if (bestDistance <= windowSec) {
              score += markerWeight * (1 - bestDistance / windowSec);
            }
          }
          return weight > 0 ? score / weight : 0;
        })()
      : 0;

  return clamp(
    densityScore * 0.18 +
      averageStrength * 0.18 +
      beatAlignmentScore * 0.28 +
      input.beatPhaseConfidence * 0.2 +
      input.downbeatConfidence * 0.16,
    0,
    1
  );
};

const scoreBeatGridStability = (input: {
  beatGridSec: number[];
  onsetEnvelope: OnsetEnvelopePoint[];
  beatPhaseConfidence: number;
  durationSec: number;
}): { score: number; coverage: number; drift: number } => {
  if (input.beatGridSec.length === 0 || input.onsetEnvelope.length === 0 || input.durationSec <= 0) {
    return { score: 0, coverage: 0, drift: 1 };
  }

  const onsetByTime = input.onsetEnvelope;
  const windowSec = 0.16;
  const sampleBeats = input.beatGridSec.filter(
    (beatSec) => beatSec >= 0 && beatSec <= input.durationSec
  );
  let covered = 0;
  let weightedDistance = 0;
  let weight = 0;

  for (const beatSec of sampleBeats.slice(0, 512)) {
    let bestStrength = 0;
    let bestDistance = windowSec;
    for (const onset of onsetByTime) {
      const distance = Math.abs(onset.timeSec - beatSec);
      if (distance > windowSec) {
        if (onset.timeSec > beatSec + windowSec) {
          break;
        }
        continue;
      }
      const weightedStrength = onset.strength * (1 - distance / windowSec);
      if (weightedStrength > bestStrength) {
        bestStrength = weightedStrength;
        bestDistance = distance;
      }
    }

    if (bestStrength >= 0.2) {
      covered += 1;
      weightedDistance += bestDistance * bestStrength;
      weight += bestStrength;
    }
  }

  const coverage = sampleBeats.length > 0 ? covered / sampleBeats.length : 0;
  const averageDistance = weight > 0 ? weightedDistance / weight : windowSec;
  const drift = clamp(averageDistance / windowSec, 0, 1);
  const score = clamp(
    coverage * 0.46 +
      (1 - drift) * 0.28 +
      input.beatPhaseConfidence * 0.26,
    0,
    1
  );

  return {
    score,
    coverage: clamp(coverage, 0, 1),
    drift
  };
};

const findNearestBar = (barGrid: BarMarker[], timeSec: number): BarMarker | null => {
  if (barGrid.length === 0) {
    return null;
  }

  let best = barGrid[0];
  let distance = Math.abs(best.startSec - timeSec);
  for (const marker of barGrid) {
    const nextDistance = Math.abs(marker.startSec - timeSec);
    if (nextDistance < distance) {
      best = marker;
      distance = nextDistance;
    }
  }
  return best;
};

const snapToBar = (
  barGrid: BarMarker[],
  timeSec: number,
  direction: 'nearest' | 'before' | 'after',
  maxDistanceSec = 8
): number => {
  if (barGrid.length === 0) {
    return timeSec;
  }

  const candidates = barGrid.filter((marker) => {
    if (direction === 'before') {
      return marker.startSec <= timeSec;
    }
    if (direction === 'after') {
      return marker.startSec >= timeSec;
    }
    return true;
  });
  const marker = findNearestBar(candidates.length > 0 ? candidates : barGrid, timeSec);
  if (!marker || Math.abs(marker.startSec - timeSec) > maxDistanceSec) {
    return timeSec;
  }

  return marker.startSec;
};

const findEnergyTime = (
  energyProfile: number[],
  durationSec: number,
  mode: 'min' | 'max',
  startRatio: number,
  endRatio: number
): number | null => {
  if (energyProfile.length === 0 || durationSec <= 0) {
    return null;
  }
  const start = Math.max(0, Math.floor(energyProfile.length * startRatio));
  const end = Math.min(energyProfile.length - 1, Math.ceil(energyProfile.length * endRatio));
  let bestIndex = start;
  let bestValue = energyProfile[start] ?? 0;
  for (let index = start; index <= end; index += 1) {
    const value = energyProfile[index] ?? 0;
    if ((mode === 'min' && value < bestValue) || (mode === 'max' && value > bestValue)) {
      bestIndex = index;
      bestValue = value;
    }
  }
  return (bestIndex / Math.max(1, energyProfile.length - 1)) * durationSec;
};

const getEnergyAtTime = (
  energyProfile: number[],
  durationSec: number,
  timeSec: number
): number | null => {
  if (energyProfile.length === 0 || durationSec <= 0) {
    return null;
  }

  const index = clamp(
    Math.round((timeSec / durationSec) * (energyProfile.length - 1)),
    0,
    energyProfile.length - 1
  );
  return energyProfile[index] ?? null;
};

const getSpectralBandAtTime = (
  spectralBands: SpectralBandPoint[],
  durationSec: number,
  timeSec: number
): SpectralBandPoint | null => {
  if (spectralBands.length === 0 || durationSec <= 0) {
    return null;
  }
  const index = clamp(
    Math.round((timeSec / durationSec) * (spectralBands.length - 1)),
    0,
    spectralBands.length - 1
  );
  return spectralBands[index] ?? null;
};

const getEnergyWindowAverage = (
  energyProfile: number[],
  durationSec: number,
  startSec: number,
  endSec: number
): number | null => {
  if (energyProfile.length === 0 || durationSec <= 0) {
    return null;
  }

  const clampedStartSec = clamp(startSec, 0, durationSec);
  const clampedEndSec = clamp(endSec, 0, durationSec);
  if (clampedEndSec <= clampedStartSec) {
    return null;
  }

  let weightedSum = 0;
  let weight = 0;
  for (let index = 0; index < energyProfile.length; index += 1) {
    const bucketStartSec = (index / energyProfile.length) * durationSec;
    const bucketEndSec = ((index + 1) / energyProfile.length) * durationSec;
    const overlapSec =
      Math.min(bucketEndSec, clampedEndSec) - Math.max(bucketStartSec, clampedStartSec);
    if (overlapSec <= 0) {
      continue;
    }
    weightedSum += (energyProfile[index] ?? 0) * overlapSec;
    weight += overlapSec;
  }

  return weight > 0 ? weightedSum / weight : null;
};

const getTransientWeightDensity = (
  transientMarkers: TransientMarker[],
  durationSec: number,
  startSec: number,
  endSec: number
): number | null => {
  const clampedStartSec = clamp(startSec, 0, durationSec);
  const clampedEndSec = clamp(endSec, 0, durationSec);
  if (durationSec <= 0 || clampedEndSec <= clampedStartSec) {
    return null;
  }

  const totalStrength = transientMarkers.reduce((sum, marker) => {
    return marker.timeSec >= clampedStartSec && marker.timeSec < clampedEndSec
      ? sum + clamp(marker.strength, 0, 1)
      : sum;
  }, 0);

  return totalStrength / Math.max(0.001, clampedEndSec - clampedStartSec);
};

const scorePhraseMarkerConfidence = (input: {
  bar: BarMarker;
  beatIntervalSec: number | null;
  beatGridQuality: number;
  bpmConfidence: number;
  downbeatConfidence: number;
  durationSec: number;
  energyProfile: number[];
  transientMarkers: TransientMarker[];
}): number => {
  const phraseLengthSec = input.beatIntervalSec !== null ? input.beatIntervalSec * 32 : 16;
  const windowSec = clamp(phraseLengthSec * 0.5, 6, 18);
  const beforeStartSec = input.bar.startSec - windowSec;
  const beforeEndSec = input.bar.startSec;
  const afterStartSec = input.bar.startSec;
  const afterEndSec = input.bar.startSec + windowSec;
  const beforeEnergy = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    beforeStartSec,
    beforeEndSec
  );
  const afterEnergy = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    afterStartSec,
    afterEndSec
  );
  const beforeDensity = getTransientWeightDensity(
    input.transientMarkers,
    input.durationSec,
    beforeStartSec,
    beforeEndSec
  );
  const afterDensity = getTransientWeightDensity(
    input.transientMarkers,
    input.durationSec,
    afterStartSec,
    afterEndSec
  );
  const energyDelta =
    beforeEnergy !== null && afterEnergy !== null ? Math.abs(afterEnergy - beforeEnergy) : 0;
  const densityDelta =
    beforeDensity !== null && afterDensity !== null
      ? Math.abs(afterDensity - beforeDensity)
      : 0;
  const sectionChangeScore =
    clamp((energyDelta - 0.08) / 0.28, 0, 1) * 0.2 +
    clamp((densityDelta - 0.12) / 0.42, 0, 1) * 0.1;
  const startBoundaryScore = input.bar.index === 0 ? 0.03 : 0;

  return clamp(
    0.16 +
      input.bpmConfidence * 0.18 +
      input.beatGridQuality * 0.2 +
      input.downbeatConfidence * 0.18 +
      sectionChangeScore +
      startBoundaryScore,
    0,
    0.88
  );
};

const resolveOutroCue = (input: {
  barGrid: BarMarker[];
  beatIntervalSec: number | null;
  beatGridQuality: number;
  downbeatConfidence: number;
  durationSec: number;
  energyProfile: number[];
  transientMarkers: TransientMarker[];
}): {
  startSec: number;
  rawEnergySec: number;
  confidence: number;
  phraseAligned: boolean;
  derived: boolean;
} => {
  const minRemainingSec = clamp(input.durationSec * 0.14, 8, 24);
  const earliestSec = Math.max(0, input.durationSec * 0.55);
  const latestSec = Math.max(earliestSec, input.durationSec - minRemainingSec);
  const rawEnergySec =
    findEnergyTime(
      input.energyProfile,
      input.durationSec,
      'min',
      earliestSec / Math.max(1, input.durationSec),
      latestSec / Math.max(1, input.durationSec)
    ) ?? Math.max(0, latestSec);
  const fallbackSec = snapToBar(
    input.barGrid,
    Math.min(rawEnergySec, latestSec),
    'before',
    input.beatIntervalSec ?? 4
  );

  const candidates = input.barGrid.filter(
    (bar) => bar.startSec >= earliestSec && bar.startSec <= latestSec
  );
  if (candidates.length === 0) {
    const energy = getEnergyAtTime(input.energyProfile, input.durationSec, fallbackSec);
    return {
      startSec: fallbackSec,
      rawEnergySec,
      confidence: clamp(
        0.34 +
          input.beatGridQuality * 0.18 +
          input.downbeatConfidence * 0.08 +
          (energy !== null ? (1 - energy) * 0.18 : 0),
        0,
        0.68
      ),
      phraseAligned: false,
      derived: false
    };
  }

  const maxDistanceSec = Math.max(input.beatIntervalSec ?? 1, 16);
  let selected = candidates[0];
  let selectedScore = -Infinity;
  for (const candidate of candidates) {
    const energy = getEnergyAtTime(input.energyProfile, input.durationSec, candidate.startSec);
    const distanceScore = clamp(1 - Math.abs(candidate.startSec - rawEnergySec) / maxDistanceSec, 0, 1);
    const lowEnergyScore = energy !== null ? 1 - energy : 0.35;
    const phraseScore = candidate.index % 8 === 0 ? 1 : candidate.index % 4 === 0 ? 0.55 : 0;
    const remainingSec = input.durationSec - candidate.startSec;
    const remainingScore = clamp(remainingSec / Math.max(1, minRemainingSec * 1.5), 0, 1);
    const score =
      lowEnergyScore * 0.32 +
      distanceScore * 0.18 +
      phraseScore * 0.28 +
      remainingScore * 0.12 +
      input.downbeatConfidence * 0.1;

    if (score > selectedScore) {
      selected = candidate;
      selectedScore = score;
    }
  }

  const selectedEnergy = getEnergyAtTime(input.energyProfile, input.durationSec, selected.startSec);
  const selectedPhraseAligned = selected.index % 8 === 0;
  const selectedDistanceScore = clamp(
    1 - Math.abs(selected.startSec - rawEnergySec) / maxDistanceSec,
    0,
    1
  );
  const selectedRemainingSec = input.durationSec - selected.startSec;
  const evidence = scoreOutroEvidence({
    timeSec: selected.startSec,
    durationSec: input.durationSec,
    barGrid: input.barGrid,
    energyProfile: input.energyProfile,
    transientMarkers: input.transientMarkers,
    beatGridQuality: input.beatGridQuality,
    downbeatConfidence: input.downbeatConfidence
  });
  const confidence = clamp(
    0.28 +
      input.beatGridQuality * 0.18 +
      input.downbeatConfidence * 0.16 +
      (selectedEnergy !== null ? (1 - selectedEnergy) * 0.18 : 0.04) +
      selectedDistanceScore * 0.1 +
      evidence.score * 0.08 +
      (selectedPhraseAligned ? 0.08 : 0) +
      (selectedRemainingSec >= minRemainingSec ? 0.08 : 0),
    0,
    0.86
  );

  return {
    startSec: selected.startSec,
    rawEnergySec,
    confidence,
    phraseAligned: selectedPhraseAligned,
    derived: evidence.derived
  };
};

const hasNearbyTransient = (
  transientMarkers: TransientMarker[],
  timeSec: number,
  windowSec: number
): number => {
  let best = 0;
  for (const marker of transientMarkers) {
    const distance = Math.abs(marker.timeSec - timeSec);
    if (distance <= windowSec) {
      best = Math.max(best, marker.strength * (1 - distance / windowSec));
    }
  }
  return best;
};

const lowBandDownbeatScore = (
  spectralBands: SpectralBandPoint[],
  durationSec: number,
  timeSec: number
): number => {
  const band = getSpectralBandAtTime(spectralBands, durationSec, timeSec);
  if (!band) {
    return 0;
  }
  const total = Math.max(0.000_001, band.low + band.mid + band.high);
  const lowRatio = band.low / total;
  const lowDominance = band.low - Math.max(band.mid * 0.4, band.high * 0.26);
  return clamp(lowRatio * 0.72 + lowDominance * 0.48, 0, 1);
};

const getSpectralWindowAverage = (
  spectralBands: SpectralBandPoint[],
  durationSec: number,
  startSec: number,
  endSec: number
): SpectralBandPoint | null => {
  if (spectralBands.length === 0 || durationSec <= 0) {
    return null;
  }
  const clampedStartSec = clamp(startSec, 0, durationSec);
  const clampedEndSec = clamp(endSec, clampedStartSec, durationSec);
  if (clampedEndSec <= clampedStartSec) {
    return null;
  }

  let low = 0;
  let mid = 0;
  let high = 0;
  let weight = 0;
  for (let index = 0; index < spectralBands.length; index += 1) {
    const band = spectralBands[index];
    if (!band) {
      continue;
    }
    const bucketStartSec = (index / spectralBands.length) * durationSec;
    const bucketEndSec = ((index + 1) / spectralBands.length) * durationSec;
    const overlapSec =
      Math.min(bucketEndSec, clampedEndSec) - Math.max(bucketStartSec, clampedStartSec);
    if (overlapSec <= 0) {
      continue;
    }
    low += band.low * overlapSec;
    mid += band.mid * overlapSec;
    high += band.high * overlapSec;
    weight += overlapSec;
  }

  return weight > 0
    ? { timeSec: clampedStartSec, low: low / weight, mid: mid / weight, high: high / weight }
    : null;
};

const spectralChangeScore = (
  spectralBands: SpectralBandPoint[],
  durationSec: number,
  timeSec: number,
  windowSec: number
): number => {
  const before = getSpectralWindowAverage(
    spectralBands,
    durationSec,
    Math.max(0, timeSec - windowSec),
    timeSec
  );
  const after = getSpectralWindowAverage(
    spectralBands,
    durationSec,
    timeSec,
    Math.min(durationSec, timeSec + windowSec)
  );
  if (!before || !after) {
    return 0;
  }
  const positiveDelta =
    Math.max(0, after.low - before.low) +
    Math.max(0, after.mid - before.mid) +
    Math.max(0, after.high - before.high);
  return clamp(positiveDelta / 0.22, 0, 1);
};

const scoreIntroEvidence = (input: {
  introCueSec: number;
  firstDownbeatSec: number | null;
  durationSec: number;
  energyProfile: number[];
  beatGridQuality: number;
  downbeatConfidence: number;
}): { score: number; derived: boolean } => {
  if (input.firstDownbeatSec === null || input.durationSec <= 0 || input.firstDownbeatSec < 1.5) {
    return { score: 0, derived: false };
  }
  const leadInEnergy = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    input.introCueSec,
    Math.min(input.firstDownbeatSec, input.introCueSec + 12)
  );
  const postEnergy = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    input.firstDownbeatSec,
    Math.min(input.durationSec, input.firstDownbeatSec + 12)
  );
  if (leadInEnergy === null || postEnergy === null) {
    return { score: 0, derived: false };
  }
  const leadInDrop = clamp((postEnergy - leadInEnergy) / 0.22, 0, 1);
  const downbeatScore = clamp(input.beatGridQuality * 0.5 + input.downbeatConfidence * 0.5, 0, 1);
  const score = clamp(leadInDrop * 0.62 + downbeatScore * 0.38, 0, 1);
  return {
    score,
    derived: leadInDrop >= 0.45 && downbeatScore >= 0.45 && score >= 0.54
  };
};

const scoreFirstDownbeatEvidence = (input: {
  timeSec: number;
  barGrid: BarMarker[];
  durationSec: number;
  spectralBands: SpectralBandPoint[];
  transientMarkers: TransientMarker[];
  beatGridQuality: number;
  downbeatConfidence: number;
  transientQuality: number;
}): { score: number; derived: boolean } => {
  const transientScore = hasNearbyTransient(input.transientMarkers, input.timeSec, 0.18);
  const kickScore = lowBandDownbeatScore(input.spectralBands, input.durationSec, input.timeSec);
  const matchingBar = input.barGrid.find((bar) => Math.abs(bar.startSec - input.timeSec) <= 0.25);
  const phraseSupport = matchingBar
    ? matchingBar.index === 0
      ? 1
      : matchingBar.index % 8 === 0
        ? 0.82
        : 0.42
    : 0;
  const earlySupport = clamp(1 - input.timeSec / Math.max(1, Math.min(48, input.durationSec * 0.35)), 0, 1);
  const score = clamp(
    input.beatGridQuality * 0.24 +
      input.downbeatConfidence * 0.22 +
      transientScore * 0.24 +
      kickScore * 0.16 +
      phraseSupport * 0.08 +
      earlySupport * 0.06,
    0,
    1
  );
  return {
    score,
    derived:
      input.beatGridQuality >= 0.38 &&
      input.downbeatConfidence >= 0.22 &&
      input.transientQuality >= 0.18 &&
      (transientScore >= 0.24 || kickScore >= 0.24) &&
      score >= 0.48
  };
};

const scoreOutroEvidence = (input: {
  timeSec: number;
  durationSec: number;
  barGrid: BarMarker[];
  energyProfile: number[];
  transientMarkers: TransientMarker[];
  beatGridQuality: number;
  downbeatConfidence: number;
}): { score: number; derived: boolean } => {
  if (input.durationSec <= 0) {
    return { score: 0, derived: false };
  }
  const windowSec = Math.min(18, Math.max(6, input.durationSec * 0.08));
  const beforeEnergy = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    Math.max(0, input.timeSec - windowSec),
    input.timeSec
  );
  const afterEnergy = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    input.timeSec,
    Math.min(input.durationSec, input.timeSec + windowSec)
  );
  if (beforeEnergy === null || afterEnergy === null) {
    return { score: 0, derived: false };
  }
  const energyDrop = clamp((beforeEnergy - afterEnergy) / 0.22, 0, 1);
  const beforeDensity = getTransientWeightDensity(
    input.transientMarkers,
    input.durationSec,
    Math.max(0, input.timeSec - windowSec),
    input.timeSec
  ) ?? 0;
  const afterDensity = getTransientWeightDensity(
    input.transientMarkers,
    input.durationSec,
    input.timeSec,
    Math.min(input.durationSec, input.timeSec + windowSec)
  ) ?? 0;
  const densityDrop = clamp((beforeDensity - afterDensity) / Math.max(0.12, beforeDensity), 0, 1);
  const remainingSec = input.durationSec - input.timeSec;
  const remainingSupport = clamp(remainingSec / Math.max(1, Math.min(24, input.durationSec * 0.18)), 0, 1);
  const matchingBar = input.barGrid.find((bar) => Math.abs(bar.startSec - input.timeSec) <= 0.75);
  const phraseSupport = matchingBar
    ? matchingBar.index % 8 === 0
      ? 1
      : matchingBar.index % 4 === 0
        ? 0.58
        : 0.28
    : 0;
  const gridSupport = clamp(input.beatGridQuality * 0.65 + input.downbeatConfidence * 0.35, 0, 1);
  const score = clamp(
    energyDrop * 0.34 +
      densityDrop * 0.22 +
      phraseSupport * 0.16 +
      remainingSupport * 0.14 +
      gridSupport * 0.14,
    0,
    1
  );
  return {
    score,
    derived:
      energyDrop >= 0.28 &&
      densityDrop >= 0.18 &&
      remainingSec >= Math.min(8, input.durationSec * 0.08) &&
      gridSupport >= 0.36 &&
      score >= 0.5
  };
};

const scoreEnergyValleyEvidence = (input: {
  timeSec: number;
  durationSec: number;
  energyProfile: number[];
  barGrid: BarMarker[];
  beatGridQuality: number;
}): { score: number; derived: boolean } => {
  if (input.durationSec <= 0) {
    return { score: 0, derived: false };
  }
  const windowSec = Math.min(12, Math.max(4, input.durationSec * 0.06));
  const before = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    Math.max(0, input.timeSec - windowSec),
    input.timeSec
  );
  const center = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    Math.max(0, input.timeSec - windowSec * 0.35),
    Math.min(input.durationSec, input.timeSec + windowSec * 0.35)
  );
  const after = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    input.timeSec,
    Math.min(input.durationSec, input.timeSec + windowSec)
  );
  if (before === null || center === null || after === null) {
    return { score: 0, derived: false };
  }
  const valleyDepth = clamp((Math.min(before, after) - center) / 0.18, 0, 1);
  const surroundingEnergy = clamp(Math.max(before, after) / 0.22, 0, 1);
  const matchingBar = input.barGrid.find((bar) => Math.abs(bar.startSec - input.timeSec) <= 0.75);
  const phraseSupport = matchingBar ? (matchingBar.index % 4 === 0 ? 1 : 0.35) : 0;
  const score = clamp(
    valleyDepth * 0.52 + surroundingEnergy * 0.2 + phraseSupport * 0.16 + input.beatGridQuality * 0.12,
    0,
    1
  );
  return {
    score,
    derived: valleyDepth >= 0.42 && surroundingEnergy >= 0.45 && score >= 0.54
  };
};

const scoreEnergyDropEvidence = (input: {
  timeSec: number;
  durationSec: number;
  energyProfile: number[];
  spectralBands: SpectralBandPoint[];
  transientMarkers: TransientMarker[];
  barGrid: BarMarker[];
  beatGridQuality: number;
}): { score: number; derived: boolean } => {
  if (input.durationSec <= 0) {
    return { score: 0, derived: false };
  }
  const windowSec = Math.min(10, Math.max(3, input.durationSec * 0.05));
  const before = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    Math.max(0, input.timeSec - windowSec),
    input.timeSec
  );
  const after = getEnergyWindowAverage(
    input.energyProfile,
    input.durationSec,
    input.timeSec,
    Math.min(input.durationSec, input.timeSec + windowSec)
  );
  if (before === null || after === null) {
    return { score: 0, derived: false };
  }
  const energyRise = clamp((after - before) / 0.2, 0, 1);
  const transientScore = hasNearbyTransient(input.transientMarkers, input.timeSec, 0.25);
  const spectralScore = spectralChangeScore(
    input.spectralBands,
    input.durationSec,
    input.timeSec,
    windowSec
  );
  const matchingBar = input.barGrid.find((bar) => Math.abs(bar.startSec - input.timeSec) <= 0.75);
  const phraseSupport = matchingBar
    ? matchingBar.index % 8 === 0
      ? 1
      : matchingBar.index % 4 === 0
        ? 0.64
        : 0.32
    : 0;
  const score = clamp(
    energyRise * 0.38 +
      transientScore * 0.24 +
      spectralScore * 0.14 +
      phraseSupport * 0.14 +
      input.beatGridQuality * 0.1,
    0,
    1
  );
  return {
    score,
    derived: energyRise >= 0.34 && (transientScore >= 0.22 || spectralScore >= 0.28) && score >= 0.52
  };
};

const resolveIntroCues = (input: {
  barGrid: BarMarker[];
  beatIntervalSec: number | null;
  beatGridQuality: number;
  downbeatsSec: number[];
  downbeatConfidence: number;
  durationSec: number;
  energyProfile: number[];
  spectralBands: SpectralBandPoint[];
  transientMarkers: TransientMarker[];
  transientQuality: number;
}): {
  introCueSec: number;
  firstDownbeatSec: number;
  introConfidence: number;
  firstDownbeatConfidence: number;
  introDerived: boolean;
  firstDownbeatDerived: boolean;
} => {
  const introCueSec = snapToBar(
    input.barGrid,
    input.downbeatsSec[0] ?? 0,
    'nearest',
    input.beatIntervalSec ?? 4
  );
  const latestCandidateSec = Math.min(48, input.durationSec * 0.35);
  const candidates = input.barGrid.filter(
    (bar) => bar.startSec >= 0 && bar.startSec <= latestCandidateSec
  );

  if (candidates.length === 0) {
    return {
      introCueSec,
      firstDownbeatSec: introCueSec,
      introConfidence: clamp(0.38 + input.beatGridQuality * 0.2, 0, 0.72),
      firstDownbeatConfidence: input.beatGridQuality > 0
        ? clamp(0.32 + input.beatGridQuality * 0.22, 0, 0.62)
        : 0.25,
      introDerived: false,
      firstDownbeatDerived: false
    };
  }

  let selected = candidates[0];
  let selectedScore = -Infinity;
  for (const candidate of candidates) {
    const energy = getEnergyAtTime(input.energyProfile, input.durationSec, candidate.startSec);
    const transientScore = hasNearbyTransient(
      input.transientMarkers,
      candidate.startSec,
      Math.min(0.18, (input.beatIntervalSec ?? 0.5) * 0.4)
    );
    const phraseScore = candidate.index % 8 === 0 ? 0.22 : candidate.index % 4 === 0 ? 0.12 : 0;
    const earlyPenalty = clamp(candidate.startSec / Math.max(1, latestCandidateSec), 0, 1) * 0.14;
    const score =
      (energy ?? 0.2) * 0.46 +
      transientScore * 0.24 +
      input.downbeatConfidence * 0.18 +
      phraseScore -
      earlyPenalty;

    if (score > selectedScore) {
      selected = candidate;
      selectedScore = score;
    }
  }

  const selectedEnergy = getEnergyAtTime(input.energyProfile, input.durationSec, selected.startSec);
  const selectedTransient = hasNearbyTransient(
    input.transientMarkers,
    selected.startSec,
    Math.min(0.18, (input.beatIntervalSec ?? 0.5) * 0.4)
  );
  const firstDownbeatMaxConfidence = clamp(0.58 + input.downbeatConfidence * 0.3, 0.58, 0.88);
  const firstDownbeatConfidence = clamp(
    0.28 +
      input.beatGridQuality * 0.2 +
      input.downbeatConfidence * 0.22 +
      (selectedEnergy ?? 0.2) * 0.18 +
      selectedTransient * 0.14 +
      (selected.index % 8 === 0 ? 0.06 : 0),
    0,
    firstDownbeatMaxConfidence
  );
  const introEvidence = scoreIntroEvidence({
    introCueSec,
    firstDownbeatSec: selected.startSec,
    durationSec: input.durationSec,
    energyProfile: input.energyProfile,
    beatGridQuality: input.beatGridQuality,
    downbeatConfidence: input.downbeatConfidence
  });
  const firstDownbeatEvidence = scoreFirstDownbeatEvidence({
    timeSec: selected.startSec,
    barGrid: input.barGrid,
    durationSec: input.durationSec,
    spectralBands: input.spectralBands,
    transientMarkers: input.transientMarkers,
    beatGridQuality: input.beatGridQuality,
    downbeatConfidence: input.downbeatConfidence,
    transientQuality: input.transientQuality
  });
  const introEnergy = getEnergyAtTime(input.energyProfile, input.durationSec, introCueSec);
  const introConfidence = clamp(
    0.34 +
      input.beatGridQuality * 0.18 +
      input.downbeatConfidence * 0.1 +
      introEvidence.score * 0.08 +
      (introEnergy ?? 0.2) * 0.08,
    0,
    0.8
  );

  return {
    introCueSec,
    firstDownbeatSec: selected.startSec,
    introConfidence,
    firstDownbeatConfidence: clamp(
      firstDownbeatConfidence * 0.7 + (0.3 + firstDownbeatEvidence.score * 0.58) * 0.3,
      0,
      0.88
    ),
    introDerived: introEvidence.derived,
    firstDownbeatDerived: firstDownbeatEvidence.derived
  };
};

export const buildTrackAnalysisFromAudioBuffer = (
  track: Track,
  buffer: AudioBufferForBpm
): TrackAnalysis => {
  const bpmEstimate = estimateTrackBpm(buffer);
  const resolvedBpm = resolveAnalysisBpm(track, bpmEstimate);
  const bpm = resolvedBpm.bpm;
  const durationSec = Math.max(0, buffer.duration || track.durationSec);
  const energyProfile = buildEnergyProfile(buffer);
  const waveformPeaks = buildWaveformPeaks(buffer);
  const waveformDetail = buildWaveformDetail(buffer);
  const spectralBands = buildSpectralBandsFromAudioBuffer(buffer, {
    bucketCount: waveformDetail.length
  });
  const onsetEnvelope = buildOnsetEnvelope(waveformDetail, spectralBands, durationSec);
  const transientMarkers = buildTransientMarkers(onsetEnvelope, durationSec);
  const beatIntervalSec = bpm && bpm > 0 ? 60 / bpm : null;
  const beatPhase =
    beatIntervalSec !== null
      ? resolveBeatPhaseOffset(beatIntervalSec, transientMarkers)
      : { offsetSec: 0, confidence: 0 };
  const beatGridSec =
    beatIntervalSec !== null
      ? buildBeatGrid(durationSec, beatIntervalSec, beatPhase.offsetSec)
      : [];
  const downbeatGrid = buildDownbeatGrid(beatGridSec, transientMarkers, energyProfile, durationSec);
  const beatGridStability = scoreBeatGridStability({
    beatGridSec,
    onsetEnvelope,
    beatPhaseConfidence: beatPhase.confidence,
    durationSec
  });
  const downbeatsSec = downbeatGrid.downbeatsSec;
  const barGrid = downbeatGrid.barGrid;
  const lowEnergyBreakSecRaw = findEnergyTime(energyProfile, durationSec, 'min', 0.35, 0.8);
  const lowEnergyBreakSec =
    lowEnergyBreakSecRaw !== null
      ? snapToBar(barGrid, lowEnergyBreakSecRaw, 'nearest')
      : null;
  const highEnergyDropSecRaw = findEnergyTime(energyProfile, durationSec, 'max', 0.05, 0.55);
  const highEnergyDropSec =
    highEnergyDropSecRaw !== null
      ? snapToBar(barGrid, highEnergyDropSecRaw, 'nearest')
      : null;
  const bpmConfidence =
    resolvedBpm.source === 'derived'
      ? bpmEstimate.confidence
      : track.bpm
        ? Math.max(0.62, Math.min(0.76, bpmEstimate.confidence || 0.72))
        : 0;
  const beatGridQuality =
    beatGridSec.length > 0
      ? clamp(
          bpmConfidence * 0.38 +
            beatPhase.confidence * 0.16 +
            downbeatGrid.confidence * 0.22 +
            beatGridStability.score * 0.24,
          0,
          1
        )
      : 0;
  const phraseMarkers: PhraseMarker[] = barGrid
    .filter((bar) => bar.index % 8 === 0)
    .map((bar, index) => ({
      index,
      startSec: bar.startSec,
      bars: 8,
      confidence: scorePhraseMarkerConfidence({
        bar,
        beatIntervalSec,
        beatGridQuality,
        bpmConfidence,
        downbeatConfidence: downbeatGrid.confidence,
        durationSec,
        energyProfile,
        transientMarkers
      })
    }));
  const transientQuality = scoreTransientMarkerQuality({
    transientMarkers,
    beatGridSec,
    durationSec,
    beatPhaseConfidence: beatPhase.confidence,
    downbeatConfidence: downbeatGrid.confidence
  });
  const outroCue = resolveOutroCue({
    barGrid,
    beatIntervalSec,
    beatGridQuality,
    downbeatConfidence: downbeatGrid.confidence,
    durationSec,
    energyProfile,
    transientMarkers
  });
  const outroCueSec = outroCue.startSec;
  const introCues = resolveIntroCues({
    barGrid,
    beatIntervalSec,
    beatGridQuality,
    downbeatsSec,
    downbeatConfidence: downbeatGrid.confidence,
    durationSec,
    energyProfile,
    spectralBands,
    transientMarkers,
    transientQuality
  });
  const introCueSec = introCues.introCueSec;
  const firstDownbeatSec = introCues.firstDownbeatSec;
  const lowEnergyBreakEvidence = lowEnergyBreakSec !== null
    ? scoreEnergyValleyEvidence({
        timeSec: lowEnergyBreakSec,
        durationSec,
        energyProfile,
        barGrid,
        beatGridQuality
      })
    : null;
  const highEnergyDropEvidence = highEnergyDropSec !== null
    ? scoreEnergyDropEvidence({
        timeSec: highEnergyDropSec,
        durationSec,
        energyProfile,
        spectralBands,
        transientMarkers,
        barGrid,
        beatGridQuality
      })
    : null;
  const analysisConfidence = clamp(
    0.25 +
      (bpm ? 0.25 : 0) +
      (beatGridSec.length > 0 ? beatGridQuality * 0.2 : 0) +
      (energyProfile.length > 8 ? 0.15 : 0) +
      (waveformPeaks.length > 8 ? 0.1 : 0) +
      (waveformDetail.length > WAVEFORM_BUCKETS ? 0.05 : 0),
    0,
    1
  );
  const analysisQuality = {
    waveformDetail: clamp(waveformDetail.length / WAVEFORM_DETAIL_MAX_BUCKETS, 0, 1),
    spectralBands: clamp(spectralBands.length / WAVEFORM_DETAIL_MAX_BUCKETS, 0, 1),
    transientMarkers: transientQuality,
    beatGrid: beatGridQuality,
    harmonicKey: 0
  };

  return sanitizeTrackAnalysis(track.id, {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    source: resolvedBpm.source,
    bpm,
    bpmConfidence,
    beatGridSec,
    downbeatsSec,
    barGrid,
    phraseMarkers,
    introCueSec,
    outroCueSec,
    energyProfile,
    waveformPeaks,
    waveformDetail,
    spectralBands,
    transientMarkers,
    cueCandidates: [
      {
        id: 'intro',
        type: 'intro',
        startSec: introCueSec,
        endSec: Math.min(durationSec, introCueSec + 8),
        confidence: introCues.introConfidence,
        label: 'Intro',
        origin: introCues.introDerived ? 'derived' : 'heuristic_placeholder'
      },
      {
        id: 'first-downbeat',
        type: 'first_downbeat',
        startSec: firstDownbeatSec,
        endSec: Math.min(durationSec, firstDownbeatSec + 4),
        confidence: bpm ? introCues.firstDownbeatConfidence : 0.25,
        label: 'First downbeat',
        origin: introCues.firstDownbeatDerived ? 'derived' : 'heuristic_placeholder'
      },
      {
        id: 'outro',
        type: 'outro',
        startSec: outroCueSec,
        endSec: durationSec,
        confidence: outroCue.confidence,
        label: 'Outro mix-out',
        origin: outroCue.derived ? 'derived' : 'heuristic_placeholder'
      },
      ...(lowEnergyBreakSec !== null
        ? [
            {
              id: 'low-energy-break',
              type: 'low_energy_break' as const,
              startSec: lowEnergyBreakSec,
              endSec: Math.min(durationSec, lowEnergyBreakSec + 8),
              confidence: clamp(0.34 + (lowEnergyBreakEvidence?.score ?? 0) * 0.42, 0, 0.78),
              label: 'Low-energy break',
              origin: lowEnergyBreakEvidence?.derived ? 'derived' : 'heuristic_placeholder'
            }
          ]
        : []),
      ...(highEnergyDropSec !== null
        ? [
            {
              id: 'high-energy-drop',
              type: 'high_energy_drop' as const,
              startSec: highEnergyDropSec,
              endSec: Math.min(durationSec, highEnergyDropSec + 8),
              confidence: clamp(0.32 + (highEnergyDropEvidence?.score ?? 0) * 0.46, 0, 0.78),
              label: 'High-energy drop',
              origin: highEnergyDropEvidence?.derived ? 'derived' : 'heuristic_placeholder'
            }
          ]
        : [])
    ],
    musicalKey: null,
    loudness: null,
    analysisConfidence,
    analysisQuality,
    analysisWarnings: [
      ...(bpm ? [] : ['bpm_unavailable' as const]),
      ...(bpmEstimate.bpm && bpmEstimate.confidence < 0.45
        ? ['bpm_low_confidence' as const]
        : []),
      ...(resolvedBpm.metadataMismatch ? ['bpm_metadata_mismatch' as const] : []),
      ...(bpm ? ['beat_grid_estimated' as const] : []),
      ...(durationSec < 30 ? ['short_track' as const] : []),
      ...(Math.max(...energyProfile, 0) < 0.05 ? ['flat_energy' as const] : []),
      'key_unavailable' as const,
      'loudness_low_confidence' as const
    ]
  });
};
