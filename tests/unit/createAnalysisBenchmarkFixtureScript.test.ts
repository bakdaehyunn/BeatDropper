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
});
