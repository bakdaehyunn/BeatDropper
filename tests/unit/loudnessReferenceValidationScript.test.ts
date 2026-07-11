import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const repoRoot = path.resolve(__dirname, '..', '..');

describe('validate-loudness-reference script', () => {
  it('writes an anonymized blocked report when ffmpeg is unavailable', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-loudness-reference-'));
    const reportPath = path.join(tmpDir, 'report.json');
    const result = spawnSync(
      process.execPath,
      ['scripts/validate-loudness-reference.cjs', '--write-json', reportPath],
      {
        cwd: repoRoot,
        env: { ...process.env, PATH: tmpDir },
        encoding: 'utf8'
      }
    );

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
    expect(result.stdout).toContain('BLOCKED');
    const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
    expect(report).toMatchObject({
      status: 'BLOCKED',
      reason: 'ffmpeg_not_found',
      requiredTool: 'ffmpeg with loudnorm filter',
      tolerances: {
        integratedLUFS: 0.2,
        truePeakDb: 1.8
      }
    });
    expect(JSON.stringify(report)).not.toContain(os.homedir());
  });

  it('writes anonymized folder evidence when batch validation is blocked by missing ffmpeg', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-loudness-reference-folder-'));
    const audioDir = path.join(tmpDir, 'Private Artist - Private Album');
    fs.mkdirSync(audioDir);
    fs.writeFileSync(path.join(audioDir, 'Private Track Name.mp3'), 'not real audio');
    const reportPath = path.join(tmpDir, 'report.json');
    const result = spawnSync(
      process.execPath,
      [
        'scripts/validate-loudness-reference.cjs',
        '--folder',
        audioDir,
        '--write-json',
        reportPath
      ],
      {
        cwd: repoRoot,
        env: { ...process.env, PATH: tmpDir },
        encoding: 'utf8'
      }
    );

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
    expect(result.stdout).toContain('BLOCKED');
    const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
    expect(report).toMatchObject({
      status: 'BLOCKED',
      reason: 'ffmpeg_not_found',
      folder: {
        pathProvided: true,
        supportedFileCount: 1,
        selectedFileCount: 1,
        staged: true
      }
    });
    const serialized = JSON.stringify(report);
    expect(serialized).not.toContain(audioDir);
    expect(serialized).not.toContain('Private Artist');
    expect(serialized).not.toContain('Private Track Name');
  });
});
