#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { runPersistentAppLaunch } = require('./lib/macos-launch-smoke.cjs');

const rootDir = path.resolve(__dirname, '..');
const appPath = path.join(rootDir, 'native', 'dist', 'BeatDropper.app');
const executablePath = path.join(appPath, 'Contents', 'MacOS', 'BeatDropperNative');
const infoPlistPath = path.join(appPath, 'Contents', 'Info.plist');
const plannerScriptPath = path.join(appPath, 'Contents', 'Resources', 'Scripts', 'codex-mix-planner.cjs');
const bundledNodeRuntimePath = path.join(appPath, 'Contents', 'Resources', 'Runtime', 'node');
const thirdPartyNoticePath = path.join(appPath, 'Contents', 'Resources', 'ThirdParty', 'THIRD-PARTY-NOTICES.txt');
const nodeLicensePath = path.join(appPath, 'Contents', 'Resources', 'ThirdParty', 'Node-LICENSE.txt');

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8',
    ...options
  });
  return {
    ok: result.status === 0,
    status: result.status,
    signal: result.signal,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const fail = (message) => {
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
};

const assertFile = (filePath, label) => {
  if (!fs.existsSync(filePath)) {
    throw new Error(`${label} missing: ${filePath}`);
  }
};

const main = () => {
  const skipLaunch = process.argv.includes('--skip-launch');
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    process.stdout.write(
      [
        'Usage: node scripts/smoke-native-app.cjs [options]',
        '',
        'Options:',
        '  --skip-launch   Verify bundle structure without launching the app.',
        '  --help          Show this message.',
        ''
      ].join('\n')
    );
    return;
  }

  assertFile(appPath, 'BeatDropper.app');
  assertFile(executablePath, 'BeatDropperNative executable');
  assertFile(infoPlistPath, 'Info.plist');
  assertFile(bundledNodeRuntimePath, 'bundled Node runtime');
  assertFile(thirdPartyNoticePath, 'third-party notices');
  assertFile(nodeLicensePath, 'Node license');
  assertFile(plannerScriptPath, 'bundled planner script');

  const plist = run('plutil', ['-lint', infoPlistPath]);
  if (!plist.ok) {
    throw new Error(plist.output || 'Info.plist validation failed');
  }

  const codesign = run('codesign', ['--verify', '--deep', '--strict', appPath]);
  if (!codesign.ok) {
    throw new Error(codesign.output || 'codesign verification failed');
  }

  const bundledNode = run(bundledNodeRuntimePath, ['--version']);
  if (!bundledNode.ok) {
    throw new Error(bundledNode.output || 'bundled Node runtime failed to execute');
  }

  if (skipLaunch) {
    process.stdout.write('BeatDropper native app smoke passed without launch.\n');
    return;
  }

  const launched = runPersistentAppLaunch(executablePath);
  if (!launched.ok) {
    throw new Error(
      launched.output || `native app exited before the ${launched.settleMs}ms launch window`
    );
  }

  process.stdout.write(
    [
      'BeatDropper native app smoke passed.',
      'process active true',
      `launch window ms ${launched.settleMs}`
    ].join('\n') + '\n'
  );
};

try {
  main();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
