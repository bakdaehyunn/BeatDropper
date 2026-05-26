#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const distDir = path.join(rootDir, 'native', 'dist');
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
const notaryEvidenceDir = path.join(distDir, 'notary-logs');
const zipNotarySubmitPath = path.join(notaryEvidenceDir, 'zip-submit.json');
const zipNotaryLogPath = path.join(notaryEvidenceDir, 'zip-log.json');
const dmgNotarySubmitPath = path.join(notaryEvidenceDir, 'dmg-submit.json');
const dmgNotaryLogPath = path.join(notaryEvidenceDir, 'dmg-log.json');

const relative = (targetPath) => path.relative(rootDir, targetPath);

const run = (command, args) => {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8'
  });
  return {
    ok: result.status === 0,
    status: result.status,
    signal: result.signal,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const hashFile = (filePath) => {
  const hash = crypto.createHash('sha256');
  const data = fs.readFileSync(filePath);
  hash.update(data);
  return hash.digest('hex');
};

const readJson = (filePath) => {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
};

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const decodeXmlText = (value) =>
  value
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');

const readPlistString = (filePath, key) => {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const source = fs.readFileSync(filePath, 'utf8');
  const pattern = new RegExp(
    `<key>\\s*${escapeRegExp(key)}\\s*<\\/key>\\s*<string>([^<]*)<\\/string>`
  );
  return decodeXmlText(source.match(pattern)?.[1] || '') || null;
};

const fileInfo = (filePath) => {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const stat = fs.statSync(filePath);
  if (!stat.isFile()) {
    return null;
  }

  return {
    path: relative(filePath),
    sizeBytes: stat.size,
    sha256: hashFile(filePath),
    modifiedAt: stat.mtime.toISOString()
  };
};

const directorySize = (dirPath) => {
  if (!fs.existsSync(dirPath)) {
    return 0;
  }

  let total = 0;
  const stack = [dirPath];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(entryPath);
        continue;
      }
      if (entry.isFile()) {
        total += fs.statSync(entryPath).size;
      }
    }
  }
  return total;
};

const parseCodesignDetails = (output) => {
  const lines = output.split('\n').map((line) => line.trim()).filter(Boolean);
  const authorities = [];
  const details = {};

  for (const line of lines) {
    if (line.startsWith('Authority=')) {
      authorities.push(line.slice('Authority='.length));
      continue;
    }

    const index = line.indexOf('=');
    if (index > 0) {
      details[line.slice(0, index)] = line.slice(index + 1);
    }
  }

  return {
    signature: details.Signature || null,
    teamIdentifier: details.TeamIdentifier || null,
    runtimeVersion: details.RuntimeVersion || null,
    sealedResourcesVersion: details.SealedResources || null,
    authorities,
    isAdHoc: details.Signature === 'adhoc',
    hasDeveloperIdApplication: authorities.some((authority) =>
      authority.startsWith('Developer ID Application:')
    )
  };
};

const loadPackageVersion = () => {
  const packagePath = path.join(rootDir, 'package.json');
  if (!fs.existsSync(packagePath)) {
    return null;
  }

  return JSON.parse(fs.readFileSync(packagePath, 'utf8')).version || null;
};

const nonEmptyLines = (value) => value.split('\n').map((line) => line.trim()).filter(Boolean);

const buildGitProvenance = () => {
  const insideWorkTree = run('git', ['rev-parse', '--is-inside-work-tree']);
  if (!insideWorkTree.ok || insideWorkTree.output !== 'true') {
    return {
      available: false,
      commit: null,
      shortCommit: null,
      branch: null,
      exactTag: null,
      commitTime: null,
      isDirty: null,
      statusEntryCount: null,
      statusPreview: [],
      error: insideWorkTree.output || 'not a git work tree'
    };
  }

  const commit = run('git', ['rev-parse', 'HEAD']);
  const shortCommit = run('git', ['rev-parse', '--short=12', 'HEAD']);
  const branch = run('git', ['rev-parse', '--abbrev-ref', 'HEAD']);
  const exactTag = run('git', ['describe', '--tags', '--exact-match', 'HEAD']);
  const commitTime = run('git', ['show', '-s', '--format=%cI', 'HEAD']);
  const status = run('git', ['status', '--short', '--untracked-files=all']);
  const statusEntries = status.ok ? nonEmptyLines(status.output) : [];

  return {
    available: true,
    commit: commit.ok ? commit.output : null,
    shortCommit: shortCommit.ok ? shortCommit.output : null,
    branch: branch.ok ? branch.output : null,
    exactTag: exactTag.ok ? exactTag.output : null,
    commitTime: commitTime.ok ? commitTime.output : null,
    isDirty: status.ok ? statusEntries.length > 0 : null,
    statusEntryCount: status.ok ? statusEntries.length : null,
    statusPreview: statusEntries.slice(0, 50)
  };
};

const buildEnvironmentProvenance = () => ({
  nodeVersion: process.version,
  xcodebuildVersion: run('xcodebuild', ['-version']).output || null,
  swiftVersion: run('swift', ['--version']).output || null,
  macOSVersion: run('sw_vers', ['-productVersion']).output || null,
  architecture: run('uname', ['-m']).output || null
});

const notarySummary = (submitPath, logPath) => {
  const submit = readJson(submitPath);
  const log = readJson(logPath);
  return {
    submit: submit
      ? {
          id: submit.id || submit.submissionId || null,
          status: submit.status || null,
          message: submit.message || null
        }
      : null,
    log: log
      ? {
          statusSummary: log.statusSummary || null,
          issuesCount: Array.isArray(log.issues) ? log.issues.length : null,
          errorIssuesCount: Array.isArray(log.issues)
            ? log.issues.filter((issue) => issue.severity === 'error').length
            : null
        }
      : null
  };
};

