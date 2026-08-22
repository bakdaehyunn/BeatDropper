#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseArguments, repositoryRoot, writeJsonReport } = require('./lib/native-tooling.cjs');

const requiredMenus = ['File', 'Set', 'Playback', 'Workspace'];
const requiredDocumentTypes = ['public.audio', 'public.mp3', 'com.microsoft.waveform-audio', 'public.folder'];
const requiredShortcuts = [
  'newSet', 'addTracks', 'importFolder', 'playPause', 'aiMix',
  'nextTrack', 'previousTrack', 'playingWorkspace', 'creativeWorkspace',
];

let options;
try {
  options = parseArguments(process.argv.slice(2), { 'write-json': 'string' });
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
if (options.help || options.h) {
  process.stdout.write('Usage: node scripts/check-native-macos-shell.cjs [--write-json path]\n');
  process.exit(0);
}

const contractPath = path.join(repositoryRoot, 'native', 'Contracts', 'native-ui-contract.json');
const infoPlistPath = path.join(repositoryRoot, 'native', 'Packaging', 'Info.plist');
const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
const shell = contract.macosShell || {};
const menus = new Set(shell.menus || []);
const documentTypes = new Set(shell.documentTypes || []);
const shortcuts = shell.shortcuts || {};
const plist = fs.readFileSync(infoPlistPath, 'utf8');
const checks = [
  ...requiredMenus.map((value) => ({ label: `menu contract: ${value}`, status: menus.has(value) ? 'pass' : 'fail' })),
  ...requiredShortcuts.map((value) => ({ label: `shortcut contract: ${value}`, status: shortcuts[value] ? 'pass' : 'fail' })),
  ...requiredDocumentTypes.map((value) => ({
    label: `document type: ${value}`,
    status: documentTypes.has(value) && plist.includes(value) ? 'pass' : 'fail',
  })),
  { label: 'standard Settings scene contract', status: shell.settingsScene === true ? 'pass' : 'fail' },
  { label: 'Finder Open contract', status: shell.finderOpen === true ? 'pass' : 'fail' },
  { label: 'file drag/drop contract', status: shell.dragAndDrop === true ? 'pass' : 'fail' },
];
const failures = checks.filter(({ status }) => status === 'fail');
const report = {
  schemaVersion: 2,
  generatedAt: new Date().toISOString(),
  kind: 'native-macos-shell-contract-check',
  status: failures.length ? 'FAIL' : 'PASS',
  sources: {
    contract: path.relative(repositoryRoot, contractPath),
    infoPlist: path.relative(repositoryRoot, infoPlistPath),
  },
  summary: { checkCount: checks.length, failCount: failures.length },
  checks,
};
if (options['write-json']) writeJsonReport(options['write-json'], report);
process.stdout.write(`# Native macOS Shell Contract Check\nstatus ${report.status}\nchecks ${checks.length}\n`);
for (const failure of failures) process.stdout.write(`- ${failure.label}\n`);
process.exit(failures.length ? 1 : 0);
