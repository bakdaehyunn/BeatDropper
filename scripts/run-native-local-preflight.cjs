#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const distDir = path.join(rootDir, 'native', 'dist');

const parseArgs = (argv) => {
  const options = {
    skipExtendedStress: false,
    strictRelease: false
  };

  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') {
      process.stdout.write(
        [
          'Usage: node scripts/run-native-local-preflight.cjs [options]',
          '',
          'Runs the local native release-candidate gate without requiring Apple Developer credentials.',
          '',
          'Options:',
          '  --skip-extended-stress  Skip the longer packaged session stress loop.',
          '  --strict-release        Require Developer ID signing and notary readiness before running the full gate.',
          '  --help                  Show this message.',
          ''
        ].join('\n')
      );
      process.exit(0);
    }
    if (arg === '--skip-extended-stress') {
      options.skipExtendedStress = true;
      continue;
    }
    if (arg === '--strict-release') {
      options.strictRelease = true;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
};

const run = (label, command, args, options = {}) => {
  const startedAt = Date.now();
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8',
    timeout: options.timeout ?? 120_000,
    env: {
      ...process.env,
      ...(options.env || {})
    }
  });
  const durationMs = Date.now() - startedAt;
  const output = `${result.stdout || ''}${result.stderr || ''}`.trim();

  return {
    label,
    command: [command, ...args].join(' '),
    status: result.status,
    signal: result.signal,
    ok: result.status === 0,
    durationMs,
    output
  };
};

const parseBlockedNames = (output) => {
  const names = [];
  for (const line of output.split('\n')) {
    const match = line.match(/^- BLOCKED ([^:]+):/);
    if (match) {
      names.push(match[1]);
    }
  }
  return names;
};

const allowedReleaseReadinessBlockers = new Set([
  'Developer ID Application identity',
  'SIGN_IDENTITY',
  'Notary credentials',
  'Notary credential validation',
  'Current app signature authority'
]);

const allowedNativeParityBlockers = new Set([
  'Developer ID signing',
  'Gatekeeper assessment',
  'Strict release verification report'
]);

const makeOutcome = (step, options = {}) => {
  if (options.allowBlockedNames) {
    const blockedNames = parseBlockedNames(step.output);
    const unexpected = blockedNames.filter((name) => !options.allowBlockedNames.has(name));
    if (unexpected.length === 0 && (step.ok || blockedNames.length > 0)) {
      return {
        ...step,
        outcome: 'pass',
        allowedBlockers: blockedNames,
        note: blockedNames.length > 0
          ? 'Only expected external release blockers remain.'
          : null
      };
    }
    return {
      ...step,
      outcome: 'fail',
      allowedBlockers: blockedNames.filter((name) => options.allowBlockedNames.has(name)),
      unexpectedBlockers: unexpected
    };
  }

  if (step.ok) {
    return { ...step, outcome: 'pass', allowedBlockers: [] };
  }

  return {
    ...step,
    outcome: 'fail',
    allowedBlockers: [],
    unexpectedBlockers: parseBlockedNames(step.output)
  };
};

