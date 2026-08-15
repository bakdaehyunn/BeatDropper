#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const audioExtensions = new Set(['.wav', '.aiff', '.aif', '.flac', '.mp3', '.m4a']);

const fail = (message) => { throw new Error(message); };
const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, 'utf8'));

const parseArgs = (argv) => {
  const options = { roots: [], target: 30 };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) fail(`${arg} requires a value.`);
      return argv[index];
    };
    if (arg === '--root') options.roots.push(path.resolve(next()));
    else if (arg === '--manifest') options.manifest = path.resolve(next());
    else if (arg === '--out') options.out = path.resolve(next());
    else if (arg === '--target') options.target = Number(next());
    else if (arg === '--help' || arg === '-h') options.help = true;
    else fail(`Unknown option: ${arg}`);
  }
  if (!options.help) {
    if (!options.roots.length) fail('At least one --root is required.');
    if (!options.out) fail('--out is required.');
    if (!Number.isInteger(options.target) || options.target <= 0) fail('--target must be a positive integer.');
  }
  return options;
};

const usage = () => process.stdout.write([
  'Usage: node scripts/inventory-dsp-calibration-audio.cjs --root <dir> [--root <dir>...] --manifest <private-manifest.json> --out <private-intake.json> --target 30',
  '',
  'Recursively hashes and deduplicates local audio, excludes assets already present in the manifest,',
  'and writes a private intake inventory. It does not copy audio or expose paths in repository files.',
  ''
].join('\n'));

const walk = (root) => {
  if (!fs.existsSync(root)) return [];
  const stat = fs.statSync(root);
  if (stat.isFile()) return audioExtensions.has(path.extname(root).toLowerCase()) ? [root] : [];
  if (!stat.isDirectory()) return [];
  return fs.readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    if (entry.isSymbolicLink()) return [];
    const child = path.join(root, entry.name);
    if (entry.isDirectory()) return walk(child);
    return entry.isFile() && audioExtensions.has(path.extname(entry.name).toLowerCase()) ? [child] : [];
  });
};

const sha256 = (filePath) => {
  const hash = crypto.createHash('sha256');
  const descriptor = fs.openSync(filePath, 'r');
  const buffer = Buffer.alloc(1024 * 1024);
  try {
    let bytesRead;
    do {
      bytesRead = fs.readSync(descriptor, buffer, 0, buffer.length, null);
      if (bytesRead) hash.update(buffer.subarray(0, bytesRead));
    } while (bytesRead);
  } finally {
    fs.closeSync(descriptor);
  }
  return hash.digest('hex');
};

const probe = (filePath) => {
  const result = spawnSync('ffprobe', [
    '-v', 'error', '-select_streams', 'a:0', '-show_entries',
    'format=duration:stream=sample_rate,channels', '-of', 'json', filePath
  ], { encoding: 'utf8' });
  if (result.status !== 0) fail(`ffprobe failed for ${filePath}: ${result.stderr.trim()}`);
  const payload = JSON.parse(result.stdout);
  const stream = payload.streams?.[0] ?? {};
  return {
    durationSec: Number(Number(payload.format?.duration).toFixed(3)),
    sampleRate: Number(stream.sample_rate),
    channelCount: Number(stream.channels)
  };
};

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) return usage();
  const manifest = options.manifest && fs.existsSync(options.manifest) ? readJson(options.manifest) : { fixtures: [] };
  const existingHashes = new Set((manifest.fixtures ?? []).map((item) => item.audioSha256).filter(Boolean));
  const seen = new Map();
  for (const filePath of [...new Set(options.roots.flatMap(walk).map((item) => path.resolve(item)))].sort()) {
    const contentHash = sha256(filePath);
    if (!seen.has(contentHash)) seen.set(contentHash, { path: filePath, sha256: contentHash, duplicates: [] });
    else seen.get(contentHash).duplicates.push(filePath);
  }
  const candidates = [...seen.values()].filter((item) => !existingHashes.has(item.sha256)).map((item, index) => ({
    proposedAssetId: `bd-cal-v1-${String((manifest.fixtureCount ?? existingHashes.size) + index + 1).padStart(3, '0')}`,
    ...item,
    ...probe(item.path)
  }));
  const existingCount = manifest.fixtureCount ?? existingHashes.size;
  const needed = Math.max(0, options.target - existingCount);
  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    targetFixtureCount: options.target,
    existingFixtureCount: existingCount,
    uniqueAudioCount: seen.size,
    newCandidateCount: candidates.length,
    requiredAdditionalCount: needed,
    shortageCount: Math.max(0, needed - candidates.length),
    candidates: candidates.slice(0, needed)
  };
  fs.mkdirSync(path.dirname(options.out), { recursive: true });
  fs.writeFileSync(options.out, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`Found ${seen.size} unique local audio file(s); ${candidates.length} new candidate(s); shortage ${report.shortageCount}.\n`);
  if (report.shortageCount > 0) process.exitCode = 2;
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
