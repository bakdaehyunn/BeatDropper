import {
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
const WAVEFORM_DETAIL_BUCKETS_PER_SEC = 4;
const ENERGY_BUCKETS = 64;

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
  const bpm = track.bpm ?? bpmEstimate.bpm;
  const durationSec = Math.max(0, buffer.duration || track.durationSec);
  const energyProfile = buildEnergyProfile(buffer);
  const waveformPeaks = buildWaveformPeaks(buffer);
  const waveformDetail = buildWaveformDetail(buffer);
  const spectralBands = buildSpectralBands(buffer);
  const transientMarkers = buildTransientMarkers(waveformDetail, durationSec);
  const beatIntervalSec = bpm && bpm > 0 ? 60 / bpm : null;
  const beatGridSec =
    beatIntervalSec !== null
      ? Array.from(
          { length: Math.min(2200, Math.floor(durationSec / beatIntervalSec) + 1) },
          (_, index) => index * beatIntervalSec
        )
      : [];
  const downbeatsSec = beatGridSec.filter((_value, index) => index % 4 === 0);
  const barGrid = downbeatsSec.map((startSec, index) => ({
    index,
    startSec,
    beatIndex: index * 4
  }));
  const phraseMarkers = barGrid
    .filter((_bar, index) => index % 8 === 0)
    .map((bar, index) => ({
      index,
      startSec: bar.startSec,
      bars: 8,
      confidence: bpmEstimate.confidence || (track.bpm ? 0.7 : 0.25)
    }));
  const introCueSec = downbeatsSec[0] ?? 0;
  const firstDownbeatSec = downbeatsSec[1] ?? introCueSec;
  const outroCueSec = Math.max(
    0,
    findEnergyTime(energyProfile, durationSec, 'min', 0.72, 0.95) ??
      durationSec - Math.min(16, durationSec * 0.12)
  );
  const lowEnergyBreakSec = findEnergyTime(energyProfile, durationSec, 'min', 0.35, 0.8);
  const highEnergyDropSec = findEnergyTime(energyProfile, durationSec, 'max', 0.05, 0.55);
  const bpmConfidence = bpmEstimate.bpm ? bpmEstimate.confidence : track.bpm ? 0.72 : 0;
  const analysisConfidence = clamp(
    0.25 +
      (bpm ? 0.25 : 0) +
      (beatGridSec.length > 0 ? 0.2 : 0) +
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
    beatGrid: beatGridSec.length > 0 ? bpmConfidence : 0
  };

  return sanitizeTrackAnalysis(track.id, {
    generatedAt: new Date().toISOString(),
    source: bpmEstimate.bpm ? 'derived' : track.bpm ? 'metadata' : 'derived',
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
        confidence: 0.7,
        label: 'Intro'
      },
      {
        id: 'first-downbeat',
        type: 'first_downbeat',
        startSec: firstDownbeatSec,
        endSec: Math.min(durationSec, firstDownbeatSec + 4),
        confidence: bpm ? 0.68 : 0.25,
        label: 'First downbeat'
      },
      {
        id: 'outro',
        type: 'outro',
        startSec: outroCueSec,
        endSec: durationSec,
        confidence: 0.64,
        label: 'Outro mix-out'
      },
      ...(lowEnergyBreakSec !== null
        ? [
            {
              id: 'low-energy-break',
              type: 'low_energy_break' as const,
              startSec: lowEnergyBreakSec,
              endSec: Math.min(durationSec, lowEnergyBreakSec + 8),
              confidence: 0.52,
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
              confidence: 0.5,
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
      ...(bpm ? ['beat_grid_estimated' as const] : []),
      ...(durationSec < 30 ? ['short_track' as const] : []),
      ...(Math.max(...energyProfile, 0) < 0.05 ? ['flat_energy' as const] : [])
    ]
  });
};
