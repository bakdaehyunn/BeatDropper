#!/usr/bin/env node

const fs = require('node:fs');
const crypto = require('node:crypto');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const distDir = path.join(rootDir, 'native', 'dist');
const reportPath = path.join(distDir, 'release-smoke-report.json');
const appPath = path.join(distDir, 'BeatDropper.app');
const zipPath = path.join(distDir, 'BeatDropper.zip');
const dmgPath = path.join(distDir, 'BeatDropper.dmg');
const manifestPath = path.join(distDir, 'release-manifest.json');
const executablePath = path.join(appPath, 'Contents', 'MacOS', 'BeatDropperNative');
const infoPlistPath = path.join(appPath, 'Contents', 'Info.plist');
const plannerScriptPath = path.join(appPath, 'Contents', 'Resources', 'Scripts', 'codex-mix-planner.cjs');
const bundledNodeRuntimePath = path.join(appPath, 'Contents', 'Resources', 'Runtime', 'node');
const thirdPartyNoticePath = path.join(appPath, 'Contents', 'Resources', 'ThirdParty', 'THIRD-PARTY-NOTICES.txt');
const nodeLicensePath = path.join(appPath, 'Contents', 'Resources', 'ThirdParty', 'Node-LICENSE.txt');

const runCommand = (command, args, timeout = 20_000, options = {}) => {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8',
    timeout,
    ...options
  });
  return {
    ok: result.status === 0,
    status: result.status,
    signal: result.signal,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const run = (label, command, args, timeout = 20_000) => {
  const startedAt = Date.now();
  const result = runCommand(command, args, timeout);
  return {
    label,
    command: [command, ...args].join(' '),
    status: result.status,
    signal: result.signal,
    ok: result.status === 0,
    durationMs: Date.now() - startedAt,
    output: result.output
  };
};

const parseMountPoint = (plistOutput) => {
  const match = plistOutput.match(/<key>mount-point<\/key>\s*<string>([^<]+)<\/string>/);
  return match?.[1] || null;
};

const detach = (mountPoint) => {
  if (!mountPoint) {
    return;
  }
  const normal = runCommand('hdiutil', ['detach', mountPoint], 20_000);
  if (!normal.ok) {
    runCommand('hdiutil', ['detach', '-force', mountPoint], 20_000);
  }
};

const assertPath = (targetPath, label) => {
  if (!fs.existsSync(targetPath)) {
    throw new Error(`${label} missing: ${targetPath}`);
  }
};

const readJson = (filePath) => {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
};

const relative = (targetPath) => path.relative(rootDir, targetPath);

const hashFile = (filePath) => {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) {
    return null;
  }
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return {
    path: relative(filePath),
    sizeBytes: stat.size,
    sha256: hash.digest('hex'),
    modifiedAt: stat.mtime.toISOString()
  };
};

const buildArtifactSnapshot = () => ({
  app: {
    path: relative(appPath),
    executable: hashFile(executablePath),
    infoPlist: hashFile(infoPlistPath),
    bundledNodeRuntime: hashFile(bundledNodeRuntimePath),
    thirdPartyNotice: hashFile(thirdPartyNoticePath),
    nodeLicense: hashFile(nodeLicensePath),
    bundledPlannerScript: hashFile(plannerScriptPath)
  },
  zip: hashFile(zipPath),
  dmg: hashFile(dmgPath),
  manifest: hashFile(manifestPath)
});

const runInstalledAppSmoke = () => {
  const label = 'installed app smoke';
  const startedAt = Date.now();
  const output = [];
  let mountPoint = null;
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-install-smoke-'));

  const append = (result) => {
    if (result.output) {
      output.push(result.output);
    }
  };

  try {
    const verify = runCommand('hdiutil', ['verify', dmgPath], 30_000);
    append(verify);
    if (!verify.ok) {
      throw new Error(verify.output || 'DMG verification failed');
    }

    const attach = runCommand('hdiutil', ['attach', '-plist', '-nobrowse', '-readonly', dmgPath], 30_000);
    append(attach);
    if (!attach.ok) {
      throw new Error(attach.output || 'DMG attach failed');
    }

    mountPoint = parseMountPoint(attach.output);
    if (!mountPoint) {
      throw new Error(`Could not find mounted volume in hdiutil output:\n${attach.output}`);
    }

    const mountedAppPath = path.join(mountPoint, 'BeatDropper.app');
    const installedAppPath = path.join(tempDir, 'BeatDropper.app');
    const executablePath = path.join(installedAppPath, 'Contents', 'MacOS', 'BeatDropperNative');
    const infoPlistPath = path.join(installedAppPath, 'Contents', 'Info.plist');
    const thirdPartyNoticePath = path.join(installedAppPath, 'Contents', 'Resources', 'ThirdParty', 'THIRD-PARTY-NOTICES.txt');
    const nodeLicensePath = path.join(installedAppPath, 'Contents', 'Resources', 'ThirdParty', 'Node-LICENSE.txt');
    assertPath(mountedAppPath, 'mounted BeatDropper.app');

    const copy = runCommand('ditto', [mountedAppPath, installedAppPath], 45_000);
    append(copy);
    if (!copy.ok) {
      throw new Error(copy.output || 'installed app copy failed');
    }

    assertPath(installedAppPath, 'installed BeatDropper.app');
    assertPath(executablePath, 'installed BeatDropperNative executable');
    assertPath(infoPlistPath, 'installed Info.plist');
    assertPath(thirdPartyNoticePath, 'installed third-party notices');
    assertPath(nodeLicensePath, 'installed Node license');

    const plist = runCommand('plutil', ['-lint', infoPlistPath], 30_000);
    append(plist);
    if (!plist.ok) {
      throw new Error(plist.output || 'installed Info.plist validation failed');
    }

    const codesign = runCommand('codesign', ['--verify', '--deep', '--strict', installedAppPath], 30_000);
    append(codesign);
    if (!codesign.ok) {
      throw new Error(codesign.output || 'installed app codesign verification failed');
    }

    const launched = runCommand(executablePath, [], 10_000, {
      env: {
        ...process.env,
        BEATDROPPER_NATIVE_SMOKE: '1',
        BEATDROPPER_NATIVE_SMOKE_DELAY_MS: '900'
      }
    });
    append(launched);
    if (!launched.ok) {
      throw new Error(
        launched.output || `installed native app smoke failed with status ${launched.status ?? launched.signal}`
      );
    }

    const match = launched.output.match(/BEATDROPPER_NATIVE_SMOKE_READY visibleWindows=(\d+) keyWindow="([^"]*)"/);
    if (!match) {
      throw new Error(`installed app did not print smoke readiness marker. Output:\n${launched.output}`);
    }

    const visibleWindows = Number(match[1]);
    if (!Number.isFinite(visibleWindows) || visibleWindows < 1) {
      throw new Error(`installed app launched but no visible windows were reported. Output:\n${launched.output}`);
    }

    output.push(`BeatDropper native installed app smoke passed.`);
    output.push(`install ${installedAppPath}`);
    output.push(`visible windows ${visibleWindows}`);
    output.push(`key window ${match[2] || '--'}`);

    return {
      label,
      command: 'mount DMG, ditto BeatDropper.app to a temporary install path, launch copied app',
      status: 0,
      signal: null,
      ok: true,
      durationMs: Date.now() - startedAt,
      output: output.join('\n')
    };
  } catch (error) {
    output.push(error instanceof Error ? error.message : String(error));
    return {
      label,
      command: 'mount DMG, ditto BeatDropper.app to a temporary install path, launch copied app',
      status: 1,
      signal: null,
      ok: false,
      durationMs: Date.now() - startedAt,
      output: output.join('\n')
    };
  } finally {
    detach(mountPoint);
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
};

