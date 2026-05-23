import {
  pickNextTrackForDetailedAnalysis,
  preferDetailedTrackAnalysis,
  shouldBuildDetailedTrackAnalysis
} from '../../src/renderer/player/trackAnalysisQueue';
import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION } from '../../src/shared/analysis';
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
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    bpm: 124,
    bpmConfidence: 0.7,
    waveformPeaks: [],
    waveformDetail: [],
    analysisConfidence: 0.6
  });

const detailedAnalysis = (trackId: string) =>
  sanitizeTrackAnalysis(trackId, {
    schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
    bpm: 124,
    bpmConfidence: 0.9,
    waveformPeaks: [{ timeSec: 0, peak: 0.4, rms: 0.2 }],
    waveformDetail: [{ timeSec: 0, peak: 0.4, rms: 0.2, min: -0.3, max: 0.3 }],
    spectralBands: [{ timeSec: 0, low: 0.4, mid: 0.3, high: 0.2 }],
    energyProfile: [0.2, 0.5, 0.4],
    barGrid: [{ index: 0, startSec: 0, beatIndex: 0 }],
    analysisConfidence: 0.85,
    analysisQuality: {
      waveformDetail: 0.4,
      spectralBands: 0.4,
      transientMarkers: 0,
      beatGrid: 0.7
    }
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

  it('queues low-confidence beat grids even when waveform detail exists', () => {
    const lowBeatGrid = sanitizeTrackAnalysis('a', {
      schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
      bpm: 124,
      bpmConfidence: 0.9,
      waveformPeaks: [{ timeSec: 0, peak: 0.4, rms: 0.2 }],
      waveformDetail: [{ timeSec: 0, peak: 0.4, rms: 0.2, min: -0.3, max: 0.3 }],
      energyProfile: [0.2, 0.5, 0.4],
      barGrid: [{ index: 0, startSec: 0, beatIndex: 0 }],
      analysisQuality: {
        waveformDetail: 0.4,
        spectralBands: 0,
        transientMarkers: 0,
        beatGrid: 0.2
      }
    });

    expect(shouldBuildDetailedTrackAnalysis(lowBeatGrid)).toBe(true);
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
