#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
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

const reportPathForOptions = (options) =>
  path.join(
    distDir,
    options.allowAdHoc
      ? 'local-release-verification-report.json'
      : 'release-verification-report.json'
  );

const parseArgs = (argv) => {
  const options = {
    allowAdHoc: false,
    reportOnly: false
  };

  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') {
      process.stdout.write(
        [
          'Usage: node scripts/verify-native-release.cjs [options]',
          '',
          'Options:',
          '  --allow-ad-hoc  Treat Developer ID, notarization, and Gatekeeper misses as warnings for local package QA.',
          '  --report-only   Print the report but exit 0 even when blockers remain.',
          '  --help          Show this message.',
          ''
        ].join('\n')
      );
      process.exit(0);
    }
    if (arg === '--allow-ad-hoc') {
      options.allowAdHoc = true;
      continue;
    }
    if (arg === '--report-only') {
      options.reportOnly = true;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
};

const relative = (targetPath) => path.relative(rootDir, targetPath);

const run = (command, args, timeout = 20_000) => {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8',
    timeout
  });
  return {
    ok: result.status === 0,
    status: result.status,
    signal: result.signal,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const readJson = (filePath) => {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
};

const loadPackageVersion = () => {
  const packageJson = readJson(path.join(rootDir, 'package.json'));
  return packageJson?.version || null;
};

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const decodeXmlText = (value) =>
  value
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');

const plistStringValue = (plistSource, key) => {
  const pattern = new RegExp(
    `<key>\\s*${escapeRegExp(key)}\\s*<\\/key>\\s*<string>([^<]*)<\\/string>`
  );
  return decodeXmlText(plistSource.match(pattern)?.[1] || '') || null;
};

const isValidBundleVersion = (value) => /^[0-9]+([.][0-9]+){0,2}$/.test(value || '');

const packageVersion = loadPackageVersion();

const hashFile = (filePath) => {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
};

const fileSnapshot = (filePath) => {
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

const currentGitProvenance = () => {
  const insideWorkTree = run('git', ['rev-parse', '--is-inside-work-tree'], 30_000);
  if (!insideWorkTree.ok || insideWorkTree.output !== 'true') {
    return {
      available: false,
      commit: null,
      shortCommit: null,
      isDirty: null,
      statusEntryCount: null
    };
  }

  const commit = run('git', ['rev-parse', 'HEAD'], 30_000);
  const shortCommit = run('git', ['rev-parse', '--short=12', 'HEAD'], 30_000);
  const status = run('git', ['status', '--short', '--untracked-files=all'], 30_000);
  const statusEntries = status.ok
    ? status.output.split('\n').map((line) => line.trim()).filter(Boolean)
    : [];

  return {
    available: true,
    commit: commit.ok ? commit.output : null,
    shortCommit: shortCommit.ok ? shortCommit.output : null,
    isDirty: status.ok ? statusEntries.length > 0 : null,
    statusEntryCount: status.ok ? statusEntries.length : null
  };
};

const manifestHasSourceProvenance = (manifest) =>
  /^[a-f0-9]{40}$/i.test(manifest?.source?.git?.commit || '') &&
  typeof manifest?.source?.git?.shortCommit === 'string' &&
  typeof manifest?.source?.git?.isDirty === 'boolean' &&
  Number.isInteger(manifest?.source?.git?.statusEntryCount);

const manifestHasBuildEnvironmentProvenance = (manifest) =>
  Boolean(
    manifest?.source?.environment?.nodeVersion &&
      manifest?.source?.environment?.xcodebuildVersion &&
      manifest?.source?.environment?.swiftVersion &&
      manifest?.source?.environment?.macOSVersion &&
      manifest?.source?.environment?.architecture
  );

const parseCodesignDetails = (output) => {
  const authorities = [];
  const details = {};
  for (const rawLine of output.split('\n')) {
    const line = rawLine.trim();
    if (!line) continue;
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
    authorities,
    isAdHoc: details.Signature === 'adhoc',
    hasDeveloperIdApplication: authorities.some((authority) =>
      authority.startsWith('Developer ID Application:')
    ),
    hasDeveloperIdCertificationAuthority: authorities.some((authority) =>
      authority === 'Developer ID Certification Authority'
    ),
    hasAppleRoot: authorities.some((authority) => authority === 'Apple Root CA'),
    hasHardenedRuntime: /flags=.*runtime/.test(output)
  };
};

const createReporter = (options) => {
  const checks = [];

  const add = (name, status, detail) => {
    checks.push({ name, status, detail });
  };

  const addRequired = (name, passed, passDetail, failDetail) => {
    add(name, passed ? 'pass' : 'blocked', passed ? passDetail : failDetail);
  };

  const addReleaseRequired = (name, passed, passDetail, failDetail) => {
    add(
      name,
      passed ? 'pass' : options.allowAdHoc ? 'warn' : 'blocked',
      passed ? passDetail : failDetail
    );
  };

  return { checks, add, addRequired, addReleaseRequired };
};

const verifyHash = (reporter, label, artifact, filePath) => {
  if (!artifact?.sha256) {
    reporter.addRequired(label, false, '', 'manifest does not record a SHA-256 checksum');
    return;
  }
  if (!fs.existsSync(filePath)) {
    reporter.addRequired(label, false, '', `${relative(filePath)} is missing`);
    return;
  }

  const actual = hashFile(filePath);
  reporter.addRequired(
    label,
    actual === artifact.sha256,
    `${relative(filePath)} matches manifest SHA-256`,
    `${relative(filePath)} SHA-256 mismatch: expected ${artifact.sha256}, actual ${actual}`
  );
};

const verifyReleaseHash = (reporter, label, artifact, filePath) => {
  if (!artifact?.sha256) {
    reporter.addReleaseRequired(label, false, '', 'manifest does not record a SHA-256 checksum');
    return;
  }
  if (!fs.existsSync(filePath)) {
    reporter.addReleaseRequired(label, false, '', `${relative(filePath)} is missing`);
    return;
  }

  const actual = hashFile(filePath);
  reporter.addReleaseRequired(
    label,
    actual === artifact.sha256,
    `${relative(filePath)} matches manifest SHA-256`,
    `${relative(filePath)} SHA-256 mismatch: expected ${artifact.sha256}, actual ${actual}`
  );
};

const describeNotarySubmit = (submit) => {
  if (!submit) {
    return 'notary submit JSON is missing or invalid';
  }
  const submissionId = submit.id || submit.submissionId || 'missing id';
  return `submission ${submissionId}, status ${submit.status || 'missing status'}`;
};

const hasAcceptedNotarySubmit = (submit) =>
  Boolean((submit?.id || submit?.submissionId) && submit.status === 'Accepted');

const notaryLogErrorCount = (log) => {
  if (!log || !Array.isArray(log.issues)) {
    return null;
  }
  return log.issues.filter((issue) => issue.severity === 'error').length;
};

const addNotaryEvidenceChecks = (reporter, label, submitPath, logPath) => {
  const submit = readJson(submitPath);
  const log = readJson(logPath);
  const errorCount = notaryLogErrorCount(log);
  const logHasNoErrors = Boolean(log && (errorCount === null || errorCount === 0));

  reporter.addReleaseRequired(
    `${label} notary submission evidence`,
    hasAcceptedNotarySubmit(submit),
    `${relative(submitPath)} records an accepted notary submission`,
    describeNotarySubmit(submit)
  );
  reporter.addReleaseRequired(
    `${label} notary log evidence`,
    logHasNoErrors,
    `${relative(logPath)} records no notary error issues`,
    log
      ? `${relative(logPath)} reports ${errorCount ?? 'unknown'} notary error issues`
      : `${relative(logPath)} is missing or invalid`
  );
};

const parseMountPoint = (plistOutput) => {
  const match = plistOutput.match(/<key>mount-point<\/key>\s*<string>([^<]+)<\/string>/);
  return match?.[1] || null;
};

const infoPlistDeclaresFinderOpenTypes = (plistSource) =>
  /<key>CFBundleDocumentTypes<\/key>/.test(plistSource) &&
  /<string>public\.audio<\/string>/.test(plistSource) &&
  /<string>public\.mp3<\/string>/.test(plistSource) &&
  /<string>com\.microsoft\.waveform-audio<\/string>/.test(plistSource) &&
  /<string>public\.folder<\/string>/.test(plistSource);

const addInfoPlistPackageVersionCheck = (reporter, name, plistSource, missingDetail) => {
  const shortVersion = plistStringValue(plistSource, 'CFBundleShortVersionString');
  const bundleVersion = plistStringValue(plistSource, 'CFBundleVersion');
  const passed =
    Boolean(packageVersion) &&
    shortVersion === packageVersion &&
    isValidBundleVersion(bundleVersion);

  reporter.addRequired(
    name,
    passed,
    `CFBundleShortVersionString ${shortVersion} matches package.json and CFBundleVersion ${bundleVersion} is valid`,
    missingDetail ||
      `expected CFBundleShortVersionString ${packageVersion || 'missing package version'} and numeric CFBundleVersion, found short version ${shortVersion || 'missing'} and bundle version ${bundleVersion || 'missing'}`
  );
};

const addBundledNodeRuntimeCheck = (reporter, name, nodePath) => {
  if (!fs.existsSync(nodePath)) {
    reporter.addRequired(name, false, '', `${relative(nodePath)} is missing`);
    return;
  }
  const executable = fs.statSync(nodePath).mode & 0o111;
  if (!executable) {
    reporter.addRequired(name, false, '', `${relative(nodePath)} is not executable`);
    return;
  }

  const version = run(nodePath, ['--version'], 30_000);
  reporter.addRequired(
    name,
    version.ok,
    `bundled Node runtime is executable: ${version.output}`,
    version.output || 'bundled Node runtime failed to run'
  );
};

const addBundledNodeCodesignCheck = (reporter, name, nodePath) => {
  if (!fs.existsSync(nodePath)) {
    reporter.addRequired(name, false, '', `${relative(nodePath)} is missing`);
    return;
  }

  const verify = run('codesign', ['--verify', '--strict', nodePath], 30_000);
  reporter.addRequired(
    name,
    verify.ok,
    `codesign verifies ${relative(nodePath)}`,
    verify.output || `codesign verification failed for ${relative(nodePath)}`
  );
};

const parseOtoolLibraries = (output) =>
  output
    .split('\n')
    .slice(1)
    .map((line) => line.trim().split(/\s+\(/)[0])
    .filter(Boolean);

const hasOnlySystemLinkedLibraries = (libraries) =>
  libraries.length > 0 &&
  libraries.every((library) =>
    library.startsWith('/System/Library/') ||
    library.startsWith('/usr/lib/') ||
    library.startsWith('@rpath/') ||
    library.startsWith('@loader_path/') ||
    library.startsWith('@executable_path/')
  );

const addBundledNodeDependencyCheck = (reporter, name, nodePath) => {
  if (!fs.existsSync(nodePath)) {
    reporter.addRequired(name, false, '', `${relative(nodePath)} is missing`);
    return;
  }

  const linked = run('otool', ['-L', nodePath], 30_000);
  const libraries = linked.ok ? parseOtoolLibraries(linked.output) : [];
  reporter.addRequired(
    name,
    linked.ok && hasOnlySystemLinkedLibraries(libraries),
    `bundled Node links only system or relative libraries (${libraries.length} libraries)`,
    linked.ok
      ? `bundled Node has non-system absolute dependencies: ${libraries.join(', ')}`
      : linked.output || 'could not inspect bundled Node linked libraries'
  );
};

const quarantineAttributeValue = () =>
  `0083;${Math.floor(Date.now() / 1000).toString(16)};BeatDropper;https://beatdropper.local/release-check`;

const addQuarantinedAppGatekeeperCheck = (reporter, name, appBundlePath) => {
  if (!fs.existsSync(appBundlePath)) {
    reporter.addReleaseRequired(name, false, '', `${relative(appBundlePath)} is missing`);
    return;
  }

  const quarantine = run(
    'xattr',
    ['-w', 'com.apple.quarantine', quarantineAttributeValue(), appBundlePath],
    30_000
  );
  if (!quarantine.ok) {
    reporter.addReleaseRequired(
      name,
      false,
      '',
      quarantine.output || `could not write quarantine attribute to ${relative(appBundlePath)}`
    );
    return;
  }

  const gatekeeper = run(
    'spctl',
    ['--assess', '--type', 'execute', '--verbose', appBundlePath],
    30_000
  );
  reporter.addReleaseRequired(
    name,
    gatekeeper.ok,
    `spctl accepts quarantined app ${relative(appBundlePath)}`,
    gatekeeper.output || `Gatekeeper rejected quarantined app ${relative(appBundlePath)}`
  );
};

const addQuarantinedAppCopyGatekeeperCheck = (reporter, name, sourceAppPath) => {
  if (!fs.existsSync(sourceAppPath)) {
    reporter.addReleaseRequired(name, false, '', `${relative(sourceAppPath)} is missing`);
    return;
  }

  let tempDir = null;
  try {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-quarantine-app-'));
    const copiedAppPath = path.join(tempDir, 'BeatDropper.app');
    const copy = run('ditto', [sourceAppPath, copiedAppPath], 60_000);
    if (!copy.ok || !fs.existsSync(copiedAppPath)) {
      reporter.addReleaseRequired(
        name,
        false,
        '',
        copy.output || `could not copy ${relative(sourceAppPath)} for quarantine assessment`
      );
      return;
    }

    addQuarantinedAppGatekeeperCheck(reporter, name, copiedAppPath);
  } finally {
    if (tempDir) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  }
};

const addQuarantinedDmgGatekeeperCheck = (reporter) => {
  if (!fs.existsSync(dmgPath)) {
    reporter.addReleaseRequired(
      'DMG quarantined Gatekeeper assessment',
      false,
      '',
      `${relative(dmgPath)} is missing`
    );
    return;
  }

  let tempDir = null;
  try {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-quarantine-dmg-'));
    const copiedDmgPath = path.join(tempDir, 'BeatDropper.dmg');
    fs.copyFileSync(dmgPath, copiedDmgPath);

    const quarantine = run(
      'xattr',
      ['-w', 'com.apple.quarantine', quarantineAttributeValue(), copiedDmgPath],
      30_000
    );
    if (!quarantine.ok) {
      reporter.addReleaseRequired(
        'DMG quarantined Gatekeeper assessment',
        false,
        '',
        quarantine.output || `could not write quarantine attribute to ${relative(copiedDmgPath)}`
      );
      return;
    }

    const gatekeeper = run(
      'spctl',
      ['--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose', copiedDmgPath],
      30_000
    );
    reporter.addReleaseRequired(
      'DMG quarantined Gatekeeper assessment',
      gatekeeper.ok,
      'spctl accepts a quarantined copy of the DMG',
      gatekeeper.output || 'Gatekeeper rejected a quarantined copy of the DMG'
    );
  } finally {
    if (tempDir) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  }
};

const thirdPartyNoticeMentionsNode = (noticeSource) =>
  /Node\.js runtime/.test(noticeSource) &&
  /Version: v?[0-9]+/.test(noticeSource) &&
  /Contents\/Resources\/Runtime\/node/.test(noticeSource) &&
  /Contents\/Resources\/ThirdParty\/Node-LICENSE\.txt/.test(noticeSource);

const nodeLicenseLooksValid = (licenseSource) =>
  /Node\.js/.test(licenseSource) &&
  /MIT License/.test(licenseSource);

const addThirdPartyNoticeChecks = (reporter, labelPrefix, noticePath, licensePath) => {
  const noticeExists = fs.existsSync(noticePath);
  const licenseExists = fs.existsSync(licensePath);
  const noticeSource = noticeExists ? fs.readFileSync(noticePath, 'utf8') : '';
  const licenseSource = licenseExists ? fs.readFileSync(licensePath, 'utf8') : '';

  reporter.addRequired(
    `${labelPrefix} third-party notice`,
    noticeExists && thirdPartyNoticeMentionsNode(noticeSource),
    `${relative(noticePath)} documents the bundled Node runtime`,
    noticeExists
      ? `${relative(noticePath)} does not mention the bundled Node runtime and license path`
      : `${relative(noticePath)} is missing`
  );
  reporter.addRequired(
    `${labelPrefix} Node license`,
    licenseExists && nodeLicenseLooksValid(licenseSource),
    `${relative(licensePath)} contains the Node.js license`,
    licenseExists
      ? `${relative(licensePath)} does not look like the Node.js MIT license`
      : `${relative(licensePath)} is missing`
  );
};

const detachDmg = (mountPoint) => {
  if (!mountPoint) {
    return;
  }

  const normal = run('hdiutil', ['detach', mountPoint], 30_000);
  if (!normal.ok) {
    run('hdiutil', ['detach', '-force', mountPoint], 30_000);
  }
};

const addInstalledAppSkippedChecks = (reporter, detail) => {
  reporter.addRequired('installed Info.plist validation', false, '', detail);
  reporter.addRequired('installed Finder-open document types', false, '', detail);
  reporter.addRequired('installed Info.plist package version', false, '', detail);
  reporter.addRequired('installed bundled Node runtime', false, '', detail);
  reporter.addRequired('installed bundled Node codesign', false, '', detail);
  reporter.addRequired('installed bundled Node dependencies', false, '', detail);
  reporter.addRequired('installed third-party notice', false, '', detail);
  reporter.addRequired('installed Node license', false, '', detail);
  reporter.addRequired('installed app codesign verification', false, '', detail);
  reporter.addReleaseRequired('installed app Gatekeeper assessment', false, '', detail);
  reporter.addReleaseRequired('installed quarantined app Gatekeeper assessment', false, '', detail);
};

const addZipAppSkippedChecks = (reporter, detail) => {
  reporter.addRequired('zip app Info.plist validation', false, '', detail);
  reporter.addRequired('zip app Finder-open document types', false, '', detail);
  reporter.addRequired('zip app Info.plist package version', false, '', detail);
  reporter.addRequired('zip app bundled Node runtime', false, '', detail);
  reporter.addRequired('zip app bundled Node codesign', false, '', detail);
  reporter.addRequired('zip app bundled Node dependencies', false, '', detail);
  reporter.addRequired('zip app third-party notice', false, '', detail);
  reporter.addRequired('zip app Node license', false, '', detail);
  reporter.addRequired('zip app codesign verification', false, '', detail);
  reporter.addReleaseRequired('zip app notarization ticket', false, '', detail);
  reporter.addReleaseRequired('zip app Gatekeeper assessment', false, '', detail);
  reporter.addReleaseRequired('zip app quarantined Gatekeeper assessment', false, '', detail);
};

const verifyZipAppFromArchive = (reporter) => {
  if (!fs.existsSync(zipPath)) {
    const detail = `${relative(zipPath)} is missing`;
    reporter.addRequired('zip app extraction', false, '', detail);
    addZipAppSkippedChecks(reporter, detail);
    return;
  }

  let tempDir = null;
  try {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-zip-app-'));
    const extract = run('ditto', ['-x', '-k', zipPath, tempDir], 60_000);
    const zipAppPath = path.join(tempDir, 'BeatDropper.app');
    const extracted = extract.ok && fs.existsSync(zipAppPath);
    reporter.addRequired(
      'zip app extraction',
      extracted,
      'extracted BeatDropper.app from the ZIP artifact',
      extract.output || 'could not extract BeatDropper.app from the ZIP artifact'
    );
    if (!extracted) {
      addZipAppSkippedChecks(reporter, 'BeatDropper.app was not extracted from the ZIP artifact');
      return;
    }

    const zipInfoPlistPath = path.join(zipAppPath, 'Contents', 'Info.plist');
    const zipInfoExists = fs.existsSync(zipInfoPlistPath);
    const zipPlist = zipInfoExists ? run('plutil', ['-lint', zipInfoPlistPath], 30_000) : null;
    reporter.addRequired(
      'zip app Info.plist validation',
      zipPlist?.ok === true,
      'ZIP app Info.plist validates',
      zipInfoExists ? zipPlist?.output || 'ZIP app Info.plist validation failed' : 'ZIP app Info.plist is missing'
    );
    const zipInfoSource = zipInfoExists ? fs.readFileSync(zipInfoPlistPath, 'utf8') : '';
    reporter.addRequired(
      'zip app Finder-open document types',
      infoPlistDeclaresFinderOpenTypes(zipInfoSource),
      'ZIP app Info.plist declares audio and folder document types',
      zipInfoExists
        ? 'ZIP app Info.plist lacks public.audio/public.mp3/WAV/folder document types'
        : 'ZIP app Info.plist is missing'
    );
    addInfoPlistPackageVersionCheck(
      reporter,
      'zip app Info.plist package version',
      zipInfoSource,
      zipInfoExists ? null : 'ZIP app Info.plist is missing'
    );
    addBundledNodeRuntimeCheck(
      reporter,
      'zip app bundled Node runtime',
      path.join(zipAppPath, 'Contents', 'Resources', 'Runtime', 'node')
    );
    addBundledNodeCodesignCheck(
      reporter,
      'zip app bundled Node codesign',
      path.join(zipAppPath, 'Contents', 'Resources', 'Runtime', 'node')
    );
    addBundledNodeDependencyCheck(
      reporter,
      'zip app bundled Node dependencies',
      path.join(zipAppPath, 'Contents', 'Resources', 'Runtime', 'node')
    );
    addThirdPartyNoticeChecks(
      reporter,
      'zip app',
      path.join(zipAppPath, 'Contents', 'Resources', 'ThirdParty', 'THIRD-PARTY-NOTICES.txt'),
      path.join(zipAppPath, 'Contents', 'Resources', 'ThirdParty', 'Node-LICENSE.txt')
    );

    const zipCodesign = run('codesign', ['--verify', '--deep', '--strict', zipAppPath], 30_000);
    reporter.addRequired(
      'zip app codesign verification',
      zipCodesign.ok,
      'ZIP app codesign verification passed',
      zipCodesign.output || 'ZIP app codesign verification failed'
    );

    const zipStapler = run('xcrun', ['stapler', 'validate', zipAppPath], 30_000);
    reporter.addReleaseRequired(
      'zip app notarization ticket',
      zipStapler.ok,
      'stapler validates the ZIP app notarization ticket',
      zipStapler.output || 'ZIP app notarization ticket validation failed'
    );

    const zipGatekeeper = run(
      'spctl',
      ['--assess', '--type', 'execute', '--verbose', zipAppPath],
      30_000
    );
    reporter.addReleaseRequired(
      'zip app Gatekeeper assessment',
      zipGatekeeper.ok,
      'spctl accepts the ZIP app',
      zipGatekeeper.output || 'ZIP app Gatekeeper assessment failed'
    );
    addQuarantinedAppGatekeeperCheck(
      reporter,
      'zip app quarantined Gatekeeper assessment',
      zipAppPath
    );
  } finally {
    if (tempDir) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  }
};

const verifyInstalledAppFromDmg = (reporter) => {
  if (!fs.existsSync(dmgPath)) {
    const detail = `${relative(dmgPath)} is missing`;
    reporter.addRequired('installed app copy', false, '', detail);
    addInstalledAppSkippedChecks(reporter, detail);
    return;
  }

  let mountPoint = null;
  let tempDir = null;
  try {
    const attach = run('hdiutil', ['attach', '-plist', '-nobrowse', '-readonly', dmgPath], 30_000);
    if (!attach.ok) {
      const detail = attach.output || 'DMG attach failed';
      reporter.addRequired('installed app copy', false, '', detail);
      addInstalledAppSkippedChecks(reporter, detail);
      return;
    }

    mountPoint = parseMountPoint(attach.output);
    if (!mountPoint) {
      const detail = `Could not find mounted volume in hdiutil output:\n${attach.output}`;
      reporter.addRequired('installed app copy', false, '', detail);
      addInstalledAppSkippedChecks(reporter, detail);
      return;
    }

    const mountedAppPath = path.join(mountPoint, 'BeatDropper.app');
    if (!fs.existsSync(mountedAppPath)) {
      const detail = `mounted BeatDropper.app missing: ${mountedAppPath}`;
      reporter.addRequired('installed app copy', false, '', detail);
      addInstalledAppSkippedChecks(reporter, detail);
      return;
    }

    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-installed-app-'));
    const installedAppPath = path.join(tempDir, 'BeatDropper.app');
    const copy = run('ditto', [mountedAppPath, installedAppPath], 60_000);
    const copied = copy.ok && fs.existsSync(installedAppPath);
    reporter.addRequired(
      'installed app copy',
      copied,
      'copied mounted DMG app to a temporary install location',
      copy.output || 'ditto copy from mounted DMG failed'
    );
    if (!copied) {
      addInstalledAppSkippedChecks(reporter, 'installed app was not copied from the mounted DMG');
      return;
    }

    const installedInfoPlistPath = path.join(installedAppPath, 'Contents', 'Info.plist');
    const installedInfoExists = fs.existsSync(installedInfoPlistPath);
    const installedPlist = installedInfoExists
      ? run('plutil', ['-lint', installedInfoPlistPath], 30_000)
      : null;
    reporter.addRequired(
      'installed Info.plist validation',
      installedPlist?.ok === true,
      'copied installed app Info.plist validates',
      installedInfoExists
        ? installedPlist?.output || 'installed Info.plist validation failed'
        : 'copied installed app Info.plist is missing'
    );
    const installedInfoSource = installedInfoExists ? fs.readFileSync(installedInfoPlistPath, 'utf8') : '';
    reporter.addRequired(
      'installed Finder-open document types',
      infoPlistDeclaresFinderOpenTypes(installedInfoSource),
      'copied installed app Info.plist declares audio and folder document types',
      installedInfoExists
        ? 'copied installed app Info.plist lacks public.audio/public.mp3/WAV/folder document types'
        : 'copied installed app Info.plist is missing'
    );
    addInfoPlistPackageVersionCheck(
      reporter,
      'installed Info.plist package version',
      installedInfoSource,
      installedInfoExists ? null : 'copied installed app Info.plist is missing'
    );
    addBundledNodeRuntimeCheck(
      reporter,
      'installed bundled Node runtime',
      path.join(installedAppPath, 'Contents', 'Resources', 'Runtime', 'node')
    );
    addBundledNodeCodesignCheck(
      reporter,
      'installed bundled Node codesign',
      path.join(installedAppPath, 'Contents', 'Resources', 'Runtime', 'node')
    );
    addBundledNodeDependencyCheck(
      reporter,
      'installed bundled Node dependencies',
      path.join(installedAppPath, 'Contents', 'Resources', 'Runtime', 'node')
    );
    addThirdPartyNoticeChecks(
      reporter,
      'installed',
      path.join(installedAppPath, 'Contents', 'Resources', 'ThirdParty', 'THIRD-PARTY-NOTICES.txt'),
      path.join(installedAppPath, 'Contents', 'Resources', 'ThirdParty', 'Node-LICENSE.txt')
    );

    const installedCodesign = run(
      'codesign',
      ['--verify', '--deep', '--strict', installedAppPath],
      30_000
    );
    reporter.addRequired(
      'installed app codesign verification',
      installedCodesign.ok,
      'copied installed app codesign verification passed',
      installedCodesign.output || 'copied installed app codesign verification failed'
    );

    const installedGatekeeper = run(
      'spctl',
      ['--assess', '--type', 'execute', '--verbose', installedAppPath],
      30_000
    );
    reporter.addReleaseRequired(
      'installed app Gatekeeper assessment',
      installedGatekeeper.ok,
      'spctl accepts the copied installed app',
      installedGatekeeper.output || 'copied installed app Gatekeeper assessment failed'
    );
    addQuarantinedAppGatekeeperCheck(
      reporter,
      'installed quarantined app Gatekeeper assessment',
      installedAppPath
    );
  } finally {
    detachDmg(mountPoint);
    if (tempDir) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  }
};

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  const reporter = createReporter(options);
  const manifest = fs.existsSync(manifestPath) ? readJson(manifestPath) : null;

  reporter.addRequired(
    'release manifest',
    manifest?.schemaVersion === 1,
    'native/dist/release-manifest.json schema v1 present',
    'native/dist/release-manifest.json is missing or invalid; run npm run native:package'
  );
  reporter.addRequired(
    'manifest Info.plist package version',
    manifest?.packageVersion === packageVersion &&
      manifest?.artifacts?.app?.infoPlistMetadata?.shortVersion === packageVersion &&
      isValidBundleVersion(manifest?.artifacts?.app?.infoPlistMetadata?.bundleVersion),
    'release manifest records Info.plist version metadata matching package.json',
    `release manifest must record package version ${packageVersion || 'missing'} and valid Info.plist bundle metadata`
  );
  reporter.addRequired(
    'manifest source provenance',
    manifestHasSourceProvenance(manifest),
    `release manifest records source commit ${manifest?.source?.git?.shortCommit}`,
    'release manifest must record git commit, short commit, dirty state, and status entry count'
  );
  reporter.addRequired(
    'manifest build toolchain provenance',
    manifestHasBuildEnvironmentProvenance(manifest),
    'release manifest records Node, Xcode, Swift, macOS, and architecture provenance',
    'release manifest must record Node, Xcode, Swift, macOS, and architecture provenance'
  );
  const currentSource = currentGitProvenance();
  reporter.addReleaseRequired(
    'source revision matches current checkout',
    currentSource.available &&
      manifest?.source?.git?.commit &&
      currentSource.commit === manifest.source.git.commit,
    `manifest source commit ${manifest?.source?.git?.shortCommit} matches the current checkout`,
    currentSource.available
      ? `manifest source commit ${manifest?.source?.git?.shortCommit || 'missing'} does not match current checkout ${currentSource.shortCommit || 'unknown'}`
      : 'current git checkout could not be inspected'
  );
  reporter.addReleaseRequired(
    'source tree clean for release',
    manifest?.source?.git?.isDirty === false,
    'release manifest was generated from a clean git tree',
    manifest?.source?.git?.isDirty === true
      ? `release manifest records a dirty source tree with ${manifest.source.git.statusEntryCount} changed entries`
      : 'release manifest does not prove a clean source tree'
  );

  for (const [label, artifactPath] of [
    ['app bundle', appPath],
    ['zip artifact', zipPath],
    ['dmg artifact', dmgPath],
    ['app executable', executablePath],
    ['Info.plist', infoPlistPath],
    ['bundled Node runtime', bundledNodeRuntimePath],
    ['third-party notice', thirdPartyNoticePath],
    ['Node license', nodeLicensePath],
    ['bundled planner script', plannerScriptPath]
  ]) {
    reporter.addRequired(
      label,
      fs.existsSync(artifactPath),
      `${relative(artifactPath)} present`,
      `${relative(artifactPath)} missing`
    );
  }

  if (manifest) {
    verifyHash(reporter, 'zip checksum', manifest.artifacts?.zip, zipPath);
    verifyHash(reporter, 'dmg checksum', manifest.artifacts?.dmg, dmgPath);
    verifyHash(
      reporter,
      'app executable checksum',
      manifest.artifacts?.app?.executable,
      executablePath
    );
    verifyHash(reporter, 'Info.plist checksum', manifest.artifacts?.app?.infoPlist, infoPlistPath);
    verifyHash(
      reporter,
      'bundled Node runtime checksum',
      manifest.artifacts?.app?.bundledNodeRuntime,
      bundledNodeRuntimePath
    );
    verifyHash(
      reporter,
      'third-party notice checksum',
      manifest.artifacts?.app?.thirdPartyNotice,
      thirdPartyNoticePath
    );
    verifyHash(
      reporter,
      'Node license checksum',
      manifest.artifacts?.app?.nodeLicense,
      nodeLicensePath
    );
    verifyHash(
      reporter,
      'planner script checksum',
      manifest.artifacts?.app?.bundledPlannerScript,
      plannerScriptPath
    );
    verifyReleaseHash(
      reporter,
      'zip notary submit checksum',
      manifest.artifacts?.notaryEvidence?.zipSubmit,
      zipNotarySubmitPath
    );
    verifyReleaseHash(
      reporter,
      'zip notary log checksum',
      manifest.artifacts?.notaryEvidence?.zipLog,
      zipNotaryLogPath
    );
    verifyReleaseHash(
      reporter,
      'DMG notary submit checksum',
      manifest.artifacts?.notaryEvidence?.dmgSubmit,
      dmgNotarySubmitPath
    );
    verifyReleaseHash(
      reporter,
      'DMG notary log checksum',
      manifest.artifacts?.notaryEvidence?.dmgLog,
      dmgNotaryLogPath
    );
  }

  const plist = fs.existsSync(infoPlistPath) ? run('plutil', ['-lint', infoPlistPath]) : null;
  reporter.addRequired(
    'Info.plist validation',
    plist?.ok === true,
    'plutil validation passed',
    plist?.output || 'Info.plist validation could not run'
  );
  const infoPlistSource = fs.existsSync(infoPlistPath) ? fs.readFileSync(infoPlistPath, 'utf8') : '';
  reporter.addRequired(
    'Finder-open document types',
    infoPlistDeclaresFinderOpenTypes(infoPlistSource),
    'Info.plist declares audio and folder document types for Finder Open With',
    fs.existsSync(infoPlistPath)
      ? 'Info.plist lacks public.audio/public.mp3/WAV/folder document types'
      : 'Info.plist is missing'
  );
  addInfoPlistPackageVersionCheck(
    reporter,
    'Info.plist package version',
    infoPlistSource,
    fs.existsSync(infoPlistPath) ? null : 'Info.plist is missing'
  );
  addBundledNodeRuntimeCheck(reporter, 'bundled Node runtime execution', bundledNodeRuntimePath);
  addBundledNodeCodesignCheck(reporter, 'bundled Node codesign verification', bundledNodeRuntimePath);
  addBundledNodeDependencyCheck(reporter, 'bundled Node dependency closure', bundledNodeRuntimePath);
  addThirdPartyNoticeChecks(reporter, 'app', thirdPartyNoticePath, nodeLicensePath);

  const bundledPlannerSyntax = fs.existsSync(plannerScriptPath)
    ? run(
        fs.existsSync(bundledNodeRuntimePath) ? bundledNodeRuntimePath : 'node',
        ['--check', plannerScriptPath]
      )
    : null;
  reporter.addRequired(
    'bundled planner script syntax',
    bundledPlannerSyntax?.ok === true,
    'bundled codex-mix-planner.cjs passes node --check',
    bundledPlannerSyntax?.output || 'bundled planner script syntax could not be checked'
  );

  const appCodesign = fs.existsSync(appPath)
    ? run('codesign', ['--verify', '--deep', '--strict', appPath])
    : null;
  reporter.addRequired(
    'app codesign verification',
    appCodesign?.ok === true,
    'codesign --verify --deep --strict passed',
    appCodesign?.output || 'app codesign verification could not run'
  );

  const appCodesignDetails = fs.existsSync(appPath)
    ? run('codesign', ['-dv', '--verbose=4', appPath])
    : null;
  const appSignature = appCodesignDetails ? parseCodesignDetails(appCodesignDetails.output) : null;
  reporter.addReleaseRequired(
    'Developer ID app signature',
    appSignature?.hasDeveloperIdApplication === true &&
      appSignature.hasDeveloperIdCertificationAuthority &&
      appSignature.hasAppleRoot,
    'Developer ID Application trust chain present',
    appSignature?.isAdHoc
      ? 'app is ad-hoc signed'
      : appCodesignDetails?.output || 'Developer ID Application trust chain missing'
  );
  reporter.addReleaseRequired(
    'hardened runtime',
    appSignature?.hasHardenedRuntime === true,
    'app signature includes hardened runtime',
    'app signature does not report hardened runtime'
  );

  const appStapler = fs.existsSync(appPath) ? run('xcrun', ['stapler', 'validate', appPath]) : null;
  reporter.addReleaseRequired(
    'app notarization ticket',
    appStapler?.ok === true,
    'stapler validates the app notarization ticket',
    appStapler?.output || 'app notarization ticket validation could not run'
  );

  const appGatekeeper = fs.existsSync(appPath)
    ? run('spctl', ['--assess', '--type', 'execute', '--verbose', appPath])
    : null;
  reporter.addReleaseRequired(
    'app Gatekeeper assessment',
    appGatekeeper?.ok === true,
    'spctl accepts the app',
    appGatekeeper?.output || 'app Gatekeeper assessment could not run'
  );
  addQuarantinedAppCopyGatekeeperCheck(
    reporter,
    'app quarantined Gatekeeper assessment',
    appPath
  );

  verifyZipAppFromArchive(reporter);

  const dmgVerify = fs.existsSync(dmgPath) ? run('hdiutil', ['verify', dmgPath]) : null;
  reporter.addRequired(
    'DMG verification',
    dmgVerify?.ok === true,
    'hdiutil verify passed',
    dmgVerify?.output || 'DMG verification could not run'
  );

  const dmgCodesignDetails = fs.existsSync(dmgPath)
    ? run('codesign', ['-dv', '--verbose=4', dmgPath])
    : null;
  const dmgSignature = dmgCodesignDetails?.ok ? parseCodesignDetails(dmgCodesignDetails.output) : null;
  reporter.addReleaseRequired(
    'Developer ID DMG signature',
    dmgSignature?.hasDeveloperIdApplication === true &&
      dmgSignature.hasDeveloperIdCertificationAuthority &&
      dmgSignature.hasAppleRoot,
    'DMG has Developer ID Application trust chain',
    dmgCodesignDetails?.output || 'DMG is not Developer ID signed'
  );

  const dmgStapler = fs.existsSync(dmgPath) ? run('xcrun', ['stapler', 'validate', dmgPath]) : null;
  reporter.addReleaseRequired(
    'DMG notarization ticket',
    dmgStapler?.ok === true,
    'stapler validates the DMG notarization ticket',
    dmgStapler?.output || 'DMG notarization ticket validation could not run'
  );

  const dmgGatekeeper = fs.existsSync(dmgPath)
    ? run('spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose', dmgPath])
    : null;
  reporter.addReleaseRequired(
    'DMG Gatekeeper assessment',
    dmgGatekeeper?.ok === true,
    'spctl accepts the DMG',
    dmgGatekeeper?.output || 'DMG Gatekeeper assessment could not run'
  );
  addQuarantinedDmgGatekeeperCheck(reporter);

  addNotaryEvidenceChecks(reporter, 'zip', zipNotarySubmitPath, zipNotaryLogPath);
  addNotaryEvidenceChecks(reporter, 'DMG', dmgNotarySubmitPath, dmgNotaryLogPath);

  verifyInstalledAppFromDmg(reporter);

  if (manifest) {
    reporter.addReleaseRequired(
      'manifest release mode',
      manifest.releaseMode === 'developer-id',
      'manifest records developer-id release mode',
      `manifest release mode is ${manifest.releaseMode || 'missing'}`
    );
    reporter.addReleaseRequired(
      'manifest notarization intent',
      manifest.signing?.notarizeRequested === true,
      'manifest records notarization was requested',
      'manifest does not record NOTARIZE=1'
    );
  }

  const totals = reporter.checks.reduce(
    (acc, check) => {
      acc[check.status] += 1;
      return acc;
    },
    { pass: 0, warn: 0, blocked: 0 }
  );
  const status = totals.blocked > 0 ? 'BLOCKED' : totals.warn > 0 ? 'WARN' : 'PASS';
  const reportPath = reportPathForOptions(options);
  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    status,
    mode: options.allowAdHoc ? 'local-ad-hoc' : 'strict-release',
    artifacts: {
      app: {
        path: relative(appPath),
        executable: fileSnapshot(executablePath),
        infoPlist: fileSnapshot(infoPlistPath),
        bundledNodeRuntime: fileSnapshot(bundledNodeRuntimePath),
        thirdPartyNotice: fileSnapshot(thirdPartyNoticePath),
        nodeLicense: fileSnapshot(nodeLicensePath),
        bundledPlannerScript: fileSnapshot(plannerScriptPath)
      },
      zip: fileSnapshot(zipPath),
      dmg: fileSnapshot(dmgPath),
      notaryEvidence: {
        zipSubmit: fileSnapshot(zipNotarySubmitPath),
        zipLog: fileSnapshot(zipNotaryLogPath),
        dmgSubmit: fileSnapshot(dmgNotarySubmitPath),
        dmgLog: fileSnapshot(dmgNotaryLogPath)
      },
      manifest: fileSnapshot(manifestPath)
    },
    source: {
      manifest: manifest?.source || null,
      current: currentSource
    },
    totals,
    checks: reporter.checks
  };

  fs.mkdirSync(distDir, { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);

  process.stdout.write(
    [
      '# Native Release Verification',
      `status ${status}`,
      `mode ${options.allowAdHoc ? 'local-ad-hoc' : 'strict-release'}`,
      `pass ${totals.pass}`,
      `warn ${totals.warn}`,
      `blocked ${totals.blocked}`,
      `report ${relative(reportPath)}`,
      ''
    ].join('\n')
  );

  for (const check of reporter.checks) {
    process.stdout.write(`- ${check.status.toUpperCase()} ${check.name}: ${check.detail}\n`);
  }

  if (totals.blocked > 0 && !options.reportOnly) {
    process.exitCode = 1;
  }
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
