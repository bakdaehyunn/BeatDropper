#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseArguments, repositoryRoot, writeJsonReport } = require('./lib/native-tooling.cjs');

const requiredLabels = [
  'BeatDropper DJ workspace', 'Primary toolbar', 'Workspace mode', 'Live mix monitor',
  'Playing waveform stack', 'Current playlist', 'Library browser', 'Creative workspace',
  'Creative track monitor', 'Creative waveform editor', 'Set energy flow', 'Search library',
];
const requiredCapabilities = [
  'authoritative-incoming-playhead', 'current-and-next-waveform-evidence',
  'transition-plan-evidence', 'reduced-motion-ai-mix-control',
  'responsive-scrollable-workspace', 'keyboard-navigation',
];

function usage() {
  process.stdout.write('Usage: node scripts/check-native-accessibility.cjs [--write-json path]\n');
}

let options;
try {
  options = parseArguments(process.argv.slice(2), { 'write-json': 'string' });
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
if (options.help || options.h) {
  usage();
  process.exit(0);
}

const contractPath = path.join(repositoryRoot, 'native', 'Contracts', 'native-ui-contract.json');
const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
const labels = new Set(contract.accessibility?.labels || []);
const capabilities = new Set(contract.accessibility?.capabilities || []);
const checks = [
  ...requiredLabels.map((value) => ({ label: `accessibility id: ${value}`, status: labels.has(value) ? 'pass' : 'fail' })),
  ...requiredCapabilities.map((value) => ({ label: `accessibility behavior: ${value}`, status: capabilities.has(value) ? 'pass' : 'fail' })),
];
const failures = checks.filter(({ status }) => status === 'fail');
const report = {
  schemaVersion: 2,
  generatedAt: new Date().toISOString(),
  kind: 'native-accessibility-contract-check',
  status: failures.length ? 'FAIL' : 'PASS',
  contract: path.relative(repositoryRoot, contractPath),
  summary: { checkCount: checks.length, failCount: failures.length },
  checks,
};
if (options['write-json']) writeJsonReport(options['write-json'], report);
process.stdout.write(`# Native Accessibility Contract Check\nstatus ${report.status}\nchecks ${checks.length}\n`);
for (const failure of failures) process.stdout.write(`- ${failure.label}\n`);
process.exit(failures.length ? 1 : 0);
