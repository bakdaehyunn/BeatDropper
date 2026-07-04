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
    expect(analysis.analysisQuality.harmonicKey).toBe(0);
    expect(analysis.musicalKey).toBeNull();
    expect(analysis.loudness).toBeNull();
    expect(analysis.analysisWarnings).toContain('analysis_upgrade_available');
  });

  it('marks current-schema metadata-only analysis for planner detail upgrade', () => {
    const analysis = sanitizeTrackAnalysis('track-1', {
      schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
      source: 'metadata',
      bpm: 124,
      bpmConfidence: 0.7,
      beatGridSec: [0, 0.48, 0.96],
      downbeatsSec: [0],
      barGrid: [{ index: 0, startSec: 0, beatIndex: 0 }],
      analysisConfidence: 0.6,
      analysisQuality: {
        waveformDetail: 0,
        spectralBands: 0,
        transientMarkers: 0,
        beatGrid: 0.5
      }
    });

    expect(analysis.waveformDetail).toEqual([]);
    expect(analysis.analysisWarnings).toContain('analysis_upgrade_available');
  });

  it('marks v3 heuristic spectral analysis for FFT analyzer upgrade', () => {
    const analysis = sanitizeTrackAnalysis('track-1', {
      schemaVersion: 3 as typeof TRACK_ANALYSIS_SCHEMA_VERSION,
      bpm: 124,
      bpmConfidence: 0.8,
      beatGridSec: [0, 0.48, 0.96],
      downbeatsSec: [0],
      barGrid: [{ index: 0, startSec: 0, beatIndex: 0 }],
      energyProfile: [0.4, 0.5, 0.6],
      waveformDetail: [{ timeSec: 0, peak: 0.6, rms: 0.3, min: -0.2, max: 0.6 }],
      spectralBands: [{ timeSec: 0, low: 0.5, mid: 0.4, high: 0.3 }],
      analysisConfidence: 0.8,
      analysisQuality: {
        waveformDetail: 0.8,
        spectralBands: 0.8,
        transientMarkers: 0.6,
        beatGrid: 0.8
      }
    });

    expect(analysis.schemaVersion).toBe(TRACK_ANALYSIS_SCHEMA_VERSION);
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

  it('treats cue candidates without an origin as heuristic placeholders', () => {
    const analysis = sanitizeTrackAnalysis('track-1', {
      schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
      cueCandidates: [
        {
          id: 'legacy-outro',
          type: 'outro',
          startSec: 84,
          endSec: 96,
          confidence: 0.7,
          label: 'Legacy outro'
        }
      ]
    });

    expect(analysis.cueCandidates[0]?.origin).toBe('heuristic_placeholder');
  });

  it('sanitizes key, loudness, and stereo evidence for schema v7 analysis', () => {
    const analysis = sanitizeTrackAnalysis('track-1', {
      schemaVersion: TRACK_ANALYSIS_SCHEMA_VERSION,
      musicalKey: {
        tonic: 'C#',
        mode: 'minor',
        confidence: 1.5,
        chromaEnergy: -1
      },
      loudness: {
        integratedRMSDb: -18.3,
        integratedLUFS: -17.8,
        peakDb: 2,
        truePeakDb: 2.4,
        headroomDb: -4,
        crestFactorDb: 200,
        dynamicRangeDb: 9.4,
        loudnessRangeLU: 3.8,
        measurement: 'ebu_r128_k_weighted_gated_mono',
        confidence: 2
      },
      stereo: {
        channelCount: 2.8,
        leftPeakDb: 16,
        rightPeakDb: -140,
        leftRMSDb: -18.4,
        rightRMSDb: 18,
        stereoWidth: 2,
        phaseCorrelation: -2,
        midSideBalance: 20,
        confidence: 2
      },
      analysisQuality: {
        waveformDetail: 0.8,
        spectralBands: 0.8,
        transientMarkers: 0.6,
        beatGrid: 0.8,
        harmonicKey: 2
      },
      analysisWarnings: ['key_low_confidence', 'headroom_low']
    });

    expect(analysis.musicalKey).toMatchObject({
      tonic: 'C#',
      mode: 'minor',
      confidence: 1,
      chromaEnergy: 0
    });
    expect(analysis.loudness).toMatchObject({
      integratedRMSDb: -18.3,
      integratedLUFS: -17.8,
      peakDb: 2,
      truePeakDb: 2.4,
      headroomDb: 0,
      crestFactorDb: 80,
      dynamicRangeDb: 9.4,
      loudnessRangeLU: 3.8,
      measurement: 'ebu_r128_k_weighted_gated_mono',
      confidence: 1
    });
    expect(analysis.stereo).toMatchObject({
      channelCount: 2,
      leftPeakDb: 12,
      rightPeakDb: -120,
      leftRMSDb: -18.4,
      rightRMSDb: 12,
      stereoWidth: 1,
      phaseCorrelation: -1,
      midSideBalance: 12,
      confidence: 1
    });
    expect(analysis.analysisQuality.harmonicKey).toBe(1);
    expect(analysis.analysisWarnings).toContain('key_low_confidence');
    expect(analysis.analysisWarnings).toContain('headroom_low');
  });
});