const parseSmokeEvidence = (output) => {
  const visibleWindowsMatch = output.match(/visible windows (\d+)/i);
  const keyWindowMatch = output.match(/key window (.+)$/im);
  const mountMatch = output.match(/^mount (.+)$/im);
  const installMatch = output.match(/^install (.+)$/im);

  return {
    visibleWindows: visibleWindowsMatch ? Number(visibleWindowsMatch[1]) : null,
    keyWindow: keyWindowMatch?.[1]?.trim() || null,
    mountPoint: mountMatch?.[1]?.trim() || null,
    installPath: installMatch?.[1]?.trim() || null,
    readinessMarkerSeen: /BeatDropper native .* smoke passed\./.test(output)
  };
};

const compactOutput = (output) => {
  const lines = output.split('\n').filter(Boolean);
  if (lines.length <= 10) {
    return lines;
  }
  return [...lines.slice(0, 5), '...', ...lines.slice(-5)];
};

const writeReport = (steps) => {
  fs.mkdirSync(distDir, { recursive: true });
  const failed = steps.filter((step) => !step.ok);
  const manifest = readJson(manifestPath);
  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    status: failed.length === 0 ? 'PASS' : 'FAIL',
    purpose: 'Post-release launch smoke evidence for the packaged app bundle, mounted DMG, and copied installed app.',
    releaseManifest: manifest
      ? {
          path: relative(manifestPath),
          generatedAt: manifest.generatedAt || null,
          packageVersion: manifest.packageVersion || null,
          releaseMode: manifest.releaseMode || null,
          source: manifest.source || null,
          signing: manifest.signing || null
        }
      : null,
    artifacts: {
      ...buildArtifactSnapshot()
    },
    steps: steps.map((step) => ({
      label: step.label,
      command: step.command,
      outcome: step.ok ? 'pass' : 'fail',
      status: step.status,
      signal: step.signal,
      durationMs: step.durationMs,
      evidence: parseSmokeEvidence(step.output),
      outputPreview: compactOutput(step.output)
    }))
  };

  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
};

const main = () => {
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    process.stdout.write(
      [
        'Usage: node scripts/smoke-native-release.cjs',
        '',
        'Runs packaged app smoke, mounted DMG smoke, and installed-app smoke, then writes native/dist/release-smoke-report.json.',
        'Run npm run native:package or npm run native:release first.',
        ''
      ].join('\n')
    );
    return;
  }

  const steps = [
    run('packaged app smoke', 'node', ['scripts/smoke-native-app.cjs'], 12_000),
    run('mounted DMG smoke', 'node', ['scripts/smoke-native-dmg.cjs'], 20_000),
    runInstalledAppSmoke()
  ];
  const report = writeReport(steps);

  process.stdout.write(
    [
      '# Native Release Smoke',
      `status ${report.status}`,
      `steps ${report.steps.length}`,
      `report ${path.relative(rootDir, reportPath)}`,
      ''
    ].join('\n')
  );

  for (const step of report.steps) {
    const windows = step.evidence.visibleWindows ?? '--';
    const mount = step.evidence.mountPoint ? ` mount=${step.evidence.mountPoint}` : '';
    const install = step.evidence.installPath ? ` install=${step.evidence.installPath}` : '';
    process.stdout.write(`- ${step.outcome.toUpperCase()} ${step.label}: visibleWindows=${windows}${mount}${install}\n`);
  }

  if (report.status !== 'PASS') {
    process.exitCode = 1;
  }
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
