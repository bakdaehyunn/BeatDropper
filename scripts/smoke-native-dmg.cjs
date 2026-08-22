#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { runPersistentAppLaunch } = require('./lib/macos-launch-smoke.cjs');

const rootDir = path.resolve(__dirname, '..');
const dmgPath = path.join(rootDir, 'native', 'dist', 'BeatDropper.dmg');

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

const assertPath = (targetPath, label) => {
  if (!fs.existsSync(targetPath)) {
    throw new Error(`${label} missing: ${targetPath}`);
  }
};

const parseMountPoint = (plistOutput) => {
  const match = plistOutput.match(/<key>mount-point<\/key>\s*<string>([^<]+)<\/string>/);
  return match?.[1] || null;
};

const detach = (mountPoint) => {
  if (!mountPoint) {
    return;
  }
  const normal = run('hdiutil', ['detach', mountPoint]);
  if (!normal.ok) {
    run('hdiutil', ['detach', '-force', mountPoint]);
  }
};

const main = () => {
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    process.stdout.write(
      [
        'Usage: node scripts/smoke-native-dmg.cjs',
        '',
        'Mounts native/dist/BeatDropper.dmg, verifies the app bundle inside it, launches smoke mode, then detaches.',
        'Run npm run native:package first.',
        ''
      ].join('\n')
    );
    return;
  }

  assertPath(dmgPath, 'BeatDropper.dmg');

  const verify = run('hdiutil', ['verify', dmgPath], { timeout: 30_000 });
  if (!verify.ok) {
    throw new Error(verify.output || 'DMG verification failed');
  }

  let mountPoint = null;
  try {
    const attach = run('hdiutil', ['attach', '-plist', '-nobrowse', '-readonly', dmgPath], {
      timeout: 30_000
    });
    if (!attach.ok) {
      throw new Error(attach.output || 'DMG attach failed');
    }

    mountPoint = parseMountPoint(attach.output);
    if (!mountPoint) {
      throw new Error(`Could not find mounted volume in hdiutil output:\n${attach.output}`);
    }

    const mountedAppPath = path.join(mountPoint, 'BeatDropper.app');
    const executablePath = path.join(mountedAppPath, 'Contents', 'MacOS', 'BeatDropperNative');
    const infoPlistPath = path.join(mountedAppPath, 'Contents', 'Info.plist');
    const bundledNodeRuntimePath = path.join(mountedAppPath, 'Contents', 'Resources', 'Runtime', 'node');
    const thirdPartyNoticePath = path.join(mountedAppPath, 'Contents', 'Resources', 'ThirdParty', 'THIRD-PARTY-NOTICES.txt');
    const nodeLicensePath = path.join(mountedAppPath, 'Contents', 'Resources', 'ThirdParty', 'Node-LICENSE.txt');
    const applicationsLink = path.join(mountPoint, 'Applications');
    assertPath(mountedAppPath, 'mounted BeatDropper.app');
    assertPath(executablePath, 'mounted BeatDropperNative executable');
    assertPath(infoPlistPath, 'mounted Info.plist');
    assertPath(bundledNodeRuntimePath, 'mounted bundled Node runtime');
    assertPath(thirdPartyNoticePath, 'mounted third-party notices');
    assertPath(nodeLicensePath, 'mounted Node license');

    const applicationsStat = fs.lstatSync(applicationsLink);
    if (!applicationsStat.isSymbolicLink()) {
      throw new Error(`Applications shortcut is not a symlink: ${applicationsLink}`);
    }

    const plist = run('plutil', ['-lint', infoPlistPath], {
      timeout: 30_000
    });
    if (!plist.ok) {
      throw new Error(plist.output || 'mounted Info.plist validation failed');
    }

    const codesign = run('codesign', ['--verify', '--deep', '--strict', mountedAppPath], {
      timeout: 30_000
    });
    if (!codesign.ok) {
      throw new Error(codesign.output || 'mounted app codesign verification failed');
    }

    const bundledNode = run(bundledNodeRuntimePath, ['--version'], {
      timeout: 30_000
    });
    if (!bundledNode.ok) {
      throw new Error(bundledNode.output || 'mounted bundled Node runtime failed to execute');
    }

    const launched = runPersistentAppLaunch(executablePath);
    if (!launched.ok) {
      throw new Error(
        launched.output || `mounted native app exited before the ${launched.settleMs}ms launch window`
      );
    }

    process.stdout.write(
      [
        'BeatDropper native DMG smoke passed.',
        `mount ${mountPoint}`,
        'process active true',
        `launch window ms ${launched.settleMs}`
      ].join('\n') + '\n'
    );
  } finally {
    detach(mountPoint);
  }
};

try {
  main();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
