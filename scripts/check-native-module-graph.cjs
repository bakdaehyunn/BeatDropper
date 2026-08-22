#!/usr/bin/env node
'use strict';

const { run } = require('./lib/native-tooling.cjs');

const expected = {
  BeatDropperDomain: [],
  BeatDropperDSP: ['BeatDropperDomain'],
  BeatDropperLibrary: ['BeatDropperDomain'],
  BeatDropperReview: ['BeatDropperDomain', 'BeatDropperDSP'],
  BeatDropperPlanning: ['BeatDropperDomain', 'BeatDropperDSP', 'BeatDropperLibrary', 'BeatDropperReview'],
  BeatDropperPlatform: ['BeatDropperApplication', 'BeatDropperDSP', 'BeatDropperLibrary', 'BeatDropperPlanning', 'BeatDropperReview'],
  BeatDropperApplication: ['BeatDropperDomain', 'BeatDropperDSP', 'BeatDropperLibrary', 'BeatDropperPlanning', 'BeatDropperReview'],
  BeatDropperTestSupport: ['BeatDropperDomain', 'BeatDropperDSP', 'BeatDropperLibrary', 'BeatDropperPlanning', 'BeatDropperReview', 'BeatDropperPlatform'],
  BeatDropperNative: ['BeatDropperApplication', 'BeatDropperPlatform'],
  BeatDropperNativeApp: ['BeatDropperNative'],
};

const result = run('swift', ['package', '--package-path', 'native', 'describe', '--type', 'json'], {
  capture: true,
  stdio: 'pipe',
});
if (result.status !== 0) {
  process.stderr.write(result.stderr || 'swift package describe failed\n');
  process.exit(result.status || 1);
}

const description = JSON.parse(result.stdout);
const targets = new Map(description.targets.map((target) => [target.name, target]));
const failures = [];
for (const [name, dependencies] of Object.entries(expected)) {
  const target = targets.get(name);
  if (!target) {
    failures.push(`missing target ${name}`);
    continue;
  }
  const actual = [...(target.target_dependencies || [])].sort();
  const wanted = [...dependencies].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) {
    failures.push(`${name} dependencies ${actual.join(',')} != ${wanted.join(',')}`);
  }
}

const visiting = new Set();
const visited = new Set();
function visit(name, path = []) {
  if (visiting.has(name)) {
    failures.push(`dependency cycle ${[...path, name].join(' -> ')}`);
    return;
  }
  if (visited.has(name)) return;
  visiting.add(name);
  for (const dependency of targets.get(name)?.target_dependencies || []) visit(dependency, [...path, name]);
  visiting.delete(name);
  visited.add(name);
}
for (const name of Object.keys(expected)) visit(name);

for (const name of ['BeatDropperDomain', 'BeatDropperDSP', 'BeatDropperLibrary', 'BeatDropperPlanning', 'BeatDropperReview', 'BeatDropperApplication', 'BeatDropperPlatform', 'BeatDropperNative', 'BeatDropperNativeApp']) {
  const forbidden = (targets.get(name)?.sources || []).filter((source) => /Benchmark|Stress/.test(source));
  if (forbidden.length) failures.push(`${name} compiles automation sources: ${forbidden.join(',')}`);
}

process.stdout.write(`# Native Module Graph Check\nstatus ${failures.length ? 'FAIL' : 'PASS'}\ntargets ${Object.keys(expected).length}\n`);
for (const failure of failures) process.stdout.write(`- ${failure}\n`);
process.exit(failures.length ? 1 : 0);
