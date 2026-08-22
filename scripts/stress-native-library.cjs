#!/usr/bin/env node

const { swiftRun } = require('./lib/native-tooling.cjs');

const result = swiftRun('BeatDropperNativeLibraryStress', process.argv.slice(2));

if (result.error) {
  process.stderr.write(`${result.error.message}\n`);
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