const main = () => {
  fs.mkdirSync(distDir, { recursive: true });

  const signIdentity = process.env.SIGN_IDENTITY || '-';
  const notarizeRequested = process.env.NOTARIZE === '1';
  const appExists = fs.existsSync(appPath);
  const zipExists = fs.existsSync(zipPath);
  const dmgExists = fs.existsSync(dmgPath);
  const packageVersion = loadPackageVersion();
  const infoPlistMetadata = appExists
    ? {
        bundleIdentifier: readPlistString(infoPlistPath, 'CFBundleIdentifier'),
        shortVersion: readPlistString(infoPlistPath, 'CFBundleShortVersionString'),
        bundleVersion: readPlistString(infoPlistPath, 'CFBundleVersion')
      }
    : null;

  const plist = appExists ? run('plutil', ['-lint', infoPlistPath]) : null;
  const codesignVerify = appExists ? run('codesign', ['--verify', '--deep', '--strict', appPath]) : null;
  const codesignDetails = appExists ? run('codesign', ['-dv', '--verbose=4', appPath]) : null;
  const gatekeeperApp = appExists
    ? run('spctl', ['--assess', '--type', 'execute', '--verbose', appPath])
    : null;
  const dmgVerify = dmgExists ? run('hdiutil', ['verify', dmgPath]) : null;
  const dmgCodesignDetails = dmgExists ? run('codesign', ['-dv', '--verbose=4', dmgPath]) : null;

  const appSignature = codesignDetails ? parseCodesignDetails(codesignDetails.output) : null;
  const dmgSignature = dmgCodesignDetails?.ok
    ? parseCodesignDetails(dmgCodesignDetails.output)
    : null;

  const manifest = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    product: 'BeatDropper',
    packageVersion,
    releaseMode: appSignature?.hasDeveloperIdApplication ? 'developer-id' : 'ad-hoc',
    source: {
      git: buildGitProvenance(),
      environment: buildEnvironmentProvenance()
    },
    signing: {
      requestedIdentity: signIdentity,
      notarizeRequested
    },
    artifacts: {
      app: appExists
        ? {
            path: relative(appPath),
            sizeBytes: directorySize(appPath),
            executable: fileInfo(executablePath),
            infoPlist: fileInfo(infoPlistPath),
            infoPlistMetadata,
            bundledNodeRuntime: fileInfo(bundledNodeRuntimePath),
            thirdPartyNotice: fileInfo(thirdPartyNoticePath),
            nodeLicense: fileInfo(nodeLicensePath),
            bundledPlannerScript: fileInfo(plannerScriptPath)
          }
        : null,
      zip: fileInfo(zipPath),
      dmg: fileInfo(dmgPath),
      notaryEvidence: {
        zipSubmit: fileInfo(zipNotarySubmitPath),
        zipLog: fileInfo(zipNotaryLogPath),
        dmgSubmit: fileInfo(dmgNotarySubmitPath),
        dmgLog: fileInfo(dmgNotaryLogPath)
      },
      manifest: {
        path: relative(manifestPath)
      }
    },
    verification: {
      infoPlist: plist,
      appCodesign: codesignVerify,
      appSignature,
      appGatekeeper: gatekeeperApp,
      dmgVerify,
      dmgSignature,
      notaryEvidence: {
        zip: notarySummary(zipNotarySubmitPath, zipNotaryLogPath),
        dmg: notarySummary(dmgNotarySubmitPath, dmgNotaryLogPath)
      }
    }
  };

  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const failures = [];
  if (!appExists) failures.push('missing native/dist/BeatDropper.app');
  if (!zipExists) failures.push('missing native/dist/BeatDropper.zip');
  if (!dmgExists) failures.push('missing native/dist/BeatDropper.dmg');
  if (!manifest.artifacts.app?.executable) failures.push('missing app executable');
  if (!manifest.artifacts.app?.infoPlist) failures.push('missing app Info.plist');
  if (!manifest.artifacts.app?.bundledNodeRuntime) failures.push('missing bundled Node runtime');
  if (!manifest.artifacts.app?.thirdPartyNotice) failures.push('missing third-party notice file');
  if (!manifest.artifacts.app?.nodeLicense) failures.push('missing Node license file');
  if (!manifest.artifacts.app?.bundledPlannerScript) failures.push('missing bundled planner script');
  if (packageVersion && infoPlistMetadata?.shortVersion !== packageVersion) {
    failures.push(
      `Info.plist CFBundleShortVersionString ${infoPlistMetadata?.shortVersion || 'missing'} does not match package.json version ${packageVersion}`
    );
  }
  if (!infoPlistMetadata?.bundleVersion) failures.push('missing Info.plist CFBundleVersion');
  if (plist && !plist.ok) failures.push('Info.plist validation failed');
  if (codesignVerify && !codesignVerify.ok) failures.push('app codesign verification failed');
  if (dmgVerify && !dmgVerify.ok) failures.push('DMG verification failed');

  process.stdout.write(
    [
      'BeatDropper native release manifest written.',
      `manifest ${relative(manifestPath)}`,
      `release mode ${manifest.releaseMode}`,
      `app codesign ${codesignVerify?.ok ? 'pass' : 'blocked'}`,
      `Gatekeeper ${gatekeeperApp?.ok ? 'accepted' : 'not accepted'}`,
      `DMG verify ${dmgVerify?.ok ? 'pass' : 'blocked'}`
    ].join('\n') + '\n'
  );

  if (failures.length > 0) {
    process.stderr.write(`Release manifest blockers:\n- ${failures.join('\n- ')}\n`);
    process.exitCode = 1;
  }
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
