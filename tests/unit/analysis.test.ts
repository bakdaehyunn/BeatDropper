import { sanitizeTrackAnalysis, TRACK_ANALYSIS_SCHEMA_VERSION } from '../../src/shared/analysis';

describe('sanitizeTrackAnalysis', () => {
  it('keeps older cached analysis readable and marks it for upgrade', () => {
    const analysis = sanitizeTrackAnalysis('track-1', {
      schemaVersion: 2 as typeof TRACK_ANALYSIS_SCHEMA_VERSION,
      bpm: 124,
      waveformPeaks: [{ timeSec: 0, peak: 0.7, rms: 0.4 }],
      analysisConfidence: 0.6
    });

    expect(analysis.schemaVersion).toBe(TRACK_ANALYSIS_SCHEMA_VERSION);
    expect(analysis.waveformPeaks).toHaveLength(1);
    expect(analysis.waveformDetail).toEqual([]);
    expect(analysis.spectralBands).toEqual([]);
    expect(analysis.transientMarkers).toEqual([]);
    expect(analysis.analysisQuality.waveformDetail).toBe(0);
    expect(analysis.analysisWarnings).toContain('analysis_upgrade_available');
  });

  it('clamps v3 waveform detail and spectral band values', () => {
    const analysis = sanitizeTrackAnalysis('track-1', {
      waveformDetail: [{ timeSec: 1, peak: 2, rms: -1, min: -2, max: 2 }],
      spectralBands: [{ timeSec: 1, low: 2, mid: -1, high: 0.5 }],
      transientMarkers: [{ index: 0, timeSec: 1, strength: 2 }],
      analysisQuality: {
        waveformDetail: 2,
        spectralBands: 0.5,
        transientMarkers: -1,
        beatGrid: 0.7
      }
    });

    expect(analysis.waveformDetail[0]).toMatchObject({
      peak: 1,
      rms: 0,
      min: -1,
      max: 1
    });
    expect(analysis.spectralBands[0]).toMatchObject({ low: 1, mid: 0, high: 0.5 });
    expect(analysis.transientMarkers[0]?.strength).toBe(1);
    expect(analysis.analysisQuality).toMatchObject({
      waveformDetail: 1,
      spectralBands: 0.5,
      transientMarkers: 0,
      beatGrid: 0.7
    });
  });
});
