#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const distDir = path.join(rootDir, 'native', 'dist');
const reportPath = path.join(distDir, 'release-readiness-report.json');
const bundledNodeRuntimePath = path.join(
  rootDir,
  'native',
  'dist',
  'BeatDropper.app',
  'Contents',
  'Resources',
  'Runtime',
  'node'
);
const thirdPartyNoticePath = path.join(
  rootDir,
  'native',
  'dist',
  'BeatDropper.app',
  'Contents',
  'Resources',
  'ThirdParty',
  'THIRD-PARTY-NOTICES.txt'
);
const nodeLicensePath = path.join(
  rootDir,
  'native',
  'dist',
  'BeatDropper.app',
  'Contents',
  'Resources',
  'ThirdParty',
  'Node-LICENSE.txt'
);

const parseArgs = (argv) => {
  const options = {
    preRelease: false,
    allowMissingExtendedStress: false
  };

  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') {
      process.stdout.write(
        [
          'Usage: node scripts/check-native-release-readiness.cjs [options]',
          '',
          'Options:',
          '  --pre-release                    Verify credentials and clean source state before building release artifacts.',
          '  --allow-missing-extended-stress  Allow quick local preflight runs to skip the extended session stress report.',
          '  --help                           Show this message.',
          ''
        ].join('\n')
      );
      process.exit(0);
    }
    if (arg === '--pre-release') {
      options.preRelease = true;
      continue;
    }
    if (arg === '--allow-missing-extended-stress') {
      options.allowMissingExtendedStress = true;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
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

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8',
    timeout: options.timeout ?? 45_000
  });
  return {
    ok: result.status === 0,
    status: result.status,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const checkRows = [];

const add = (name, status, detail) => {
  checkRows.push({ name, status, detail });
};

const exists = (relativePath) => fs.existsSync(path.join(rootDir, relativePath));
const readJson = (relativePath) => {
  const filePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
};

const readText = (relativePath) => {
  const filePath = path.join(rootDir, relativePath);
  return fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
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

const env = process.env;
const signIdentity = env.SIGN_IDENTITY || '';
const notaryProfile = env.NOTARY_KEYCHAIN_PROFILE || '';
const appleId = env.APPLE_ID || '';
const appleTeamId = env.APPLE_TEAM_ID || '';
const applePassword = env.APPLE_PASSWORD || '';

const hasAppleIdCredentials = Boolean(appleId && appleTeamId && applePassword);
const hasNotaryCredentials = Boolean(notaryProfile || hasAppleIdCredentials);
const packageJson = readJson('package.json');
const packageVersion = packageJson?.version || null;
const options = parseArgs(process.argv.slice(2));

const xcodeSelect = run('xcode-select', ['-p']);
add(
  'Xcode developer directory',
  xcodeSelect.ok && xcodeSelect.output.includes('/Applications/Xcode.app') ? 'pass' : 'blocked',
  xcodeSelect.output || 'xcode-select failed'
);

const xcodebuild = run('xcodebuild', ['-version']);
add(
  'xcodebuild',
  xcodebuild.ok ? 'pass' : 'blocked',
  xcodebuild.output || 'xcodebuild unavailable'
);

const notarytool = run('xcrun', ['notarytool', '--version']);
add(
  'notarytool',
  notarytool.ok ? 'pass' : 'blocked',
  notarytool.output || 'notarytool unavailable'
);

const nodeRuntime = run('node', ['--version']);
add(
  'Node runtime for planner bridge',
  nodeRuntime.ok ? 'pass' : 'blocked',
  nodeRuntime.ok
    ? `node ${nodeRuntime.output}`
    : 'The native Codex planner bridge runs the bundled planner script through node.'
);

const codexRuntime = run('codex', ['--version']);
add(
  'Codex CLI for AI planner bridge',
  codexRuntime.ok ? 'pass' : 'blocked',
  codexRuntime.ok
    ? codexRuntime.output
    : 'Install/authenticate the Codex CLI or AI planning will fall back to the local deterministic planner.'
);

const identities = run('security', ['find-identity', '-v', '-p', 'codesigning']);
const identityOutput = identities.output || '';
const developerIdLines = identityOutput
  .split('\n')
  .filter((line) => line.includes('Developer ID Application:'));
const identityMatchesEnv =
  signIdentity.length > 0 &&
  signIdentity !== '-' &&
  identityOutput.includes(signIdentity);

add(
  'Developer ID Application identity',
  developerIdLines.length > 0 ? 'pass' : 'blocked',
  developerIdLines.length > 0
    ? developerIdLines.join('\n')
    : 'No valid Developer ID Application signing identity found in this keychain.'
);

add(
  'SIGN_IDENTITY',
  identityMatchesEnv ? 'pass' : 'blocked',
  identityMatchesEnv
    ? `SIGN_IDENTITY matches an installed signing identity: ${signIdentity}`
    : signIdentity && signIdentity !== '-'
      ? `SIGN_IDENTITY is set but does not match an installed valid identity: ${signIdentity}`
      : 'Set SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" before native:release.'
);

add(
  'Notary credentials',
  hasNotaryCredentials ? 'pass' : 'blocked',
  notaryProfile
    ? `Using NOTARY_KEYCHAIN_PROFILE=${notaryProfile}`
    : hasAppleIdCredentials
      ? 'Using APPLE_ID, APPLE_TEAM_ID, and APPLE_PASSWORD.'
      : 'Set NOTARY_KEYCHAIN_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_PASSWORD.'
);

if (hasNotaryCredentials) {
  const notaryValidation = notaryProfile
    ? run('xcrun', ['notarytool', 'history', '--keychain-profile', notaryProfile], { timeout: 90_000 })
    : run(
        'xcrun',
        [
          'notarytool',
          'history',
          '--apple-id',
          appleId,
          '--team-id',
          appleTeamId,
          '--password',
          applePassword
        ],
        { timeout: 90_000 }
      );
  add(
    'Notary credential validation',
    notaryValidation.ok ? 'pass' : 'blocked',
    notaryValidation.ok
      ? notaryProfile
        ? `notarytool authenticated with keychain profile ${notaryProfile}`
        : `notarytool authenticated with APPLE_ID and APPLE_TEAM_ID for ${appleId} / ${appleTeamId}`
      : notaryValidation.output || 'notarytool could not authenticate with the configured notary credentials'
  );
} else {
  add(
    'Notary credential validation',
    'blocked',
    'No notary credentials are configured to validate.'
  );
}

if (options.preRelease) {
  const sourceStatus = run('git', ['status', '--short', '--untracked-files=all']);
  const sourceEntries = sourceStatus.ok
    ? sourceStatus.output.split('\n').map((line) => line.trim()).filter(Boolean)
    : [];
  add(
    'Source tree clean for release',
    sourceStatus.ok && sourceEntries.length === 0 ? 'pass' : 'blocked',
    sourceStatus.ok && sourceEntries.length === 0
      ? 'git status is clean; release manifest can prove a clean source revision'
      : sourceStatus.ok
        ? `git status has ${sourceEntries.length} changed entries; commit or stash changes before native:release`
        : sourceStatus.output || 'could not inspect git status'
  );
}

for (const relativePath of [
  'native/Packaging/Info.plist',
  'native/Packaging/BeatDropper.entitlements',
  'scripts/package-native-app.sh',
  'scripts/setup-native-release-profile.cjs',
  'scripts/write-native-release-manifest.cjs',
  'scripts/verify-native-release.cjs',
  'scripts/smoke-native-app.cjs',
  'scripts/smoke-native-dmg.cjs',
  'scripts/smoke-native-release.cjs',
  'scripts/evaluate-native-parity.cjs'
]) {
  add(relativePath, exists(relativePath) ? 'pass' : 'blocked', exists(relativePath) ? 'present' : 'missing');
}

if (options.preRelease) {
  add(
    'Current artifact verification',
    'pass',
    'skipped for pre-release credential gate; native:release builds fresh signed/notarized artifacts after this gate'
  );
} else if (exists('native/dist/BeatDropper.app')) {
  const codesign = run('codesign', ['--verify', '--deep', '--strict', 'native/dist/BeatDropper.app']);
  add(
    'Current app codesign verification',
    codesign.ok ? 'pass' : 'blocked',
    codesign.ok ? 'codesign --verify passed for native/dist/BeatDropper.app' : codesign.output || 'codesign verification failed'
  );

  const details = run('codesign', ['-dv', '--verbose=4', 'native/dist/BeatDropper.app']);
  add(
    'Current app signature authority',
    /Authority=Developer ID Application:/.test(details.output) ? 'pass' : 'blocked',
    /Signature=adhoc/.test(details.output)
      ? 'Current app is ad-hoc signed.'
      : details.output || 'Could not inspect signature authority.'
  );

  const infoPlistSource = readText('native/dist/BeatDropper.app/Contents/Info.plist');
  const shortVersion = plistStringValue(infoPlistSource, 'CFBundleShortVersionString');
  const bundleVersion = plistStringValue(infoPlistSource, 'CFBundleVersion');
  add(
    'Current app Info.plist package version',
    packageVersion && shortVersion === packageVersion && isValidBundleVersion(bundleVersion)
      ? 'pass'
      : 'blocked',
    packageVersion && shortVersion === packageVersion && isValidBundleVersion(bundleVersion)
      ? `CFBundleShortVersionString ${shortVersion} matches package.json and CFBundleVersion ${bundleVersion} is valid`
      : `expected CFBundleShortVersionString ${packageVersion || 'missing package version'} and numeric CFBundleVersion, found short version ${shortVersion || 'missing'} and bundle version ${bundleVersion || 'missing'}`
  );

  const bundledPlannerSyntax = run('node', [
    '--check',
    'native/dist/BeatDropper.app/Contents/Resources/Scripts/codex-mix-planner.cjs'
  ]);
  add(
    'Bundled planner script syntax',
    bundledPlannerSyntax.ok ? 'pass' : 'blocked',
    bundledPlannerSyntax.ok
      ? 'bundled codex-mix-planner.cjs passes node --check'
      : bundledPlannerSyntax.output || 'bundled planner script syntax check failed'
  );

  const bundledNodeRuntime = fs.existsSync(bundledNodeRuntimePath)
    ? run(bundledNodeRuntimePath, ['--version'])
    : { ok: false, output: 'bundled Node runtime is missing' };
  add(
    'Bundled Node runtime for packaged app',
    bundledNodeRuntime.ok ? 'pass' : 'blocked',
    bundledNodeRuntime.ok
      ? `bundled Node runtime executes: ${bundledNodeRuntime.output}`
      : bundledNodeRuntime.output || 'bundled Node runtime failed to execute'
  );

  const bundledNodeCodesign = fs.existsSync(bundledNodeRuntimePath)
    ? run('codesign', ['--verify', '--strict', bundledNodeRuntimePath])
    : { ok: false, output: 'bundled Node runtime is missing' };
  add(
    'Bundled Node codesign verification',
    bundledNodeCodesign.ok ? 'pass' : 'blocked',
    bundledNodeCodesign.ok
      ? 'codesign verifies bundled Node runtime'
      : bundledNodeCodesign.output || 'bundled Node codesign verification failed'
  );

  const bundledNodeLinkedLibraries = fs.existsSync(bundledNodeRuntimePath)
    ? run('otool', ['-L', bundledNodeRuntimePath])
    : { ok: false, output: 'bundled Node runtime is missing' };
  const linkedLibraries = bundledNodeLinkedLibraries.ok
    ? parseOtoolLibraries(bundledNodeLinkedLibraries.output)
    : [];
  add(
    'Bundled Node dependency closure',
    bundledNodeLinkedLibraries.ok && hasOnlySystemLinkedLibraries(linkedLibraries) ? 'pass' : 'blocked',
    bundledNodeLinkedLibraries.ok && hasOnlySystemLinkedLibraries(linkedLibraries)
      ? `bundled Node links only system or relative libraries (${linkedLibraries.length} libraries)`
      : bundledNodeLinkedLibraries.ok
        ? `bundled Node has non-system absolute dependencies: ${linkedLibraries.join(', ')}`
        : bundledNodeLinkedLibraries.output || 'could not inspect bundled Node linked libraries'
  );

  const thirdPartyNoticeSource = fs.existsSync(thirdPartyNoticePath)
    ? fs.readFileSync(thirdPartyNoticePath, 'utf8')
    : '';
  add(
    'Bundled Node third-party notices',
    /Node\.js runtime/.test(thirdPartyNoticeSource) &&
      /Version: v?[0-9]+/.test(thirdPartyNoticeSource) &&
      /Contents\/Resources\/Runtime\/node/.test(thirdPartyNoticeSource) &&
      /Contents\/Resources\/ThirdParty\/Node-LICENSE\.txt/.test(thirdPartyNoticeSource)
      ? 'pass'
      : 'blocked',
    thirdPartyNoticeSource
      ? 'packaged app includes third-party notices for the bundled Node runtime'
      : 'packaged app is missing Contents/Resources/ThirdParty/THIRD-PARTY-NOTICES.txt'
  );

  const nodeLicenseSource = fs.existsSync(nodeLicensePath)
    ? fs.readFileSync(nodeLicensePath, 'utf8')
    : '';
  add(
    'Bundled Node license notice',
    /Node\.js/.test(nodeLicenseSource) && /MIT License/.test(nodeLicenseSource)
      ? 'pass'
      : 'blocked',
    nodeLicenseSource
      ? 'packaged app includes the Node.js license text'
      : 'packaged app is missing Contents/Resources/ThirdParty/Node-LICENSE.txt'
  );
} else {
  add(
    'Current app bundle',
    'blocked',
    'native/dist/BeatDropper.app is missing. Run npm run native:package first.'
  );
}

if (!options.preRelease && exists('native/dist/BeatDropper.dmg')) {
  const dmg = run('hdiutil', ['verify', 'native/dist/BeatDropper.dmg']);
  add(
    'Current DMG verification',
    dmg.ok ? 'pass' : 'blocked',
    dmg.ok ? 'hdiutil verify passed for native/dist/BeatDropper.dmg' : dmg.output || 'hdiutil verify failed'
  );
}

if (!options.preRelease) {
  const releaseManifest = readJson('native/dist/release-manifest.json');
  const releaseSmokeReport = readJson('native/dist/release-smoke-report.json');
  const analysisBenchmarkReport = readJson('native/dist/analysis-benchmark-report.json');
  const plannerBenchmarkReport = readJson('native/dist/planner-benchmark-report.json');
  const accessibilityCheckReport = readJson('native/dist/accessibility-check-report.json');
  const macosShellCheckReport = readJson('native/dist/macos-shell-check-report.json');
  const libraryStressReport = readJson('native/dist/library-stress-report.json');
  const openImportStressReport = readJson('native/dist/open-import-stress-report.json');
  const playbackStressReport = readJson('native/dist/playback-stress-report.json');
  const sessionStressReport = readJson('native/dist/session-stress-report.json');
  const extendedSessionStressReport = readJson('native/dist/session-stress-extended-report.json');

  const analysisBenchmarkPassed =
    analysisBenchmarkReport?.schemaVersion === 1 &&
    analysisBenchmarkReport?.status === 'PASS' &&
    analysisBenchmarkReport?.allowExpectedGrades === true &&
    Array.isArray(analysisBenchmarkReport?.gradeMismatches) &&
    analysisBenchmarkReport.gradeMismatches.length === 0 &&
    Array.isArray(analysisBenchmarkReport?.suite?.results) &&
    analysisBenchmarkReport.suite.results.length >= 3 &&
    analysisBenchmarkReport.suite.results.every(
      (result) => result?.expectedGrade && result?.result?.grade === result.expectedGrade
    );
  add(
    'Current analysis benchmark report',
    analysisBenchmarkPassed ? 'pass' : 'blocked',
    analysisBenchmarkPassed
      ? 'native/dist/analysis-benchmark-report.json records passing expected-grade DSP fixture evidence'
      : 'Run npm run native:benchmark:analysis:gate to write native/dist/analysis-benchmark-report.json before release readiness.'
  );

  const plannerBenchmarkEvidence = (plannerBenchmarkReport?.results || [])
    .flatMap((result) => result?.plan?.evidence || []);
  const plannerBenchmarkPassed =
    Number(plannerBenchmarkReport?.schemaVersion) >= 1 &&
    plannerBenchmarkReport?.status === 'PASS' &&
    Number(plannerBenchmarkReport?.summary?.passCount) >= 6 &&
    Number(plannerBenchmarkReport?.summary?.failCount) === 0 &&
    plannerBenchmarkEvidence.some((evidence) => /source analysis/i.test(evidence)) &&
    plannerBenchmarkEvidence.some((evidence) => /planner failure/i.test(evidence));
  add(
    'Current planner benchmark report',
    plannerBenchmarkPassed ? 'pass' : 'blocked',
    plannerBenchmarkPassed
      ? 'native/dist/planner-benchmark-report.json records passing fallback-planner cases with analysis-source and planner-failure evidence'
      : 'Run npm run native:benchmark:planner -- --write-json native/dist/planner-benchmark-report.json before release readiness.'
  );

  const accessibilityCheckPassed =
    accessibilityCheckReport?.schemaVersion === 1 &&
    accessibilityCheckReport?.kind === 'accessibility-check' &&
    accessibilityCheckReport?.status === 'PASS' &&
    Number(accessibilityCheckReport?.summary?.checkCount) >= 17 &&
    Number(accessibilityCheckReport?.summary?.failCount) === 0;
  add(
    'Current accessibility check report',
    accessibilityCheckPassed ? 'pass' : 'blocked',
    accessibilityCheckPassed
      ? 'native/dist/accessibility-check-report.json records passing VoiceOver label evidence'
      : 'Run node scripts/check-native-accessibility.cjs --write-json native/dist/accessibility-check-report.json before release readiness.'
  );

  const macosShellCheckPassed =
    macosShellCheckReport?.schemaVersion === 1 &&
    macosShellCheckReport?.kind === 'macos-shell-check' &&
    macosShellCheckReport?.status === 'PASS' &&
    Number(macosShellCheckReport?.summary?.checkCount) >= 15 &&
    Number(macosShellCheckReport?.summary?.failCount) === 0;
  add(
    'Current macOS shell check report',
    macosShellCheckPassed ? 'pass' : 'blocked',
    macosShellCheckPassed
      ? 'native/dist/macos-shell-check-report.json records passing command menu, Settings, Finder Open With, drag/drop, and toolbar evidence'
      : 'Run node scripts/check-native-macos-shell.cjs --write-json native/dist/macos-shell-check-report.json before release readiness.'
  );

  const libraryStressTrackCount = Number(libraryStressReport?.result?.trackCount) || 0;
  const libraryStressPassed =
    libraryStressReport?.schemaVersion === 1 &&
    libraryStressReport?.kind === 'library-stress' &&
    libraryStressReport?.status === 'PASS' &&
    libraryStressTrackCount >= 1_200 &&
    Number(libraryStressReport?.result?.indexedCount) === libraryStressTrackCount &&
    Number(libraryStressReport?.result?.missingCount) === libraryStressTrackCount &&
    Number(libraryStressReport?.result?.relinkedCount) === libraryStressTrackCount &&
    Number(libraryStressReport?.result?.stablePlaylistReferenceCount) >= 64;
  add(
    'Current library stress report',
    libraryStressPassed ? 'pass' : 'blocked',
    libraryStressPassed
      ? 'native/dist/library-stress-report.json records passing large-library persistence, indexing, relink, and saved-set reference evidence'
      : 'Run node scripts/stress-native-library.cjs --write-json native/dist/library-stress-report.json before release readiness.'
  );

  const openImportStressPassed =
    openImportStressReport?.schemaVersion === 1 &&
    openImportStressReport?.kind === 'open-import-stress' &&
    openImportStressReport?.status === 'PASS' &&
    openImportStressReport?.result?.opened === 3 &&
    openImportStressReport?.result?.library === 3 &&
    openImportStressReport?.result?.sourceFolders === 1 &&
    Number(openImportStressReport?.result?.analyzed) >= 3 &&
    openImportStressReport?.result?.finalState === 'Idle' &&
    openImportStressReport?.launch?.ok === true;
  add(
    'Current open-import stress report',
    openImportStressPassed ? 'pass' : 'blocked',
    openImportStressPassed
      ? 'native/dist/open-import-stress-report.json records passing packaged Finder/Open With import evidence'
      : 'Run node scripts/stress-native-open-import.cjs --write-json native/dist/open-import-stress-report.json before release readiness.'
  );

  const playbackStressPassed =
    playbackStressReport?.schemaVersion === 1 &&
    playbackStressReport?.kind === 'playback-stress' &&
    playbackStressReport?.status === 'PASS' &&
    playbackStressReport?.result?.finalState === 'Idle' &&
    playbackStressReport?.launch?.ok === true;
  add(
    'Current playback stress report',
    playbackStressPassed ? 'pass' : 'blocked',
    playbackStressPassed
      ? 'native/dist/playback-stress-report.json records passing packaged playback and crossfade evidence'
      : 'Run node scripts/stress-native-playback.cjs --write-json native/dist/playback-stress-report.json before release readiness.'
  );

  const expectedSessionTransitions = Math.min(
    Number(sessionStressReport?.stress?.transitionCount) || 0,
    Math.max(0, (Number(sessionStressReport?.result?.imported) || 0) - 1)
  );
  const sessionStressPassed =
    sessionStressReport?.schemaVersion === 1 &&
    sessionStressReport?.kind === 'session-stress' &&
    sessionStressReport?.status === 'PASS' &&
    sessionStressReport?.stress?.mode === 'normal' &&
    sessionStressReport?.result?.finalState === 'Idle' &&
    Number(sessionStressReport?.result?.imported) >= Number(sessionStressReport?.stress?.trackCount) &&
    Number(sessionStressReport?.result?.analyzed) >= Number(sessionStressReport?.result?.imported) &&
    Number(sessionStressReport?.result?.maxRunning) >= 1 &&
    Number(sessionStressReport?.result?.maxRunning) <= 4 &&
    Number(sessionStressReport?.result?.planConfidence) > 0 &&
    Number(sessionStressReport?.result?.transitions) >= expectedSessionTransitions &&
    sessionStressReport?.launch?.ok === true;
  add(
    'Current session stress report',
    sessionStressPassed ? 'pass' : 'blocked',
    sessionStressPassed
      ? 'native/dist/session-stress-report.json records passing packaged import, analysis, planner, playback, and transition evidence'
      : 'Run node scripts/stress-native-session.cjs --write-json native/dist/session-stress-report.json before release readiness.'
  );

  const expectedExtendedSessionTransitions = Math.min(
    Number(extendedSessionStressReport?.stress?.transitionCount) || 0,
    Math.max(0, (Number(extendedSessionStressReport?.result?.imported) || 0) - 1)
  );
  const extendedSessionStressPassed =
    extendedSessionStressReport?.schemaVersion === 1 &&
    extendedSessionStressReport?.kind === 'session-stress' &&
    extendedSessionStressReport?.status === 'PASS' &&
    extendedSessionStressReport?.stress?.mode === 'extended' &&
    extendedSessionStressReport?.stress?.extended === true &&
    Number(extendedSessionStressReport?.stress?.trackCount) >= 12 &&
    Number(extendedSessionStressReport?.stress?.transitionCount) >= 6 &&
    extendedSessionStressReport?.result?.finalState === 'Idle' &&
    Number(extendedSessionStressReport?.result?.imported) >= Number(extendedSessionStressReport?.stress?.trackCount) &&
    Number(extendedSessionStressReport?.result?.analyzed) >= Number(extendedSessionStressReport?.result?.imported) &&
    Number(extendedSessionStressReport?.result?.maxRunning) >= 1 &&
    Number(extendedSessionStressReport?.result?.maxRunning) <= 4 &&
    Number(extendedSessionStressReport?.result?.planConfidence) > 0 &&
    Number(extendedSessionStressReport?.result?.transitions) >= expectedExtendedSessionTransitions &&
    extendedSessionStressReport?.launch?.ok === true;
  add(
    'Current extended session stress report',
    extendedSessionStressPassed || (options.allowMissingExtendedStress && !extendedSessionStressReport)
      ? 'pass'
      : 'blocked',
    extendedSessionStressPassed
      ? 'native/dist/session-stress-extended-report.json records passing repeated packaged import, analysis, planner, playback, and transition evidence'
      : options.allowMissingExtendedStress && !extendedSessionStressReport
        ? 'skipped by quick local preflight; default release readiness still requires native/dist/session-stress-extended-report.json'
        : 'Run node scripts/stress-native-session.cjs --extended --write-json native/dist/session-stress-extended-report.json before release readiness.'
  );

  add(
    'Current release manifest',
    releaseManifest?.schemaVersion === 1 ? 'pass' : 'blocked',
    releaseManifest?.schemaVersion === 1
      ? 'native/dist/release-manifest.json schema v1 present'
      : 'Run npm run native:package to generate native/dist/release-manifest.json.'
  );
  add(
    'Current release manifest checksums',
    releaseManifest?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256
      ? 'pass'
      : 'blocked',
    releaseManifest?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256
      ? 'zip, dmg, app executable, bundled Node, and bundled Node notice/license checksums recorded'
      : 'release manifest must record zip, dmg, app executable, bundled Node, and bundled Node notice/license checksums'
  );
  add(
    'Current release manifest Info.plist version metadata',
    releaseManifest?.packageVersion === packageVersion &&
      releaseManifest?.artifacts?.app?.infoPlistMetadata?.shortVersion === packageVersion &&
      isValidBundleVersion(releaseManifest?.artifacts?.app?.infoPlistMetadata?.bundleVersion)
      ? 'pass'
      : 'blocked',
    releaseManifest?.packageVersion === packageVersion &&
      releaseManifest?.artifacts?.app?.infoPlistMetadata?.shortVersion === packageVersion &&
      isValidBundleVersion(releaseManifest?.artifacts?.app?.infoPlistMetadata?.bundleVersion)
      ? 'release manifest records app Info.plist version metadata matching package.json'
      : 'release manifest must record packageVersion and app Info.plist version metadata matching package.json'
  );
  add(
    'Current release manifest source provenance',
    /^[a-f0-9]{40}$/i.test(releaseManifest?.source?.git?.commit || '') &&
      typeof releaseManifest?.source?.git?.isDirty === 'boolean' &&
      Number.isInteger(releaseManifest?.source?.git?.statusEntryCount) &&
      releaseManifest?.source?.environment?.nodeVersion &&
      releaseManifest?.source?.environment?.xcodebuildVersion &&
      releaseManifest?.source?.environment?.swiftVersion &&
      releaseManifest?.source?.environment?.macOSVersion &&
      releaseManifest?.source?.environment?.architecture
      ? 'pass'
      : 'blocked',
    /^[a-f0-9]{40}$/i.test(releaseManifest?.source?.git?.commit || '') &&
      typeof releaseManifest?.source?.git?.isDirty === 'boolean' &&
      Number.isInteger(releaseManifest?.source?.git?.statusEntryCount) &&
      releaseManifest?.source?.environment?.nodeVersion &&
      releaseManifest?.source?.environment?.xcodebuildVersion &&
      releaseManifest?.source?.environment?.swiftVersion &&
      releaseManifest?.source?.environment?.macOSVersion &&
      releaseManifest?.source?.environment?.architecture
      ? `release manifest records source commit ${releaseManifest.source.git.shortCommit || releaseManifest.source.git.commit.slice(0, 12)} and build toolchain provenance`
      : 'release manifest must record git source and build toolchain provenance'
  );

add(
  'Current release smoke report',
  releaseSmokeReport?.schemaVersion === 1 &&
    releaseSmokeReport?.status === 'PASS' &&
    releaseManifest?.packageVersion === releaseSmokeReport?.releaseManifest?.packageVersion &&
    releaseManifest?.source?.git?.commit === releaseSmokeReport?.releaseManifest?.source?.git?.commit &&
    releaseManifest?.source?.git?.isDirty === releaseSmokeReport?.releaseManifest?.source?.git?.isDirty &&
    releaseManifest?.source?.environment?.xcodebuildVersion === releaseSmokeReport?.releaseManifest?.source?.environment?.xcodebuildVersion &&
    releaseManifest?.signing?.notarizeRequested === releaseSmokeReport?.releaseManifest?.signing?.notarizeRequested &&
    releaseManifest?.releaseMode === releaseSmokeReport?.releaseManifest?.releaseMode &&
    releaseManifest?.artifacts?.manifest?.path === releaseSmokeReport?.artifacts?.manifest?.path &&
    releaseManifest?.artifacts?.zip?.sha256 === releaseSmokeReport?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 === releaseSmokeReport?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 === releaseSmokeReport?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.infoPlist?.sha256 === releaseSmokeReport?.artifacts?.app?.infoPlist?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === releaseSmokeReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === releaseSmokeReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === releaseSmokeReport?.artifacts?.app?.nodeLicense?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === releaseSmokeReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
      releaseSmokeReport?.steps?.some((step) => step.label === 'installed app smoke' && step.outcome === 'pass')
      ? 'pass'
      : 'blocked',
  releaseSmokeReport?.schemaVersion === 1 &&
    releaseSmokeReport?.status === 'PASS' &&
    releaseManifest?.packageVersion === releaseSmokeReport?.releaseManifest?.packageVersion &&
    releaseManifest?.source?.git?.commit === releaseSmokeReport?.releaseManifest?.source?.git?.commit &&
    releaseManifest?.source?.git?.isDirty === releaseSmokeReport?.releaseManifest?.source?.git?.isDirty &&
    releaseManifest?.source?.environment?.xcodebuildVersion === releaseSmokeReport?.releaseManifest?.source?.environment?.xcodebuildVersion &&
    releaseManifest?.signing?.notarizeRequested === releaseSmokeReport?.releaseManifest?.signing?.notarizeRequested &&
    releaseManifest?.releaseMode === releaseSmokeReport?.releaseManifest?.releaseMode &&
    releaseManifest?.artifacts?.manifest?.path === releaseSmokeReport?.artifacts?.manifest?.path &&
    releaseManifest?.artifacts?.zip?.sha256 === releaseSmokeReport?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 === releaseSmokeReport?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 === releaseSmokeReport?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.infoPlist?.sha256 === releaseSmokeReport?.artifacts?.app?.infoPlist?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === releaseSmokeReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === releaseSmokeReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === releaseSmokeReport?.artifacts?.app?.nodeLicense?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === releaseSmokeReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
      releaseSmokeReport?.steps?.some((step) => step.label === 'installed app smoke' && step.outcome === 'pass')
    ? 'native/dist/release-smoke-report.json records passing launch smoke for the current manifest checksums and source provenance'
    : 'Run npm run native:release:smoke after packaging to record launch evidence for the current manifest checksums and source provenance.'
);

  if (exists('native/dist/BeatDropper.app') && exists('native/dist/BeatDropper.dmg')) {
  const localReleaseVerify = run('node', [
    'scripts/verify-native-release.cjs',
    '--allow-ad-hoc',
    '--report-only'
  ]);
  const localReleaseVerificationReport = readJson('native/dist/local-release-verification-report.json');
  add(
    'Current local post-release verification',
    localReleaseVerify.ok && /^status (PASS|WARN)$/m.test(localReleaseVerify.output) ? 'pass' : 'blocked',
    localReleaseVerify.ok
      ? (localReleaseVerify.output.match(/^status .+$/m)?.[0] || 'local post-release verifier ran')
      : localReleaseVerify.output || 'local post-release verification failed'
  );
  add(
    'Current local release verification report',
    localReleaseVerificationReport?.schemaVersion === 1 &&
      /^(PASS|WARN)$/.test(localReleaseVerificationReport.status || '') &&
      releaseManifest?.artifacts?.zip?.sha256 === localReleaseVerificationReport?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 === localReleaseVerificationReport?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 === localReleaseVerificationReport?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.infoPlist?.sha256 === localReleaseVerificationReport?.artifacts?.app?.infoPlist?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === localReleaseVerificationReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === localReleaseVerificationReport?.artifacts?.app?.nodeLicense?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest source provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest build toolchain provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source revision matches current checkout' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source tree clean for release' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node runtime execution' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node dependency closure' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app extraction' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app copy' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed quarantined app Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app codesign verification' && check.status === 'pass')
      ? 'pass'
      : 'blocked',
    localReleaseVerificationReport?.schemaVersion === 1 &&
      /^(PASS|WARN)$/.test(localReleaseVerificationReport.status || '') &&
      releaseManifest?.artifacts?.zip?.sha256 === localReleaseVerificationReport?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 === localReleaseVerificationReport?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 === localReleaseVerificationReport?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.infoPlist?.sha256 === localReleaseVerificationReport?.artifacts?.app?.infoPlist?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === localReleaseVerificationReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === localReleaseVerificationReport?.artifacts?.app?.nodeLicense?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest source provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest build toolchain provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source revision matches current checkout' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source tree clean for release' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node runtime execution' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node dependency closure' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app extraction' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app copy' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed quarantined app Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app codesign verification' && check.status === 'pass')
      ? 'native/dist/local-release-verification-report.json records passing local ZIP, source provenance, quarantine simulation, bundled Node notice/license, version metadata, and installed-app verification for the current manifest checksums'
      : 'Run npm run native:release:verify:local to write native/dist/local-release-verification-report.json for the current manifest checksums.'
  );
  }
}

const passCount = checkRows.filter((row) => row.status === 'pass').length;
const blockedCount = checkRows.filter((row) => row.status === 'blocked').length;
const status = blockedCount === 0 ? 'PASS' : 'BLOCKED';

fs.mkdirSync(distDir, { recursive: true });
fs.writeFileSync(
  reportPath,
  `${JSON.stringify(
    {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      status,
      packageVersion,
      signing: {
        signIdentityConfigured: Boolean(signIdentity && signIdentity !== '-'),
        notaryCredentialMode: notaryProfile
          ? 'keychain-profile'
          : hasAppleIdCredentials
            ? 'apple-id-env'
            : 'missing'
      },
      totals: {
        pass: passCount,
        blocked: blockedCount
      },
      checks: checkRows
    },
    null,
    2
  )}\n`
);

process.stdout.write(
  [
    '# Native Release Readiness',
    `status ${status}`,
    `pass ${passCount}`,
    `blocked ${blockedCount}`,
    `report ${path.relative(rootDir, reportPath)}`,
    ''
  ].join('\n')
);

for (const row of checkRows) {
  process.stdout.write(`- ${row.status.toUpperCase()} ${row.name}: ${row.detail}\n`);
}

if (blockedCount > 0) {
  process.stdout.write(
    [
      '',
      'Next release command once blockers are resolved:',
      'NOTARY_KEYCHAIN_PROFILE="beatdropper-notary" \\',
      'APPLE_ID="you@example.com" \\',
      'APPLE_TEAM_ID="TEAMID" \\',
      'APPLE_PASSWORD="app-specific-password" \\',
      'npm run native:release:setup',
      '',
      'SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \\',
      'NOTARY_KEYCHAIN_PROFILE="beatdropper-notary" \\',
      'npm run native:release',
      ''
    ].join('\n')
  );
  process.exitCode = 1;
}
