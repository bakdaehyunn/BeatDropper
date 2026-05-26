#!/usr/bin/env node

const { spawnSync } = require('node:child_process');

const result = spawnSync(
  'swift',
  ['run', '--package-path', 'native', 'BeatDropperNativeAnalysisBenchmarks', ...process.argv.slice(2)],
  {
    cwd: process.cwd(),
    stdio: 'inherit'
  }
);

if (result.error) {
  process.stderr.write(`${result.error.message}\n`);
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
