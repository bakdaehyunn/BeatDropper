import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const repoRoot = path.resolve(__dirname, '..', '..');

describe('evaluate-analysis-benchmarks script', () => {
  it('prints a readable report and fails when benchmark fixtures include failures', () => {
    const result = spawnSync('node', ['scripts/evaluate-analysis-benchmarks.cjs'], {
      cwd: repoRoot,
      encoding: 'utf8'
    });

    expect(result.status).toBe(1);
    expect(result.stderr).toBe('');
    expect(result.stdout).toContain('# Analysis Benchmarks');
    expect(result.stdout).toContain('grade fail');
    expect(result.stdout).toContain('## Fixture Kinds');
    expect(result.stdout).toContain('synthetic: FAIL');
    expect(result.stdout).toContain('snapshot: PASS');
    expect(result.stdout).toContain('## clean-124-phrase');
    expect(result.stdout).toContain('## schema-v7-calibration-pass');
    expect(result.stdout).toContain('## shifted-downbeat-warn');
    expect(result.stdout).toContain('## weak-ambiguous-fail');
    expect(result.stdout).toContain('Kind: synthetic');
    expect(result.stdout).toContain('Key:');
    expect(result.stdout).toContain('Loudness:');
    expect(result.stdout).toContain('Stereo:');
    expect(result.stdout).toContain('BPM error:');
    expect(result.stdout).toContain('Bar grid: checked');
  });

  it('can run only a private snapshot fixture directory', () => {
    const fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-analysis-snapshots-'));
    const fixturePath = path.join(fixtureDir, 'private-snapshot.json');
    fs.writeFileSync(
      fixturePath,
      JSON.stringify(
        {
          id: 'private-snapshot',
          title: 'Private snapshot fixture',
          kind: 'snapshot',
          tags: ['private', 'regression'],
          trackReference: {
            source: 'private-library',
            title: 'Private local reference'
          },
          expectedGrade: 'pass',
          expected: {
            bpm: 124,
            firstDownbeatSec: 0,
            outroCueSec: 96,
            barGridSec: [0, 8, 16, 24],
            phraseBoundarySec: [32],
            plannerReady: true
          },
          analysis: {
            trackId: 'private-snapshot',
            source: 'derived',
            bpm: 124,
            bpmConfidence: 0.88,
            beatGridSec: [0, 2, 4, 6, 8, 10, 12, 14, 16],
            downbeatsSec: [0, 8, 16, 24, 32],
            barGrid: [
              { index: 0, startSec: 0, beatIndex: 0 },
              { index: 1, startSec: 8, beatIndex: 4 },
              { index: 2, startSec: 16, beatIndex: 8 },
              { index: 3, startSec: 24, beatIndex: 12 }
            ],
            phraseMarkers: [{ index: 0, startSec: 32, bars: 8, confidence: 0.82 }],
            introCueSec: 0,
            outroCueSec: 96,
            energyProfile: [0.8, 0.7, 0.6, 0.5],
            waveformDetail: [{ timeSec: 0, peak: 0.8, rms: 0.4, min: -0.6, max: 0.8 }],
            spectralBands: [{ timeSec: 0, low: 0.6, mid: 0.4, high: 0.3 }],
            transientMarkers: [{ index: 0, timeSec: 0, strength: 0.82 }],
            cueCandidates: [
              {
                id: 'first-downbeat',
                type: 'first_downbeat',
                startSec: 0,
                endSec: 4,
                confidence: 0.86,
                label: 'First downbeat'
              },
              {
                id: 'outro',
                type: 'outro',
                startSec: 96,
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
          }
        },
        null,
        2
      ),
      'utf8'
    );

    const result = spawnSync(
      'node',
      [
        'scripts/evaluate-analysis-benchmarks.cjs',
        '--no-default-fixtures',
        '--fixture-dir',
        fixtureDir
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8'
      }
    );

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
    expect(result.stdout).toContain('grade pass');
    expect(result.stdout).toContain('snapshot: PASS');
    expect(result.stdout).toContain('## private-snapshot');
    expect(result.stdout).toContain('Kind: snapshot');
  });
});
