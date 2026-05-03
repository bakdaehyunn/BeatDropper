import {
  pickNextTrackForDetailedAnalysis,
  preferDetailedTrackAnalysis,
  shouldBuildDetailedTrackAnalysis
} from '../../src/renderer/player/trackAnalysisQueue';
import { sanitizeTrackAnalysis } from '../../src/shared/analysis';
import { Track } from '../../src/shared/types';

const track = (id: string): Track => ({
  id,
  title: `${id}.wav`,
  durationSec: 180,
  format: 'wav',
  bpm: null
});

const metadataOnlyAnalysis = (trackId: string) =>
  sanitizeTrackAnalysis(trackId, {
    bpm: 124,
    bpmConfidence: 0.7,
    waveformPeaks: [],
    waveformDetail: [],
    analysisConfidence: 0.6
  });

const detailedAnalysis = (trackId: string) =>
  sanitizeTrackAnalysis(trackId, {
    bpm: 124,
    bpmConfidence: 0.9,
    waveformPeaks: [{ timeSec: 0, peak: 0.4, rms: 0.2 }],
    waveformDetail: [{ timeSec: 0, peak: 0.4, rms: 0.2, min: -0.3, max: 0.3 }],
    analysisConfidence: 0.85
  });

describe('trackAnalysisQueue', () => {
  it('queues tracks with no analysis so playlist BPM can be calculated before playback', () => {
    expect(
      pickNextTrackForDetailedAnalysis([track('a')], {}, [], new Set())?.id
    ).toBe('a');
  });

  it('queues metadata-only analysis for waveform and beat detail upgrade', () => {
    expect(shouldBuildDetailedTrackAnalysis(metadataOnlyAnalysis('a'))).toBe(true);
    expect(shouldBuildDetailedTrackAnalysis(detailedAnalysis('a'))).toBe(false);
  });

  it('skips tracks already running or failed during this session', () => {
    const tracks = [track('a'), track('b'), track('c')];
    expect(
      pickNextTrackForDetailedAnalysis(tracks, {}, ['a'], new Set(['b']))?.id
    ).toBe('c');
  });

  it('does not overwrite detailed renderer analysis with metadata-only cache results', () => {
    const detailed = detailedAnalysis('a');
    const metadataOnly = metadataOnlyAnalysis('a');
    expect(preferDetailedTrackAnalysis(detailed, metadataOnly)).toBe(detailed);
  });
});
