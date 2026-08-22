#!/usr/bin/env node
'use strict';

const { parseArguments, swiftTest, writeJsonReport } = require('./lib/native-tooling.cjs');

const timeoutMs = 45_000;
const options = parseArguments(process.argv.slice(2), { 'write-json': 'string', help: 'boolean' });
const reportPath = options['write-json'];
const base = (status) => ({
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  kind: 'open-import-stress',
  status,
  harness: {
    kind: 'swift-test',
    target: 'BeatDropperNativeTests',
    filter: 'BeatDropperNativeAutomationTests/openImportStress',
  },
  stress: {
    timeoutMs,
    expectedOpened: 3,
    expectedLibraryRecords: 3,
    expectedSourceFolders: 1,
    expectedAnalyzedAtLeast: 3,
  },
});

try {
  if (options.help) {
    process.stdout.write('Usage: node scripts/stress-native-open-import.cjs [--write-json <path>]\n');
    process.exit(0);
  }
  const launched = swiftTest('BeatDropperNativeAutomationTests/openImportStress', {
    timeout: timeoutMs,
    env: { ...process.env, BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS: '1' },
  });
  const output = `${launched.stdout || ''}${launched.stderr || ''}`;
  if (launched.status !== 0) throw new Error(output.trim() || 'native open-import automation test failed');
  const match = output.match(/BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS_READY opened=(\d+) library=(\d+) sourceFolders=(\d+) analyzed=(\d+) state=([^\s]+)/);
  if (!match) throw new Error(`open-import automation marker missing. Output:\n${output}`);
  const result = {
    opened: Number(match[1]),
    library: Number(match[2]),
    sourceFolders: Number(match[3]),
    analyzed: Number(match[4]),
    finalState: match[5],
  };
  if (result.opened !== 3 || result.library !== 3 || result.sourceFolders !== 1 || result.analyzed < 3 || result.finalState !== 'Idle') {
    throw new Error(`open-import invariants failed. Output:\n${output}`);
  }
  if (reportPath) writeJsonReport(reportPath, {
    ...base('PASS'),
    launch: { ok: true, status: launched.status, signal: launched.signal },
    result,
  });
  process.stdout.write([
    'BeatDropper native open-import stress passed.',
    `opened ${result.opened}`,
    `library records ${result.library}`,
    `source folders ${result.sourceFolders}`,
    `analyzed ${result.analyzed}`,
    `final state ${result.finalState}`,
  ].join('\n') + '\n');
} catch (error) {
  if (reportPath) writeJsonReport(reportPath, { ...base('FAIL'), error: error.message });
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
