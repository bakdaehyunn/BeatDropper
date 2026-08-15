#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline/promises');

const fail = (message) => {
  throw new Error(message);
};

const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, 'utf8'));

const parseArgs = (argv) => {
  const options = { playback: true };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) fail(`${arg} requires a value.`);
      return argv[index];
    };
    if (arg === '--batch-dir') options.batchDir = path.resolve(next());
    else if (arg === '--audio-map') options.audioMap = path.resolve(next());
    else if (arg === '--reviewer') options.reviewer = next().trim();
    else if (arg === '--fixture') options.fixtureId = next();
    else if (arg === '--answers') options.answers = path.resolve(next());
    else if (arg === '--no-playback') options.playback = false;
    else if (arg === '--help' || arg === '-h') options.help = true;
    else fail(`Unknown option: ${arg}`);
  }
  if (!options.help) {
    if (!options.batchDir) fail('--batch-dir is required.');
    if (!options.audioMap) fail('--audio-map is required.');
    if (!options.reviewer) fail('--reviewer is required.');
  }
  return options;
};

const usage = () => process.stdout.write([
  'Usage: node scripts/review-dsp-calibration-batch.cjs --batch-dir <dir> --audio-map <json> --reviewer <id>',
  '',
  'The audio map is private JSON: { "asset-id": "/absolute/path/to/audio.wav" }.',
  'The tool plays timing-click and key excerpts, then records accept/edit/reject decisions.',
  'Use --fixture <id> to review one fixture. --answers and --no-playback are test-only automation.',
  ''
].join('\n'));

const writeWave = (filePath, durationSec, clickOffsetsSec, sampleRate = 48000) => {
  const sampleCount = Math.ceil(durationSec * sampleRate);
  const dataBytes = sampleCount * 2;
  const buffer = Buffer.alloc(44 + dataBytes);
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write('WAVEfmt ', 8);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataBytes, 40);
  for (const offset of clickOffsetsSec) {
    const start = Math.max(0, Math.round(offset * sampleRate));
    const length = Math.round(0.025 * sampleRate);
    for (let index = 0; index < length && start + index < sampleCount; index += 1) {
      const envelope = 1 - index / length;
      const sample = Math.round(Math.sin(2 * Math.PI * 1500 * index / sampleRate) * envelope * 24_000);
      buffer.writeInt16LE(sample, 44 + (start + index) * 2);
    }
  }
  fs.writeFileSync(filePath, buffer);
};

const makeTimingPreview = (audioPath, expected, tempDir) => {
  const downbeats = expected.downbeatSec ?? [];
  const anchor = expected.firstDownbeatSec ?? downbeats[0] ?? 0;
  const start = Math.max(0, anchor - 2);
  const duration = 18;
  const clickOffsets = downbeats.filter((value) => value >= start && value <= start + duration).map((value) => value - start);
  const clicks = path.join(tempDir, 'clicks.wav');
  const preview = path.join(tempDir, 'timing-preview.wav');
  writeWave(clicks, duration, clickOffsets);
  const result = spawnSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-y', '-ss', String(start), '-t', String(duration), '-i', audioPath,
    '-i', clicks, '-filter_complex', '[0:a]volume=0.8[a];[1:a]volume=0.5[c];[a][c]amix=inputs=2:duration=first', preview
  ], { encoding: 'utf8' });
  if (result.status !== 0) fail(`Could not create timing preview: ${result.stderr.trim()}`);
  return preview;
};

const play = (filePath) => {
  const result = spawnSync('afplay', [filePath], { stdio: 'inherit' });
  if (result.status !== 0) fail(`afplay failed for ${filePath}`);
};

const normalizeAction = (value) => {
  const action = String(value ?? '').trim().toLowerCase();
  const aliases = { a: 'accept', e: 'edit', r: 'reject', s: 'skip' };
  const normalized = aliases[action] ?? action;
  if (!['accept', 'edit', 'reject', 'skip'].includes(normalized)) fail(`Invalid review action: ${value}`);
  return normalized;
};

const finiteNumber = (value, label) => {
  const number = Number(value);
  if (!Number.isFinite(number)) fail(`${label} must be finite.`);
  return number;
};

const rebuildFixedTiming = (expected, bpm, firstDownbeatSec, durationSec) => {
  const barSec = 240 / bpm;
  const downbeatSec = [];
  for (let time = firstDownbeatSec; time <= durationSec && downbeatSec.length < 32; time += barSec) {
    downbeatSec.push(Number(time.toFixed(3)));
  }
  return {
    ...expected,
    bpm,
    firstDownbeatSec,
    downbeatSec,
    barGridSec: [...downbeatSec],
    phraseBoundarySec: downbeatSec.filter((_, index) => index % 8 === 0),
    cueCandidates: (expected.cueCandidates ?? []).map((cue) =>
      cue.type === 'first_downbeat' ? { ...cue, startSec: firstDownbeatSec } : cue
    )
  };
};

const interactiveAnswer = async (prompt, rl) => rl.question(prompt);

