import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const repoRoot = path.resolve(__dirname, '..', '..');

const wave = (seconds = 1, sampleRate = 8_000) => {
  const samples = sampleRate * seconds;
  const buffer = Buffer.alloc(44 + samples * 2);
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + samples * 2, 4);
  buffer.write('WAVEfmt ', 8);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(samples * 2, 40);
  return buffer;
};

describe('DSP calibration workflow scripts', () => {
  it('deduplicates audio and reports an honest expansion shortage', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-intake-'));
    const audioDir = path.join(root, 'audio');
    fs.mkdirSync(audioDir);
    const existing = wave(1);
    const candidate = wave(2);
    fs.writeFileSync(path.join(audioDir, 'existing.wav'), existing);
    fs.writeFileSync(path.join(audioDir, 'duplicate.wav'), existing);
    fs.writeFileSync(path.join(audioDir, 'candidate.wav'), candidate);
    const manifestPath = path.join(root, 'manifest.json');
    fs.writeFileSync(manifestPath, JSON.stringify({
      fixtureCount: 1,
      fixtures: [{ audioSha256: crypto.createHash('sha256').update(existing).digest('hex') }]
    }));
    const out = path.join(root, 'intake.json');

    const result = spawnSync('node', [
      'scripts/inventory-dsp-calibration-audio.cjs', '--root', audioDir,
      '--manifest', manifestPath, '--out', out, '--target', '3'
    ], { cwd: repoRoot, encoding: 'utf8' });

    expect(result.status).toBe(2);
    expect(result.stdout).toContain('2 unique local audio file(s); 1 new candidate(s); shortage 1');
    const report = JSON.parse(fs.readFileSync(out, 'utf8'));
    expect(report.newCandidateCount).toBe(1);
    expect(report.shortageCount).toBe(1);
    expect(report.candidates).toHaveLength(1);
  });

  it('keeps answer-file review visibly simulated while exercising label edits', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-review-'));
    const batchDir = path.join(root, 'calibration-v1');
    fs.mkdirSync(batchDir);
    const audioPath = path.join(root, 'audio.wav');
    fs.writeFileSync(audioPath, wave(4));
    const fixturePath = path.join(batchDir, 'cal-001.json');
    fs.writeFileSync(fixturePath, JSON.stringify({
      id: 'cal-001',
      corpus: { anonymizedAssetId: 'asset-001', audioDurationSec: 4 },
      expected: {},
      groundTruthLabels: {
        schemaVersion: 2,
        reviewedBy: 'old-reviewer',
        reviewedAt: '2026-08-15T00:00:00Z',
        expected: {
          bpm: 120,
          firstDownbeatSec: 0,
          downbeatSec: [0, 2],
          barGridSec: [0, 2],
          phraseBoundarySec: [0],
          musicalKey: { tonic: 'C', mode: 'major' },
          cueCandidates: [{ type: 'first_downbeat', startSec: 0 }]
        }
      }
    }));
    const audioMapPath = path.join(root, 'audio-map.json');
    fs.writeFileSync(audioMapPath, JSON.stringify({ 'asset-001': audioPath }));
    const answersPath = path.join(root, 'answers.json');
    fs.writeFileSync(answersPath, JSON.stringify({
      'cal-001': {
        timing: { action: 'edit', bpm: 100, firstDownbeatSec: 0.5 },
        key: { action: 'edit', tonic: 'D', mode: 'minor' }
      }
    }));

    const result = spawnSync('node', [
      'scripts/review-dsp-calibration-batch.cjs', '--batch-dir', batchDir,
      '--audio-map', audioMapPath, '--reviewer', 'human-01',
      '--answers', answersPath, '--no-playback'
    ], { cwd: repoRoot, encoding: 'utf8' });

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('simulated_verified');
    const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    expect(fixture.groundTruthLabels.reviewedBy).toBe('SIMULATED_REVIEW');
    expect(fixture.groundTruthLabels.expected.bpm).toBe(100);
    expect(fixture.groundTruthLabels.expected.firstDownbeatSec).toBe(0.5);
    expect(fixture.groundTruthLabels.expected.musicalKey).toEqual({ tonic: 'D', mode: 'minor' });
    const receipt = JSON.parse(fs.readFileSync(path.join(root, 'human-reviews', 'cal-001.json'), 'utf8'));
    expect(receipt.status).toBe('simulated_verified');
    expect(receipt.interactionMode).toBe('answers_file');
  });
});
