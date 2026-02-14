const MIN_BPM = 70;
const MAX_BPM = 180;
const MAX_ANALYSIS_SEC = 45;
const MIN_CONFIDENCE = 0.3;
const FRAME_SIZE = 1024;
const HOP_SIZE = 512;

export interface AudioBufferForBpm {
  duration: number;
  sampleRate: number;
  numberOfChannels: number;
  getChannelData(channel: number): Float32Array;
}

export interface BpmEstimate {
  bpm: number | null;
  confidence: number;
  analyzedSeconds: number;
  reason?:
    | 'unsupported_buffer'
    | 'short_audio'
    | 'short_analysis'
    | 'flat_signal'
    | 'low_confidence';
}

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const normalizeBpmRange = (bpm: number): number => {
  let normalized = bpm;
  while (normalized < MIN_BPM) {
    normalized *= 2;
  }
  while (normalized > MAX_BPM) {
    normalized /= 2;
  }
  return normalized;
};

const hasAudioBufferShape = (buffer: AudioBufferForBpm | unknown): buffer is AudioBufferForBpm => {
  if (!buffer || typeof buffer !== 'object') {
    return false;
  }

  const candidate = buffer as Partial<AudioBufferForBpm>;
  return (
    typeof candidate.duration === 'number' &&
    typeof candidate.sampleRate === 'number' &&
    typeof candidate.numberOfChannels === 'number' &&
    typeof candidate.getChannelData === 'function'
  );
};

const buildEnvelope = (
  buffer: AudioBufferForBpm,
  startSample: number,
  endSample: number
): Float32Array => {
  const channels = Math.max(1, buffer.numberOfChannels);
  const frameCount = Math.floor((endSample - startSample - FRAME_SIZE) / HOP_SIZE);
  const envelope = new Float32Array(Math.max(0, frameCount));
  if (frameCount <= 0) {
    return envelope;
  }

  const channelData = Array.from({ length: channels }, (_, index) =>
    buffer.getChannelData(index)
  );

  for (let frame = 0; frame < frameCount; frame += 1) {
    const offset = startSample + frame * HOP_SIZE;
    let sumSquares = 0;

    for (let sampleIndex = 0; sampleIndex < FRAME_SIZE; sampleIndex += 1) {
      const sourceIndex = offset + sampleIndex;
      let mono = 0;

      for (let channel = 0; channel < channels; channel += 1) {
        mono += channelData[channel][sourceIndex] ?? 0;
      }
      mono /= channels;
      sumSquares += mono * mono;
    }

    envelope[frame] = Math.sqrt(sumSquares / FRAME_SIZE);
  }

  return envelope;
};

const normalizeEnvelope = (input: Float32Array): Float32Array | null => {
  if (input.length === 0) {
    return null;
  }

  let mean = 0;
  for (let index = 0; index < input.length; index += 1) {
    mean += input[index];
  }
  mean /= input.length;

  let variance = 0;
  for (let index = 0; index < input.length; index += 1) {
    const centered = input[index] - mean;
    variance += centered * centered;
  }
  variance /= input.length;
  const stddev = Math.sqrt(variance);
  if (stddev < 1e-6) {
    return null;
  }

  const output = new Float32Array(input.length);
  for (let index = 0; index < input.length; index += 1) {
    output[index] = (input[index] - mean) / stddev;
  }
  return output;
};

const smoothEnvelope = (input: Float32Array): Float32Array => {
  if (input.length < 5) {
    return input;
  }

  const output = new Float32Array(input.length);
  const radius = 2;
  for (let index = 0; index < input.length; index += 1) {
    let sum = 0;
    let count = 0;
    for (let offset = -radius; offset <= radius; offset += 1) {
      const value = input[index + offset];
      if (value !== undefined) {
        sum += value;
        count += 1;
      }
    }
    output[index] = count > 0 ? sum / count : input[index];
  }
  return output;
};

interface CorrelationPeak {
  lag: number;
  score: number;
}

const findCorrelationPeak = (
  normalizedEnvelope: Float32Array,
  featureRate: number
): CorrelationPeak => {
  const lagMin = Math.max(1, Math.round((60 / MAX_BPM) * featureRate));
  const lagMax = Math.max(lagMin + 1, Math.round((60 / MIN_BPM) * featureRate));

  let bestLag = lagMin;
  let bestScore = -Infinity;

  for (let lag = lagMin; lag <= lagMax; lag += 1) {
    let sumXY = 0;
    let sumX2 = 0;
    let sumY2 = 0;

    for (let index = 0; index + lag < normalizedEnvelope.length; index += 1) {
      const x = normalizedEnvelope[index];
      const y = normalizedEnvelope[index + lag];
      sumXY += x * y;
      sumX2 += x * x;
      sumY2 += y * y;
    }

    if (sumX2 === 0 || sumY2 === 0) {
      continue;
    }

    const score = sumXY / Math.sqrt(sumX2 * sumY2);
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }

  return {
    lag: bestLag,
    score: Number.isFinite(bestScore) ? bestScore : 0
  };
};

export const estimateTrackBpm = (buffer: AudioBufferForBpm | unknown): BpmEstimate => {
  if (!hasAudioBufferShape(buffer)) {
    return {
      bpm: null,
      confidence: 0,
      analyzedSeconds: 0,
      reason: 'unsupported_buffer'
    };
  }

  if (buffer.duration < 4 || buffer.sampleRate <= 0 || buffer.numberOfChannels <= 0) {
    return {
      bpm: null,
      confidence: 0,
      analyzedSeconds: buffer.duration,
      reason: 'short_audio'
    };
  }

  const analysisSec = Math.min(MAX_ANALYSIS_SEC, Math.max(8, buffer.duration * 0.6));
  const initialStartSec = Math.min(Math.max(2, buffer.duration * 0.1), 20);
  const startSec = Math.max(0, Math.min(initialStartSec, buffer.duration - analysisSec));
  const endSec = Math.min(buffer.duration, startSec + analysisSec);
  const analyzedSeconds = Math.max(0, endSec - startSec);

  const startSample = Math.floor(startSec * buffer.sampleRate);
  const endSample = Math.floor(endSec * buffer.sampleRate);

  const envelope = buildEnvelope(buffer, startSample, endSample);
  if (envelope.length < 32) {
    return {
      bpm: null,
      confidence: 0,
      analyzedSeconds,
      reason: 'short_analysis'
    };
  }

  const normalized = normalizeEnvelope(smoothEnvelope(envelope));
  if (!normalized) {
    return {
      bpm: null,
      confidence: 0,
      analyzedSeconds,
      reason: 'flat_signal'
    };
  }

  const featureRate = buffer.sampleRate / HOP_SIZE;
  const peak = findCorrelationPeak(normalized, featureRate);
  const confidence = clamp(peak.score, 0, 1);
  if (confidence < MIN_CONFIDENCE) {
    return {
      bpm: null,
      confidence,
      analyzedSeconds,
      reason: 'low_confidence'
    };
  }

  const bpm = normalizeBpmRange((60 * featureRate) / peak.lag);
  return {
    bpm,
    confidence,
    analyzedSeconds
  };
};
