import { buildTrackAnalysisFromAudioBuffer } from '../../src/renderer/player/trackAnalysisBuilder';
import { Track } from '../../src/shared/types';

const buildFakeBuffer = (duration = 32, sampleRate = 8000) => {
  const length = duration * sampleRate;
  const data = new Float32Array(length);
  for (let index = 0; index < length; index += 1) {
    const sec = index / sampleRate;
    const pulse = Math.sin(sec * Math.PI * 4) > 0.92 ? 0.7 : 0.08;
    data[index] = pulse * Math.sin(sec * Math.PI * 440);
  }

  return {
    duration,
    sampleRate,
    numberOfChannels: 1,
    getChannelData: () => data
  };
};

describe('buildTrackAnalysisFromAudioBuffer', () => {
  it('builds waveform, energy, bar, phrase, and cue data for a track', () => {
    const track: Track = {
      id: 'track-1',
      title: 'Track 1',
      durationSec: 32,
      format: 'wav',
      bpm: 120
    };

    const analysis = buildTrackAnalysisFromAudioBuffer(track, buildFakeBuffer());

    expect(analysis.trackId).toBe(track.id);
    expect(analysis.bpm).toBe(120);
    expect(analysis.waveformPeaks.length).toBeGreaterThan(0);
    expect(analysis.energyProfile.length).toBeGreaterThan(0);
    expect(analysis.beatGridSec.length).toBeGreaterThan(0);
    expect(analysis.barGrid.length).toBeGreaterThan(0);
    expect(analysis.phraseMarkers.length).toBeGreaterThan(0);
    expect(analysis.cueCandidates.map((cue) => cue.type)).toEqual(
      expect.arrayContaining(['intro', 'outro'])
    );
  });
});
