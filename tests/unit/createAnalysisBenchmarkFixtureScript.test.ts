import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const repoRoot = path.resolve(__dirname, '..', '..');

const buildAnalysis = () => ({
  trackId: 'private-track-a',
  generatedAt: '2026-05-25T10:00:00.000Z',
  source: 'derived',
  bpm: 124.2,
  bpmConfidence: 0.88,
  beatGridSec: [0.25, 2.185, 4.121, 6.056, 7.992],
  downbeatsSec: [0.25, 7.992, 15.734, 23.476, 31.218],
  barGrid: [
    { index: 0, startSec: 0.25, beatIndex: 0 },
    { index: 1, startSec: 7.992, beatIndex: 4 },
    { index: 2, startSec: 15.734, beatIndex: 8 }
  ],
  phraseMarkers: [{ index: 0, startSec: 31.218, bars: 8, confidence: 0.82 }],
  introCueSec: 0.25,
  outroCueSec: 96.4,
  energyProfile: [0.82, 0.74, 0.62],
  waveformDetail: [{ timeSec: 0, peak: 0.8, rms: 0.42, min: -0.7, max: 0.8 }],
  spectralBands: [{ timeSec: 0, low: 0.6, mid: 0.44, high: 0.3 }],
  transientMarkers: [{ index: 0, timeSec: 0.25, strength: 0.82 }],
  cueCandidates: [
    {
      id: 'first-downbeat',
      type: 'first_downbeat',
      startSec: 0.25,
      endSec: 4.25,
      confidence: 0.86,
      label: 'First downbeat'
    },
    {
      id: 'outro',
      type: 'outro',
      startSec: 96.4,
      endSec: 112,
      confidence: 0.82,
      label: 'Outro mix-out'
    }
  ],
  analysisConfidence: 0.86,
  analysisQuality: {
    waveformDetail: 0.82,
    spectralBands: 0.8,
    transientMarkers: 0.78,
    beatGrid: 0.86
  },
  analysisWarnings: []
});

