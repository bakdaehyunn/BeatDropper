import {
  BarMarker,
  sanitizeTrackAnalysis,
  SpectralBandPoint,
  TrackAnalysis,
  TransientMarker,
  WaveformDetailPoint
} from '../../shared/analysis';
import { Track } from '../../shared/types';
import { AudioBufferForBpm, estimateTrackBpm } from './bpmEstimator';

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

const normalizeBandPoints = (points: SpectralBandPoint[]): SpectralBandPoint[] => {
  const maxLow = Math.max(1e-6, ...points.map((point) => point.low));
  const maxMid = Math.max(1e-6, ...points.map((point) => point.mid));
  const maxHigh = Math.max(1e-6, ...points.map((point) => point.high));

  return points.map((point) => ({
    timeSec: point.timeSec,
    low: clamp(point.low / maxLow, 0, 1),
    mid: clamp(point.mid / maxMid, 0, 1),
    high: clamp(point.high / maxHigh, 0, 1)
  }));
};

const buildSpectralBands = (buffer: AudioBufferForBpm): SpectralBandPoint[] => {
  const totalSamples = Math.max(0, Math.floor(buffer.duration * buffer.sampleRate));
  const bucketCount = Math.min(
    WAVEFORM_DETAIL_MAX_BUCKETS,
    Math.max(WAVEFORM_BUCKETS, Math.floor(buffer.duration * WAVEFORM_DETAIL_BUCKETS_PER_SEC))
  );
  const samplesPerBucket = Math.max(1, Math.floor(totalSamples / bucketCount));
  const points = Array.from({ length: bucketCount }, (_, bucketIndex) => {
    const start = bucketIndex * samplesPerBucket;
    const end = Math.min(totalSamples, start + samplesPerBucket);
    let low = 0;
    let mid = 0;
    let high = 0;
    let previous = readMonoSample(buffer, start);
    let count = 0;

    for (let sampleIndex = start; sampleIndex < end; sampleIndex += 1) {
      const sample = readMonoSample(buffer, sampleIndex);
      const delta = sample - previous;
      const abs = Math.abs(sample);
      const highComponent = Math.abs(delta);
      low += abs * abs;
      mid += Math.abs(sample - delta * 0.5);
      high += highComponent * highComponent;
      previous = sample;
      count += 1;
    }

    return {
      timeSec: (start / Math.max(1, totalSamples)) * buffer.duration,
      low: count > 0 ? Math.sqrt(low / count) : 0,
      mid: count > 0 ? mid / count : 0,
      high: count > 0 ? Math.sqrt(high / count) : 0
    };
  });

  return normalizeBandPoints(points);
};

const buildTransientMarkers = (
  waveformDetail: WaveformDetailPoint[],
  durationSec: number
): TransientMarker[] => {
  if (waveformDetail.length < 4 || durationSec <= 0) {
    return [];
  }

  const strengths = waveformDetail.map((point, index) => {
    const previous = waveformDetail[Math.max(0, index - 1)]?.rms ?? 0;
    return Math.max(0, point.rms - previous);
  });
  const maxStrength = Math.max(1e-6, ...strengths);
  const normalized = strengths.map((value) => clamp(value / maxStrength, 0, 1));
  const markers: TransientMarker[] = [];
  let lastTimeSec = -Infinity;

  normalized.forEach((strength, index) => {
    const point = waveformDetail[index];
    if (!point || strength < 0.58 || point.timeSec - lastTimeSec < 0.18) {
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

  let bestPhase = 0;
  let bestScore = scoreDownbeatPhase(beatGridSec, 0, transientMarkers, energyProfile, durationSec);
  for (let phase = 1; phase < 4; phase += 1) {
    const score = scoreDownbeatPhase(beatGridSec, phase, transientMarkers, energyProfile, durationSec);
    if (score > bestScore) {
      bestScore = score;
      bestPhase = phase;
    }
  }

  const downbeatsSec = beatGridSec.filter((_beat, index) => index % 4 === bestPhase);
  const barGrid = downbeatsSec.map((startSec, index) => ({
    index,
    startSec,
    beatIndex: bestPhase + index * 4
  }));

  return {
    downbeatsSec,
    barGrid,
    confidence: clamp(bestScore, 0, 1)
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
  const spectralBands = buildSpectralBands(buffer);
  const transientMarkers = buildTransientMarkers(waveformDetail, durationSec);
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
  const downbeatsSec = downbeatGrid.downbeatsSec;
  const barGrid = downbeatGrid.barGrid;
  const phraseMarkers = barGrid
    .filter((_bar, index) => index % 8 === 0)
    .map((bar, index) => ({
      index,
      startSec: bar.startSec,
      bars: 8,
      confidence: clamp(
        (bpmEstimate.confidence || (track.bpm ? 0.7 : 0.25)) * 0.72 +
          downbeatGrid.confidence * 0.28,
        0,
        1
      )
    }));
  const introCueSec = snapToBar(barGrid, downbeatsSec[0] ?? 0, 'nearest', beatIntervalSec ?? 4);
  const firstDownbeatSec = snapToBar(
    barGrid,
    downbeatsSec.find((timeSec) => timeSec > 0.2) ?? introCueSec,
    'nearest',
    beatIntervalSec ?? 4
  );
  const rawOutroCueSec = Math.max(
    0,
    findEnergyTime(energyProfile, durationSec, 'min', 0.72, 0.95) ??
      durationSec - Math.min(16, durationSec * 0.12)
  );
  const outroCueSec = snapToBar(barGrid, rawOutroCueSec, 'before');
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
      ? clamp(bpmConfidence * 0.68 + beatPhase.confidence * 0.18 + downbeatGrid.confidence * 0.14, 0, 1)
      : 0;
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
    transientMarkers: clamp(transientMarkers.length / Math.max(16, durationSec / 2), 0, 1),
    beatGrid: beatGridQuality
  };

  return sanitizeTrackAnalysis(track.id, {
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
        confidence: clamp(0.58 + beatGridQuality * 0.24, 0, 0.86),
        label: 'Intro'
      },
      {
        id: 'first-downbeat',
        type: 'first_downbeat',
        startSec: firstDownbeatSec,
        endSec: Math.min(durationSec, firstDownbeatSec + 4),
        confidence: bpm ? clamp(0.5 + beatGridQuality * 0.34, 0, 0.88) : 0.25,
        label: 'First downbeat'
      },
      {
        id: 'outro',
        type: 'outro',
        startSec: outroCueSec,
        endSec: durationSec,
        confidence: clamp(0.46 + beatGridQuality * 0.2 + (rawOutroCueSec !== outroCueSec ? 0.08 : 0), 0, 0.82),
        label: 'Outro mix-out'
      },
      ...(lowEnergyBreakSec !== null
        ? [
            {
              id: 'low-energy-break',
              type: 'low_energy_break' as const,
              startSec: lowEnergyBreakSec,
              endSec: Math.min(durationSec, lowEnergyBreakSec + 8),
              confidence: clamp(0.44 + beatGridQuality * 0.18, 0, 0.72),
              label: 'Low-energy break'
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
              confidence: clamp(0.42 + beatGridQuality * 0.16, 0, 0.7),
              label: 'High-energy drop'
            }
          ]
        : [])
    ],
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
      ...(Math.max(...energyProfile, 0) < 0.05 ? ['flat_energy' as const] : [])
    ]
  });
};
