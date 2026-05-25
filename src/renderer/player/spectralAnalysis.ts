import { SpectralBandPoint } from '../../shared/analysis';
import { AudioBufferForBpm } from './bpmEstimator';

const DEFAULT_FFT_SIZE = 2048;
const LOW_BAND_MAX_HZ = 250;
const MID_BAND_MAX_HZ = 4000;
const HIGH_BAND_MAX_HZ = 16000;

const clamp = (value: number, min: number, max: number): number => {
  return Math.min(max, Math.max(min, value));
};

const isPowerOfTwo = (value: number): boolean => {
  return value > 0 && (value & (value - 1)) === 0;
};

const buildHannWindow = (size: number): Float64Array => {
  const window = new Float64Array(size);
  if (size === 1) {
    window[0] = 1;
    return window;
  }

  for (let index = 0; index < size; index += 1) {
    window[index] = 0.5 - 0.5 * Math.cos((2 * Math.PI * index) / (size - 1));
  }
  return window;
};

const reverseBits = (value: number, bitCount: number): number => {
  let reversed = 0;
  for (let bit = 0; bit < bitCount; bit += 1) {
    reversed = (reversed << 1) | (value & 1);
    value >>= 1;
  }
  return reversed;
};

const fftInPlace = (real: Float64Array, imag: Float64Array): void => {
  const size = real.length;
  const bitCount = Math.log2(size);

  for (let index = 0; index < size; index += 1) {
    const reversed = reverseBits(index, bitCount);
    if (reversed > index) {
      const realValue = real[index];
      const imagValue = imag[index];
      real[index] = real[reversed];
      imag[index] = imag[reversed];
      real[reversed] = realValue;
      imag[reversed] = imagValue;
    }
  }

  for (let width = 2; width <= size; width *= 2) {
    const halfWidth = width / 2;
    const phaseStep = (-2 * Math.PI) / width;
    for (let start = 0; start < size; start += width) {
      for (let offset = 0; offset < halfWidth; offset += 1) {
        const evenIndex = start + offset;
        const oddIndex = evenIndex + halfWidth;
        const angle = phaseStep * offset;
        const cos = Math.cos(angle);
        const sin = Math.sin(angle);
        const oddReal = real[oddIndex] * cos - imag[oddIndex] * sin;
        const oddImag = real[oddIndex] * sin + imag[oddIndex] * cos;
        const evenReal = real[evenIndex];
        const evenImag = imag[evenIndex];

        real[evenIndex] = evenReal + oddReal;
        imag[evenIndex] = evenImag + oddImag;
        real[oddIndex] = evenReal - oddReal;
        imag[oddIndex] = evenImag - oddImag;
      }
    }
  }
};

const normalizeBandPoints = (points: SpectralBandPoint[]): SpectralBandPoint[] => {
  const maxEnergy = Math.max(
    1e-6,
    ...points.flatMap((point) => [point.low, point.mid, point.high])
  );

  return points.map((point) => ({
    timeSec: point.timeSec,
    low: clamp(point.low / maxEnergy, 0, 1),
    mid: clamp(point.mid / maxEnergy, 0, 1),
    high: clamp(point.high / maxEnergy, 0, 1)
  }));
};

export interface BuildSpectralBandsOptions {
  bucketCount: number;
  fftSize?: number;
}

export const buildSpectralBandsFromAudioBuffer = (
  buffer: AudioBufferForBpm,
  options: BuildSpectralBandsOptions
): SpectralBandPoint[] => {
  const totalSamples = Math.max(0, Math.floor(buffer.duration * buffer.sampleRate));
  const bucketCount = Math.max(1, Math.floor(options.bucketCount));
  const fftSize = options.fftSize ?? DEFAULT_FFT_SIZE;

  if (
    totalSamples <= 0 ||
    buffer.sampleRate <= 0 ||
    buffer.numberOfChannels <= 0 ||
    !isPowerOfTwo(fftSize)
  ) {
    return [];
  }

  const channels = Math.max(1, buffer.numberOfChannels);
  const channelData = Array.from({ length: channels }, (_, index) => buffer.getChannelData(index));
  const window = buildHannWindow(fftSize);
  const samplesPerBucket = Math.max(1, Math.floor(totalSamples / bucketCount));
  const binHz = buffer.sampleRate / fftSize;
  const nyquistBin = Math.floor(fftSize / 2);
  const lowMaxBin = clamp(Math.floor(LOW_BAND_MAX_HZ / binHz), 1, nyquistBin);
  const midMaxBin = clamp(Math.floor(MID_BAND_MAX_HZ / binHz), lowMaxBin + 1, nyquistBin);
  const highMaxBin = clamp(Math.floor(HIGH_BAND_MAX_HZ / binHz), midMaxBin + 1, nyquistBin);

  const readMonoSample = (sampleIndex: number): number => {
    if (sampleIndex < 0 || sampleIndex >= totalSamples) {
      return 0;
    }

    let sum = 0;
    for (let channel = 0; channel < channels; channel += 1) {
      sum += channelData[channel][sampleIndex] ?? 0;
    }
    return sum / channels;
  };

  const points = Array.from({ length: bucketCount }, (_, bucketIndex) => {
    const bucketStart = bucketIndex * samplesPerBucket;
    const bucketEnd = Math.min(totalSamples, bucketStart + samplesPerBucket);
    const windowStart = Math.floor((bucketStart + bucketEnd) / 2 - fftSize / 2);
    const real = new Float64Array(fftSize);
    const imag = new Float64Array(fftSize);

    for (let index = 0; index < fftSize; index += 1) {
      real[index] = readMonoSample(windowStart + index) * window[index];
    }

    fftInPlace(real, imag);

    let low = 0;
    let lowCount = 0;
    let mid = 0;
    let midCount = 0;
    let high = 0;
    let highCount = 0;

    for (let bin = 1; bin <= highMaxBin; bin += 1) {
      const power = real[bin] * real[bin] + imag[bin] * imag[bin];
      if (bin <= lowMaxBin) {
        low += power;
        lowCount += 1;
      } else if (bin <= midMaxBin) {
        mid += power;
        midCount += 1;
      } else {
        high += power;
        highCount += 1;
      }
    }

    return {
      timeSec: (bucketStart / Math.max(1, totalSamples)) * buffer.duration,
      low: lowCount > 0 ? Math.sqrt(low / lowCount) : 0,
      mid: midCount > 0 ? Math.sqrt(mid / midCount) : 0,
      high: highCount > 0 ? Math.sqrt(high / highCount) : 0
    };
  });

  return normalizeBandPoints(points);
};
