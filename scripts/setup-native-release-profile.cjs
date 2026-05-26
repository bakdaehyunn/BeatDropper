#!/usr/bin/env node

const { spawnSync } = require('node:child_process');

const parseArgs = (argv) => {
  const options = {
    storeProfile: false,
    checkOnly: false
  };

  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') {
      process.stdout.write(
        [
          'Usage: node scripts/setup-native-release-profile.cjs [options]',
          '',
          'Options:',
          '  --store-profile  Store Apple notary credentials in the macOS keychain profile.',
          '  --check          Print tool, identity, and credential setup status without storing credentials.',
          '  --help           Show this message.',
          '',
          'Environment for --store-profile:',
          '  NOTARY_KEYCHAIN_PROFILE  Keychain profile name, defaults to beatdropper-notary.',
          '  APPLE_ID                 Apple ID email used for notarization.',
          '  APPLE_TEAM_ID            Apple Developer Team ID.',
          '  APPLE_PASSWORD           App-specific password or notary-compatible password.',
          ''
        ].join('\n')
      );
      process.exit(0);
    }
    if (arg === '--store-profile') {
      options.storeProfile = true;
      continue;
    }
    if (arg === '--check') {
      options.checkOnly = true;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
};

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    timeout: options.timeout ?? 60_000
  });
  return {
    ok: result.status === 0,
    status: result.status,
    signal: result.signal,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const rows = [];
const add = (name, status, detail) => {
  rows.push({ name, status, detail });
};

const summarize = () => {
  const pass = rows.filter((row) => row.status === 'pass').length;
  const blocked = rows.filter((row) => row.status === 'blocked').length;

  process.stdout.write(
    [
      '# Native Release Profile Setup',
      `status ${blocked === 0 ? 'PASS' : 'BLOCKED'}`,
      `pass ${pass}`,
      `blocked ${blocked}`,
      ''
    ].join('\n')
  );

  for (const row of rows) {
    process.stdout.write(`- ${row.status.toUpperCase()} ${row.name}: ${row.detail}\n`);
  }

  if (blocked > 0) {
    process.stdout.write(
      [
        '',
        'Setup command:',
        'NOTARY_KEYCHAIN_PROFILE="beatdropper-notary" \\',
        'APPLE_ID="you@example.com" \\',
        'APPLE_TEAM_ID="TEAMID" \\',
        'APPLE_PASSWORD="app-specific-password" \\',
        'npm run native:release:setup',
        ''
      ].join('\n')
    );
    process.exitCode = 1;
  }
};

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  const profile = process.env.NOTARY_KEYCHAIN_PROFILE || 'beatdropper-notary';
  const appleId = process.env.APPLE_ID || '';
  const appleTeamId = process.env.APPLE_TEAM_ID || '';
  const applePassword = process.env.APPLE_PASSWORD || '';

  const xcodeSelect = run('xcode-select', ['-p']);
  add(
    'Xcode developer directory',
    xcodeSelect.ok && xcodeSelect.output.includes('/Applications/Xcode.app') ? 'pass' : 'blocked',
    xcodeSelect.output || 'xcode-select failed'
  );

  const notarytool = run('xcrun', ['notarytool', '--version']);
  add(
    'notarytool',
    notarytool.ok ? 'pass' : 'blocked',
    notarytool.output || 'xcrun notarytool is unavailable'
  );

  const identities = run('security', ['find-identity', '-v', '-p', 'codesigning']);
  const developerIdLines = (identities.output || '')
    .split('\n')
    .filter((line) => line.includes('Developer ID Application:'));
  add(
    'Developer ID Application identity',
    developerIdLines.length > 0 ? 'pass' : 'blocked',
    developerIdLines.length > 0
      ? developerIdLines.join('\n')
      : 'No valid Developer ID Application signing identity found in this keychain.'
  );

  add(
    'NOTARY_KEYCHAIN_PROFILE',
    profile ? 'pass' : 'blocked',
    profile ? `will use ${profile}` : 'Set NOTARY_KEYCHAIN_PROFILE, for example beatdropper-notary.'
  );

  if (!options.storeProfile) {
    add(
      'credential storage',
      options.checkOnly ? 'pass' : 'blocked',
      options.checkOnly
        ? 'check-only mode did not modify the keychain'
        : 'Run with --store-profile or npm run native:release:setup to store notary credentials.'
    );
    summarize();
    return;
  }

  const hasCredentials = Boolean(appleId && appleTeamId && applePassword);
  add(
    'Apple notary credential environment',
    hasCredentials ? 'pass' : 'blocked',
    hasCredentials
      ? `APPLE_ID and APPLE_TEAM_ID are set for ${appleId} / ${appleTeamId}`
      : 'Set APPLE_ID, APPLE_TEAM_ID, and APPLE_PASSWORD before storing the profile.'
  );

  if (hasCredentials) {
    const store = run(
      'xcrun',
      [
        'notarytool',
        'store-credentials',
        profile,
        '--apple-id',
        appleId,
        '--team-id',
        appleTeamId,
        '--password',
        applePassword
      ],
      { timeout: 120_000 }
    );
    add(
      'notary keychain profile',
      store.ok ? 'pass' : 'blocked',
      store.ok
        ? `stored and validated keychain profile ${profile}`
        : store.output || `failed to store keychain profile ${profile}`
    );
  }

  summarize();
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