describe('create-analysis-benchmark-fixture script', () => {
  it('creates a private snapshot fixture from an analysis JSON file', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-create-fixture-'));
    const analysisPath = path.join(tempDir, 'analysis.json');
    const outDir = path.join(tempDir, 'snapshots');
    fs.writeFileSync(analysisPath, JSON.stringify(buildAnalysis(), null, 2), 'utf8');

    const result = spawnSync(
      'node',
      [
        'scripts/create-analysis-benchmark-fixture.cjs',
        '--analysis-file',
        analysisPath,
        '--out-dir',
        outDir,
        '--id',
        'private-fixture-a',
        '--title',
        'Private Fixture A',
        '--artist',
        'Private Artist',
        '--track-title',
        'Private Track',
        '--tags',
        'private,house',
        '--expected-bpm',
        '124',
        '--first-downbeat',
        '0',
        '--outro',
        '96',
        '--bar-grid',
        '0,7.742,15.484',
        '--phrase-boundaries',
        '31.0',
        '--planner-ready',
        'true'
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8'
      }
    );

    const fixturePath = path.join(outDir, 'private-fixture-a.json');
    const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
    expect(result.stdout).toContain('Created');
    expect(result.stdout).toContain('npm run native:benchmark:analysis');
    expect(fixture.kind).toBe('snapshot');
    expect(fixture.title).toBe('Private Fixture A');
    expect(fixture.tags).toEqual(['private', 'house']);
    expect(fixture.trackReference).toEqual(
      expect.objectContaining({
        source: 'private-library',
        artist: 'Private Artist',
        title: 'Private Track'
      })
    );
    expect(fixture.expected).toEqual({
      bpm: 124,
      firstDownbeatSec: 0,
      outroCueSec: 96,
      barGridSec: [0, 7.742, 15.484],
      phraseBoundarySec: [31],
      plannerReady: true
    });
    expect(fixture.analysis.trackId).toBe('private-track-a');
  });

  it('lists saved analysis cache entries so users can find a track id', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-analysis-cache-'));
    const trackId = 'private/track a';
    fs.writeFileSync(
      path.join(tempDir, `${encodeURIComponent(trackId)}.json`),
      JSON.stringify({ ...buildAnalysis(), trackId }, null, 2),
      'utf8'
    );

    const result = spawnSync(
      'node',
      ['scripts/create-analysis-benchmark-fixture.cjs', '--cache-dir', tempDir, '--list-cache'],
      {
        cwd: repoRoot,
        encoding: 'utf8'
      }
    );

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
    expect(result.stdout).toContain('# Analysis Cache');
    expect(result.stdout).toContain('entries 1');
    expect(result.stdout).toContain('private/track a');
    expect(result.stdout).toContain('bpm 124.20');
  });

  it('writes and loads editable ground-truth label files', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-labels-'));
    const analysisPath = path.join(tempDir, 'analysis.json');
    const labelsPath = path.join(tempDir, 'labels.json');
    const outDir = path.join(tempDir, 'snapshots');
    fs.writeFileSync(
      analysisPath,
      JSON.stringify(
        {
          ...buildAnalysis(),
          loudness: {
            integratedRMSDb: -10.2,
            integratedLUFS: -9.8,
            peakDb: -0.7,
            truePeakDb: -0.55,
            headroomDb: 0.55,
            crestFactorDb: 9.5,
            dynamicRangeDb: 12.8,
            loudnessRangeLU: 4.1,
            measurement: 'ebu_r128_k_weighted_gated_mono',
            confidence: 0.82
          }
        },
        null,
        2
      ),
      'utf8'
    );

    const writeResult = spawnSync(
      'node',
      [
        'scripts/create-analysis-benchmark-fixture.cjs',
        '--analysis-file',
        analysisPath,
        '--out-dir',
        outDir,
        '--id',
        'label-fixture',
        '--write-labels',
        labelsPath
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8'
      }
    );
    expect(writeResult.status).toBe(0);
    const labels = JSON.parse(fs.readFileSync(labelsPath, 'utf8'));
    expect(labels.expected.loudness).toMatchObject({
      integratedLUFS: -9.8,
      truePeakDb: -0.55
    });

    labels.expected.bpm = 123;
    labels.reviewedBy = 'calibration-reviewer';
    fs.writeFileSync(labelsPath, JSON.stringify(labels, null, 2), 'utf8');

    const loadResult = spawnSync(
      'node',
      [
        'scripts/create-analysis-benchmark-fixture.cjs',
        '--analysis-file',
        analysisPath,
        '--out-dir',
        outDir,
        '--id',
        'label-fixture',
        '--labels-file',
        labelsPath,
        '--overwrite'
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8'
      }
    );
    const fixture = JSON.parse(fs.readFileSync(path.join(outDir, 'label-fixture.json'), 'utf8'));

    expect(loadResult.status).toBe(0);
    expect(fixture.expected.bpm).toBe(123);
    expect(fixture.groundTruthLabels.reviewedBy).toBe('calibration-reviewer');
    expect(fixture.groundTruthLabels.expected.loudness.integratedLUFS).toBe(-9.8);
  });

  it('creates an anonymized schema-v2 real-audio corpus fixture', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-real-corpus-'));
    const analysisPath = path.join(tempDir, 'analysis.json');
    const outDir = path.join(tempDir, 'corpus');
    fs.writeFileSync(
      analysisPath,
      JSON.stringify({
        ...buildAnalysis(),
        musicalKey: { tonic: 'C', mode: 'minor', confidence: 0.82, chromaEnergy: 10 },
        loudness: {
          integratedRMSDb: -12.5,
          integratedLUFS: -12,
          peakDb: -1.2,
          truePeakDb: -1,
          headroomDb: 1,
          crestFactorDb: 8,
          dynamicRangeDb: 6,
          confidence: 0.9
        }
      }),
      'utf8'
    );

    const result = spawnSync(
      'node',
      [
        'scripts/create-analysis-benchmark-fixture.cjs',
        '--analysis-file', analysisPath,
        '--out-dir', outDir,
        '--id', 'opaque-fixture',
        '--real-audio',
        '--split', 'calibration',
        '--asset-id', 'asset-opaque-001',
        '--audio-rights', 'private_user_owned',
        '--duration', '120',
        '--sample-rate', '48000',
        '--channel-count', '2',
        '--tempo-profile', 'fixed',
        '--genre-tags', 'house,electronic',
        '--reviewed-by', 'reviewer-01'
      ],
      { cwd: repoRoot, encoding: 'utf8' }
    );
    const fixture = JSON.parse(fs.readFileSync(path.join(outDir, 'opaque-fixture.json'), 'utf8'));

    expect(result.status).toBe(0);
    expect(fixture.kind).toBe('real_audio');
    expect(fixture.trackReference).toBeUndefined();
    expect(fixture.corpus).toMatchObject({
      schemaVersion: 2,
      split: 'calibration',
      anonymizedAssetId: 'asset-opaque-001',
      audioRights: 'private_user_owned',
      audioDurationSec: 120,
      sampleRate: 48000,
      channelCount: 2,
      tempoProfile: 'fixed'
    });
    expect(fixture.expected.downbeatSec).toHaveLength(5);
    expect(fixture.expected.musicalKey).toEqual({ tonic: 'C', mode: 'minor' });
    expect(fixture.expected.loudness).toMatchObject({ integratedLUFS: -12, truePeakDb: -1 });
    expect(fixture.expected.cueCandidates).toHaveLength(2);
    expect(fixture.groundTruthLabels.reviewedBy).toBe('reviewer-01');
  });
});
