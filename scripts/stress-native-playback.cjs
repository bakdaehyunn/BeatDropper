#!/usr/bin/env node
'use strict';

const {
  parseArguments,
  swiftRun,
  writeJsonReport,
} = require('./lib/native-tooling.cjs');

const timeoutMs = 60_000;
const options = parseArguments(process.argv.slice(2), { 'write-json': 'string', help: 'boolean' });
const reportPath = options['write-json'];

function compact(output) {
  const lines = String(output || '').split('\n').filter(Boolean);
  return lines.length <= 12 ? lines : [...lines.slice(0, 6), '...', ...lines.slice(-6)];
}

function base(status) {
  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    kind: 'playback-stress',
    status,
    harness: {
      kind: 'swift-executable',
      product: 'BeatDropperNativePlaybackStress',
    },
    stress: { timeoutMs },
  };
}

try {
  if (options.help) {
    process.stdout.write('Usage: node scripts/stress-native-playback.cjs [--write-json <path>]\n');
    process.exit(0);
  }
  const launched = swiftRun('BeatDropperNativePlaybackStress', [], {
    capture: true,
    stdio: 'pipe',
    timeout: timeoutMs,
  });
  const output = `${launched.stdout || ''}${launched.stderr || ''}`;
  if (launched.status !== 0) throw new Error(output.trim() || 'native playback automation test failed');
  const match = output.match(/BEATDROPPER_NATIVE_PLAYBACK_STRESS_READY state=([^\s]+) transitions=(\d+) incomingPlayhead=(true|false) pauseResume=(true|false) recovery=(true|false)/);
  if (!match) throw new Error(`playback automation marker missing. Output:\n${output}`);
  if (match[1] !== 'Idle' || Number(match[2]) < 2 || match[3] !== 'true' || match[4] !== 'true' || match[5] !== 'true') {
    throw new Error(`playback invariants failed. Output:\n${output}`);
  }
  const report = {
    ...base('PASS'),
    launch: { ok: true, status: launched.status, signal: launched.signal, outputPreview: compact(output) },
    result: {
      finalState: match[1],
      transitionsCompleted: Number(match[2]),
      incomingPlayheadAdvanced: match[3] === 'true',
      crossfadePauseResumePassed: match[4] === 'true',
      deviceRecoveryPassed: match[5] === 'true',
    },
  };
  if (reportPath) writeJsonReport(reportPath, report);
  process.stdout.write(`BeatDropper native playback stress passed.\nfinal state ${match[1]}\n`);
} catch (error) {
  if (reportPath) writeJsonReport(reportPath, { ...base('FAIL'), error: error.message });
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
