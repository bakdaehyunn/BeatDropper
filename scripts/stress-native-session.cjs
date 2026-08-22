#!/usr/bin/env node
'use strict';

const { parseArguments, swiftTest, writeJsonReport } = require('./lib/native-tooling.cjs');

const options = parseArguments(process.argv.slice(2), {
  extended: 'boolean',
  tracks: 'number',
  transitions: 'number',
  'write-json': 'string',
  help: 'boolean',
});
const counts = {
  trackCount: Number.isFinite(options.tracks) ? Math.trunc(options.tracks) : options.extended ? 12 : 4,
  transitionCount: Number.isFinite(options.transitions) ? Math.trunc(options.transitions) : options.extended ? 6 : 1,
};
const timeoutMs = options.extended ? 120_000 : 90_000;
const reportPath = options['write-json'];
const base = (status) => ({
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  kind: 'session-stress',
  status,
  harness: {
    kind: 'swift-test',
    target: 'BeatDropperNativeTests',
    filter: 'BeatDropperNativeAutomationTests/sessionStress',
  },
  stress: {
    mode: options.extended ? 'extended' : 'normal',
    extended: Boolean(options.extended),
    trackCount: counts.trackCount,
    transitionCount: counts.transitionCount,
    timeoutMs,
  },
});

try {
  if (options.help) {
    process.stdout.write('Usage: node scripts/stress-native-session.cjs [--extended] [--tracks=<n>] [--transitions=<n>] [--write-json <path>]\n');
    process.exit(0);
  }
  const launched = swiftTest('BeatDropperNativeAutomationTests/sessionStress', {
    timeout: timeoutMs,
    env: {
      ...process.env,
      BEATDROPPER_NATIVE_SESSION_STRESS: '1',
      BEATDROPPER_NATIVE_SESSION_STRESS_TRACKS: String(counts.trackCount),
      BEATDROPPER_NATIVE_SESSION_STRESS_TRANSITIONS: String(counts.transitionCount),
    },
  });
  const output = `${launched.stdout || ''}${launched.stderr || ''}`;
  if (launched.status !== 0) throw new Error(output.trim() || 'native session automation test failed');
  const match = output.match(/BEATDROPPER_NATIVE_SESSION_STRESS_READY imported=(\d+) analyzed=(\d+) maxRunning=(\d+) planConfidence=([0-9.]+) state=([^\s]+) transitions=(\d+)/);
  if (!match) throw new Error(`session automation marker missing. Output:\n${output}`);
  const result = {
    imported: Number(match[1]),
    analyzed: Number(match[2]),
    maxRunning: Number(match[3]),
    planConfidence: Number(match[4]),
    finalState: match[5],
    transitions: Number(match[6]),
  };
  const expectedTransitions = Math.min(counts.transitionCount, result.imported - 1);
  if (result.imported < counts.trackCount || result.analyzed < result.imported ||
      result.maxRunning < 1 || result.maxRunning > 4 || result.planConfidence <= 0 ||
      result.finalState !== 'Idle' || result.transitions < expectedTransitions) {
    throw new Error(`session invariants failed. Output:\n${output}`);
  }
  if (reportPath) writeJsonReport(reportPath, {
    ...base('PASS'),
    launch: { ok: true, status: launched.status, signal: launched.signal },
    result,
  });
  process.stdout.write([
    `BeatDropper native ${options.extended ? 'extended ' : ''}session stress passed.`,
    `imported ${result.imported}`,
    `analyzed ${result.analyzed}`,
    `max analysis concurrency ${result.maxRunning}`,
    `plan confidence ${result.planConfidence.toFixed(2)}`,
    `transitions ${result.transitions}`,
    `final state ${result.finalState}`,
  ].join('\n') + '\n');
} catch (error) {
  if (reportPath) writeJsonReport(reportPath, { ...base('FAIL'), error: error.message });
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