const reviewFixture = async ({ fixture, audioPath, reviewer, fixtureAnswers, playback, interactionMode, rl }) => {
  const expected = fixture.groundTruthLabels?.expected;
  if (!expected) fail(`${fixture.id}: groundTruthLabels.expected is missing.`);
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `beatdropper-review-${fixture.id}-`));
  try {
    if (playback) {
      process.stdout.write(`\n${fixture.id}: timing preview has reference clicks at proposed downbeats.\n`);
      play(makeTimingPreview(audioPath, expected, tempDir));
    }
    const timingRaw = fixtureAnswers?.timing?.action ?? await interactiveAnswer('Timing [a]ccept/[e]dit/[r]eject/[s]kip: ', rl);
    const timingAction = normalizeAction(timingRaw);
    let updatedExpected = expected;
    if (timingAction === 'edit') {
      const bpm = finiteNumber(fixtureAnswers?.timing?.bpm ?? await interactiveAnswer('Correct BPM: ', rl), 'BPM');
      const first = finiteNumber(fixtureAnswers?.timing?.firstDownbeatSec ?? await interactiveAnswer('Correct first downbeat (seconds): ', rl), 'First downbeat');
      if (bpm <= 0 || first < 0 || first >= fixture.corpus.audioDurationSec) fail(`${fixture.id}: edited timing is out of bounds.`);
      updatedExpected = rebuildFixedTiming(expected, bpm, first, fixture.corpus.audioDurationSec);
    }

    if (playback) {
      process.stdout.write(`${fixture.id}: key reference is ${expected.musicalKey?.tonic ?? '--'} ${expected.musicalKey?.mode ?? '--'}. Playing 20 seconds from 30s.\n`);
      const keyPreview = path.join(tempDir, 'key-preview.wav');
      const extract = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-ss', '30', '-t', '20', '-i', audioPath, keyPreview], { encoding: 'utf8' });
      if (extract.status !== 0) fail(`Could not create key preview: ${extract.stderr.trim()}`);
      play(keyPreview);
    }
    const keyRaw = fixtureAnswers?.key?.action ?? await interactiveAnswer('Key [a]ccept/[e]dit/[r]eject/[s]kip: ', rl);
    const keyAction = normalizeAction(keyRaw);
    if (keyAction === 'edit') {
      const tonic = String(fixtureAnswers?.key?.tonic ?? await interactiveAnswer('Correct tonic (C, C#, ...): ', rl)).trim();
      const mode = String(fixtureAnswers?.key?.mode ?? await interactiveAnswer('Correct mode (major/minor): ', rl)).trim().toLowerCase();
      if (!/^[A-G](#|b)?$/.test(tonic) || !['major', 'minor'].includes(mode)) fail(`${fixture.id}: invalid edited key.`);
      updatedExpected = { ...updatedExpected, musicalKey: { tonic, mode } };
    }

    const verified = ['accept', 'edit'].includes(timingAction) && ['accept', 'edit'].includes(keyAction);
    const reviewedAt = new Date().toISOString();
    const receipt = {
      schemaVersion: 1,
      fixtureId: fixture.id,
      assetId: fixture.corpus.anonymizedAssetId,
      reviewer,
      reviewedAt,
      interactionMode,
      status: verified
        ? (interactionMode === 'human_terminal' ? 'human_verified' : 'simulated_verified')
        : (timingAction === 'reject' || keyAction === 'reject' ? 'rejected' : 'incomplete'),
      timing: { action: timingAction },
      key: { action: keyAction },
      sourceAudioSha256: fixtureAnswers?.sourceAudioSha256
    };
    if (verified) {
      fixture.expected = updatedExpected;
      fixture.groundTruthLabels.expected = updatedExpected;
      fixture.groundTruthLabels.reviewedBy = interactionMode === 'human_terminal' ? reviewer : 'SIMULATED_REVIEW';
      fixture.groundTruthLabels.reviewedAt = reviewedAt;
      fixture.groundTruthLabels.notes = `${fixture.groundTruthLabels.notes ?? ''} Human-audition timing/key review completed.`.trim();
    }
    return { fixture, receipt, verified };
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
};

const main = async () => {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) return usage();
  const audioMap = readJson(options.audioMap);
  const answers = options.answers ? readJson(options.answers) : null;
  const interactionMode = answers ? 'answers_file' : 'human_terminal';
  const fixtureFiles = fs.readdirSync(options.batchDir)
    .filter((name) => name.endsWith('.json'))
    .map((name) => path.join(options.batchDir, name))
    .filter((filePath) => !options.fixtureId || path.basename(filePath, '.json') === options.fixtureId)
    .sort();
  if (!fixtureFiles.length) fail('No matching fixtures found.');
  const reviewsDir = path.join(path.dirname(options.batchDir), 'human-reviews');
  fs.mkdirSync(reviewsDir, { recursive: true });
  const rl = answers ? null : readline.createInterface({ input: process.stdin, output: process.stdout });
  let verifiedCount = 0;
  try {
    for (const fixtureFile of fixtureFiles) {
      const fixture = readJson(fixtureFile);
      const assetId = fixture.corpus?.anonymizedAssetId;
      const audioPath = audioMap[assetId];
      if (!audioPath || !path.isAbsolute(audioPath) || !fs.existsSync(audioPath)) fail(`${fixture.id}: private audio mapping is missing or invalid.`);
      const result = await reviewFixture({
        fixture,
        audioPath,
        reviewer: options.reviewer,
        fixtureAnswers: answers?.[fixture.id],
        playback: options.playback,
        interactionMode,
        rl
      });
      fs.writeFileSync(path.join(reviewsDir, `${fixture.id}.json`), `${JSON.stringify(result.receipt, null, 2)}\n`);
      if (result.verified) {
        fs.writeFileSync(fixtureFile, `${JSON.stringify(result.fixture, null, 2)}\n`);
        verifiedCount += 1;
      }
      process.stdout.write(`${fixture.id}: ${result.receipt.status}\n`);
    }
  } finally {
    rl?.close();
  }
  process.stdout.write(`Verified ${verifiedCount}/${fixtureFiles.length} fixture(s) in ${interactionMode} mode.\n`);
};

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
