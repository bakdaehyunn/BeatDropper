#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseArguments, repositoryRoot, run } = require('./lib/native-tooling.cjs');

const checks = [];
const add = (category, name, passed, detail, blocked = false) => checks.push({
  category,
  name,
  status: passed ? 'pass' : blocked ? 'blocked' : 'blocked',
  detail,
});
const readJson = (relativePath) => {
  try { return JSON.parse(fs.readFileSync(path.join(repositoryRoot, relativePath), 'utf8')); } catch { return null; }
};
const exists = (relativePath) => fs.existsSync(path.join(repositoryRoot, relativePath));

let options;
try {
  options = parseArguments(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
if (options.help || options.h) {
  process.stdout.write('Usage: node scripts/evaluate-native-parity.cjs [--report-only] [--allow-missing-extended-stress]\n');
  process.exit(0);
}

const graph = run('node', ['scripts/check-native-module-graph.cjs'], { capture: true, stdio: 'pipe' });
add('architecture contracts', 'acyclic Swift target graph', graph.status === 0, graph.stdout || graph.stderr);
add('architecture contracts', 'stable native UI contract', exists('native/Contracts/native-ui-contract.json'), 'native/Contracts/native-ui-contract.json');

for (const [name, file] of [
  ['analysis benchmark gate', 'native/dist/analysis-benchmark-report.json'],
  ['planner benchmark', 'native/dist/planner-benchmark-report.json'],
  ['accessibility contract', 'native/dist/accessibility-check-report.json'],
  ['macOS shell contract', 'native/dist/macos-shell-check-report.json'],
  ['open-import stress', 'native/dist/open-import-stress-report.json'],
  ['playback stress', 'native/dist/playback-stress-report.json'],
  ['session stress', 'native/dist/session-stress-report.json'],
]) {
  const report = readJson(file);
  add('behavioral evidence', name, report?.status === 'PASS', report ? `${file} status ${report.status}` : `${file} missing`);
}
const extended = readJson('native/dist/session-stress-extended-report.json');
add(
  'behavioral evidence',
  'extended session stress',
  extended?.status === 'PASS' || options['allow-missing-extended-stress'],
  extended ? `native/dist/session-stress-extended-report.json status ${extended.status}` : 'allowed to be absent for quick preflight'
);

for (const artifact of [
  'native/dist/BeatDropper.app', 'native/dist/BeatDropper.zip', 'native/dist/BeatDropper.dmg',
  'native/dist/release-manifest.json',
]) add('distribution artifacts', artifact, exists(artifact), exists(artifact) ? 'present' : 'missing');

const packageJson = readJson('package.json');
const packageLock = readJson('package-lock.json');
const hasElectron = Boolean(packageJson?.dependencies?.electron || packageJson?.devDependencies?.electron || packageLock?.packages?.['node_modules/electron']);
add('runtime boundaries', 'no Electron application dependency', !hasElectron, hasElectron ? 'Electron dependency found' : 'Node remains tooling/planner only');

const appPath = path.join(repositoryRoot, 'native', 'dist', 'BeatDropper.app');
const codesign = exists('native/dist/BeatDropper.app')
  ? run('codesign', ['-dv', '--verbose=4', appPath], { capture: true, stdio: 'pipe' })
  : { status: 1, stdout: '', stderr: '' };
const signatureText = `${codesign.stdout || ''}${codesign.stderr || ''}`;
const developerSigned = codesign.status === 0 && /Authority=Developer ID Application:/.test(signatureText);
add(
  'release blockers', 'Developer ID signing', developerSigned,
  developerSigned ? 'Developer ID signature present' : 'current app is ad-hoc signed', true
);

const gatekeeper = exists('native/dist/BeatDropper.app')
  ? run('spctl', ['--assess', '--type', 'execute', '--verbose=4', appPath], { capture: true, stdio: 'pipe' })
  : { status: 1, stdout: '', stderr: '' };
add(
  'release blockers', 'Gatekeeper assessment', gatekeeper.status === 0,
  gatekeeper.status === 0 ? 'Gatekeeper accepted current app' : 'current ad-hoc app is not accepted', true
);

const strictReport = readJson('native/dist/release-verification-report.json');
add(
  'release blockers', 'Strict release verification report', strictReport?.status === 'PASS',
  strictReport?.status === 'PASS' ? 'strict notarized release evidence is current' : 'requires Developer ID/notary credentials', true
);

const grouped = new Map();
for (const check of checks) {
  if (!grouped.has(check.category)) grouped.set(check.category, []);
  grouped.get(check.category).push(check);
}
const totals = checks.reduce((result, check) => ({ ...result, [check.status]: result[check.status] + 1 }), { pass: 0, blocked: 0 });
const status = totals.blocked ? 'BLOCKED' : 'PASS';
process.stdout.write(`# Native Parity Audit\nstatus ${status}\npass ${totals.pass}\nblocked ${totals.blocked}\n`);
for (const [category, items] of grouped) {
  process.stdout.write(`## ${category}\n`);
  for (const item of items) process.stdout.write(`- ${item.status.toUpperCase()} ${item.name}: ${item.detail}\n`);
}
if (totals.blocked && !options['report-only']) process.exitCode = 1;
