const MIN_BPM = 70;
const MAX_BPM = 180;
const MAX_ANALYSIS_SEC = 90;
const MIN_CONFIDENCE = 0.3;
const FRAME_SIZE = 1024;
const HOP_SIZE = 512;
const MIN_WINDOW_SEC = 8;
const BPM_CLUSTER_TOLERANCE = 3;

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

interface AnalysisWindow {
  startSec: number;
  endSec: number;
  weight: number;
}

interface WindowEstimate {
  bpm: number;
  confidence: number;
  analyzedSeconds: number;
  weight: number;
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

const buildDefaultAnalysisWindow = (durationSec: number): AnalysisWindow => {
  const analysisSec = Math.min(MAX_ANALYSIS_SEC, Math.max(MIN_WINDOW_SEC, durationSec * 0.6));
  const initialStartSec = Math.min(Math.max(2, durationSec * 0.1), 20);
  const startSec = Math.max(0, Math.min(initialStartSec, durationSec - analysisSec));
  const endSec = Math.min(durationSec, startSec + analysisSec);
  return {
    startSec,
    endSec,
    weight: 1.25
  };
};

const buildAnalysisWindows = (durationSec: number): AnalysisWindow[] => {
  const windows: AnalysisWindow[] = [buildDefaultAnalysisWindow(durationSec)];
  const introEnd = Math.min(durationSec, Math.max(MIN_WINDOW_SEC, Math.min(45, durationSec * 0.32)));
  const bodyStart = Math.min(durationSec, Math.max(0, durationSec * 0.32));
  const bodyEnd = Math.min(durationSec, bodyStart + Math.min(60, Math.max(MIN_WINDOW_SEC, durationSec * 0.4)));
  const outroStart = Math.max(0, durationSec - Math.min(60, Math.max(MIN_WINDOW_SEC, durationSec * 0.32)));

  windows.push(
    { startSec: 0, endSec: introEnd, weight: 0.9 },
    { startSec: bodyStart, endSec: bodyEnd, weight: 1 },
    { startSec: outroStart, endSec: durationSec, weight: 0.75 }
  );

  const deduped: AnalysisWindow[] = [];
  for (const window of windows) {
    if (window.endSec - window.startSec < MIN_WINDOW_SEC) {
      continue;
    }
    if (
      deduped.some(
        (existing) =>
          Math.abs(existing.startSec - window.startSec) < 0.5 &&
          Math.abs(existing.endSec - window.endSec) < 0.5
      )
    ) {
      continue;
    }
    deduped.push(window);
  }

  return deduped;
};

const estimateWindowBpm = (
  buffer: AudioBufferForBpm,
  window: AnalysisWindow
): WindowEstimate | null => {
  const startSample = Math.floor(window.startSec * buffer.sampleRate);
  const endSample = Math.floor(window.endSec * buffer.sampleRate);
  const analyzedSeconds = Math.max(0, window.endSec - window.startSec);
  const envelope = buildEnvelope(buffer, startSample, endSample);
  if (envelope.length < 32) {
    return null;
  }

  const normalized = normalizeEnvelope(smoothEnvelope(envelope));
  if (!normalized) {
    return null;
  }

  const featureRate = buffer.sampleRate / HOP_SIZE;
  const peak = findCorrelationPeak(normalized, featureRate);
  const confidence = clamp(peak.score, 0, 1);
  if (confidence < MIN_CONFIDENCE) {
    return null;
  }

  return {
    bpm: normalizeBpmRange((60 * featureRate) / peak.lag),
    confidence,
    analyzedSeconds,
    weight: window.weight
  };
};

const areBpmCandidatesCompatible = (left: number, right: number): boolean => {
  return Math.abs(left - right) <= BPM_CLUSTER_TOLERANCE;
};

const chooseClusteredEstimate = (estimates: WindowEstimate[]): BpmEstimate | null => {
  if (estimates.length === 0) {
    return null;
  }

  const clusters = estimates.map((estimate) => {
    const members = estimates.filter((candidate) =>
      areBpmCandidatesCompatible(candidate.bpm, estimate.bpm)
    );
    const totalWeight = members.reduce(
      (sum, member) => sum + member.confidence * member.weight,
      0
    );
    const bpm =
      members.reduce(
        (sum, member) => sum + member.bpm * member.confidence * member.weight,
        0
      ) / Math.max(1e-6, totalWeight);
    return {
      members,
      bpm,
      totalWeight
    };
  });

  const selected = clusters.sort((left, right) => right.totalWeight - left.totalWeight)[0];
  if (!selected) {
    return null;
  }

  const confidenceWeight = selected.members.reduce(
    (sum, member) => sum + member.confidence * member.weight,
    0
  );
  const plainWeight = selected.members.reduce((sum, member) => sum + member.weight, 0);
  const averageConfidence = confidenceWeight / Math.max(1e-6, plainWeight);
  const support = selected.members.length / Math.max(1, Math.min(3, estimates.length));
  const confidence = clamp(averageConfidence * 0.78 + support * 0.22, 0, 1);

  if (confidence < MIN_CONFIDENCE) {
    return null;
  }

  return {
    bpm: selected.bpm,
    confidence,
    analyzedSeconds: selected.members.reduce(
      (sum, member) => sum + member.analyzedSeconds,
      0
    )
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

  const windows = buildAnalysisWindows(buffer.duration);
  if (windows.length === 0) {
    return {
      bpm: null,
      confidence: 0,
      analyzedSeconds: 0,
      reason: 'short_analysis'
    };
  }

  const estimates = windows
    .map((window) => estimateWindowBpm(buffer, window))
    .filter((estimate): estimate is WindowEstimate => estimate !== null);
  const clustered = chooseClusteredEstimate(estimates);
  if (!clustered) {
    return {
      bpm: null,
      confidence: estimates.length > 0
        ? Math.max(...estimates.map((estimate) => estimate.confidence))
        : 0,
      analyzedSeconds: windows.reduce(
        (sum, window) => sum + Math.max(0, window.endSec - window.startSec),
        0
      ),
      reason: estimates.length > 0 ? 'low_confidence' : 'flat_signal'
    };
  }

  return clustered;
};