const compactOutput = (output) => {
  const lines = output.split('\n').filter(Boolean);
  if (lines.length <= 12) {
    return lines;
  }
  return [...lines.slice(0, 6), '...', ...lines.slice(-6)];
};

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  fs.mkdirSync(distDir, { recursive: true });
  const reportPath = path.join(
    distDir,
    options.strictRelease ? 'release-preflight-report.json' : 'local-preflight-report.json'
  );

  const steps = [];

  if (options.strictRelease) {
    const releaseReadiness = makeOutcome(
      run('strict native release readiness', 'node', ['scripts/check-native-release-readiness.cjs', '--pre-release'], {
        timeout: 45_000
      })
    );
    steps.push(releaseReadiness);
    if (releaseReadiness.outcome !== 'pass') {
      writeReportAndExit({ options, steps, reportPath });
      return;
    }
  }

  steps.push(
    makeOutcome(run('git whitespace check', 'git', ['diff', '--check'], { timeout: 30_000 })),
    makeOutcome(
      run('native accessibility check', 'node', [
        'scripts/check-native-accessibility.cjs',
        '--write-json',
        'native/dist/accessibility-check-report.json'
      ])
    ),
    makeOutcome(
      run('native macOS shell check', 'node', [
        'scripts/check-native-macos-shell.cjs',
        '--write-json',
        'native/dist/macos-shell-check-report.json'
      ])
    ),
    makeOutcome(run('native Swift tests', 'swift', ['test', '--package-path', 'native'], { timeout: 180_000 })),
    makeOutcome(
      run('native analysis benchmark gate', 'node', [
        'scripts/evaluate-native-analysis-benchmarks.cjs',
        '--allow-expected-grades',
        '--write-json',
        'native/dist/analysis-benchmark-report.json'
      ])
    ),
    makeOutcome(
      run('native planner benchmark', 'node', [
        'scripts/evaluate-native-planner-benchmarks.cjs',
        '--write-json',
        'native/dist/planner-benchmark-report.json'
      ])
    ),
    makeOutcome(
      run('local ad-hoc native package', 'scripts/package-native-app.sh', [], {
        timeout: 180_000,
        env: {
          SIGN_IDENTITY: '-',
          NOTARIZE: '0'
        }
      })
    ),
    makeOutcome(run('local release artifact verification', 'node', ['scripts/verify-native-release.cjs', '--allow-ad-hoc'])),
    makeOutcome(run('packaged release smoke report', 'node', ['scripts/smoke-native-release.cjs'])),
    makeOutcome(
      run('packaged open-import stress', 'node', [
        'scripts/stress-native-open-import.cjs',
        '--write-json',
        'native/dist/open-import-stress-report.json'
      ])
    ),
    makeOutcome(
      run('packaged playback stress', 'node', [
        'scripts/stress-native-playback.cjs',
        '--write-json',
        'native/dist/playback-stress-report.json'
      ])
    ),
    makeOutcome(
      run('packaged session stress', 'node', [
        'scripts/stress-native-session.cjs',
        '--write-json',
        'native/dist/session-stress-report.json'
      ], { timeout: 110_000 })
    )
  );

  if (!options.skipExtendedStress) {
    steps.push(
      makeOutcome(
        run('packaged extended session stress', 'node', [
          'scripts/stress-native-session.cjs',
          '--extended',
          '--write-json',
          'native/dist/session-stress-extended-report.json'
        ], { timeout: 150_000 })
      )
    );
  }

  steps.push(
    makeOutcome(
      run('native large-library stress', 'node', [
        'scripts/stress-native-library.cjs',
        '--write-json',
        'native/dist/library-stress-report.json'
      ], { timeout: 120_000 })
    )
  );
  if (!options.strictRelease) {
    const releaseReadinessArgs = ['scripts/check-native-release-readiness.cjs'];
    if (options.skipExtendedStress) {
      releaseReadinessArgs.push('--allow-missing-extended-stress');
    }
    steps.push(
      makeOutcome(
        run('native release readiness', 'node', releaseReadinessArgs, {
          timeout: 45_000
        }),
        { allowBlockedNames: allowedReleaseReadinessBlockers }
      )
    );
  }
  const parityArgs = [
    'scripts/evaluate-native-parity.cjs',
    '--report-only'
  ];
  if (options.skipExtendedStress) {
    parityArgs.push('--allow-missing-extended-stress');
  }
  steps.push(
    makeOutcome(
      run('native parity', 'node', parityArgs),
      { allowBlockedNames: allowedNativeParityBlockers }
    )
  );

  writeReportAndExit({ options, steps, reportPath });
};

const writeReportAndExit = ({ options, steps, reportPath }) => {
  const failed = steps.filter((step) => step.outcome !== 'pass');
  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    status: failed.length === 0 ? 'PASS' : 'FAIL',
    mode: options.strictRelease ? 'strict-release' : 'local-ad-hoc',
    skippedExtendedStress: options.skipExtendedStress,
    steps: steps.map((step) => ({
      label: step.label,
      command: step.command,
      outcome: step.outcome,
      status: step.status,
      signal: step.signal,
      durationMs: step.durationMs,
      allowedBlockers: step.allowedBlockers || [],
      unexpectedBlockers: step.unexpectedBlockers || [],
      note: step.note || null,
      outputPreview: compactOutput(step.output)
    }))
  };

  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);

  process.stdout.write(
    [
      options.strictRelease ? '# Native Release Preflight' : '# Native Local Preflight',
      `status ${report.status}`,
      `steps ${steps.length}`,
      `failed ${failed.length}`,
      `report ${path.relative(rootDir, reportPath)}`,
      ''
    ].join('\n')
  );

  for (const step of steps) {
    const suffix = step.allowedBlockers?.length
      ? `; allowed blockers: ${step.allowedBlockers.join(', ')}`
      : step.unexpectedBlockers?.length
        ? `; blockers: ${step.unexpectedBlockers.join(', ')}`
      : '';
    process.stdout.write(
      `- ${step.outcome.toUpperCase()} ${step.label} (${Math.round(step.durationMs)} ms)${suffix}\n`
    );
  }

  if (failed.length > 0) {
    process.exitCode = 1;
  }
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
