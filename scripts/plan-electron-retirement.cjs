#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const distDir = path.join(rootDir, 'native', 'dist');
const defaultReportPath = path.join(distDir, 'electron-retirement-plan.json');

const electronSourcePaths = [
  'src/main',
  'src/preload',
  'src/renderer',
  'src/shared',
  'tests/e2e-electron',
  'tests/e2e',
  'tests/integration',
  'tests/unit'
];

const electronConfigPaths = [
  'index.html',
  'vite.config.ts',
  'vitest.config.ts',
  'playwright.config.ts',
  'playwright.electron.config.ts',
  'tsconfig.base.json',
  'tsconfig.electron.json',
  'tsconfig.json'
];

const generatedElectronPaths = [
  'dist',
  'dist-electron',
  'playwright-report',
  'test-results'
];

const historicalDocsToReview = [
  'README.md',
  'docs'
];

const nativePathsToKeep = [
  'native',
  'scripts/codex-mix-planner.cjs',
  'scripts/check-electron-retirement-readiness.cjs',
  'scripts/check-native-accessibility.cjs',
  'scripts/check-native-macos-shell.cjs',
  'scripts/check-native-release-readiness.cjs',
  'scripts/create-analysis-benchmark-fixture.cjs',
  'scripts/evaluate-native-analysis-benchmarks.cjs',
  'scripts/evaluate-native-parity.cjs',
  'scripts/evaluate-native-planner-benchmarks.cjs',
  'scripts/package-native-app.sh',
  'scripts/plan-electron-retirement.cjs',
  'scripts/run-native-local-preflight.cjs',
  'scripts/setup-native-release-profile.cjs',
  'scripts/smoke-native-app.cjs',
  'scripts/smoke-native-dmg.cjs',
  'scripts/smoke-native-release.cjs',
  'scripts/stress-native-library.cjs',
  'scripts/stress-native-open-import.cjs',
  'scripts/stress-native-playback.cjs',
  'scripts/stress-native-session.cjs',
  'scripts/validate-loudness-reference.cjs',
  'scripts/validate-native-real-folder.cjs',
  'scripts/verify-native-release.cjs',
  'scripts/write-native-release-manifest.cjs',
  'native/Sources/BeatDropperNativeLoudnessValidation',
  'tests/fixtures'
];

const nativeScriptNamesToKeep = [
  'native:accessibility:check',
  'native:benchmark:analysis',
  'native:benchmark:analysis:create',
  'native:benchmark:analysis:gate',
  'native:benchmark:planner',
  'native:build',
  'native:macos-shell:check',
  'native:package',
  'native:parity',
  'native:parity:report',
  'native:preflight:local',
  'native:preflight:release',
  'native:release',
  'native:release:check',
  'native:release:manifest',
  'native:release:setup',
  'native:release:setup:check',
  'native:release:smoke',
  'native:release:verify',
  'native:release:verify:local',
  'native:retire:check',
  'native:retire:plan',
  'native:run',
  'native:smoke',
  'native:smoke:dmg',
  'native:stress:library',
  'native:stress:open-import',
  'native:stress:playback',
  'native:stress:session',
  'native:stress:session:extended',
  'native:validate:loudness-reference',
  'native:validate:real-folder',
  'native:test'
];

const packageFieldsToUpdate = [
  { field: 'main', action: 'remove', reason: 'points to dist-electron/main/main.js' },
  { field: 'description', action: 'review', reason: 'confirm package metadata describes the native-only app after Electron removal' }
];

const parseArgs = (argv) => {
  const options = {
    reportPath: defaultReportPath,
    runChecks: true
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      process.stdout.write(
        [
          'Usage: node scripts/plan-electron-retirement.cjs [options]',
          '',
          'Writes a dry-run plan for removing Electron after native notarized parity is proven.',
          '',
          'Options:',
          '  --out <path>       Write the plan to a custom path.',
          '  --no-checks        Skip live readiness checks and only inspect files/package metadata.',
          '  --help             Show this message.',
          ''
        ].join('\n')
      );
      process.exit(0);
    }
    if (arg === '--out') {
      if (!argv[index + 1]) {
        throw new Error('--out requires a path.');
      }
      options.reportPath = path.resolve(rootDir, argv[index + 1]);
      index += 1;
      continue;
    }
    if (arg === '--no-checks') {
      options.runChecks = false;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
};

const exists = (relativePath) => fs.existsSync(path.join(rootDir, relativePath));

const readPackageJson = () => JSON.parse(fs.readFileSync(path.join(rootDir, 'package.json'), 'utf8'));

const run = (command, args, timeout = 45_000) => {
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

const compactOutput = (output) => {
  const lines = output.split('\n').filter(Boolean);
  if (lines.length <= 10) {
    return lines;
  }
  return [...lines.slice(0, 5), '...', ...lines.slice(-5)];
};

const classifyScript = (name, command) => {
  if (nativeScriptNamesToKeep.includes(name)) {
    return 'keep';
  }
  if (
    /^(dev|build|test|test:watch|test:e2e|test:e2e:electron|test:e2e:all|benchmark:analysis|benchmark:analysis:create|security:check)$/.test(name) ||
    /electron|renderer|tsconfig\.electron|vite|vitest|playwright/.test(command)
  ) {
    return 'remove';
  }
  if (name === 'security:scan') {
    return 'review';
  }
  return name.startsWith('native:') ? 'keep' : 'review';
};

const buildPackagePlan = (packageJson) => {
  const scripts = packageJson.scripts || {};
  const scriptActions = Object.entries(scripts).map(([name, command]) => ({
    name,
    command,
    action: classifyScript(name, command)
  }));
  const dependencies = Object.keys(packageJson.dependencies || {});
  const devDependencies = Object.keys(packageJson.devDependencies || {});

  return {
    fieldsToUpdate: packageFieldsToUpdate,
    scriptsToKeep: scriptActions.filter((script) => script.action === 'keep').map((script) => script.name),
    scriptsToRemove: scriptActions.filter((script) => script.action === 'remove').map((script) => script.name),
    scriptsToReview: scriptActions.filter((script) => script.action === 'review').map((script) => script.name),
    dependenciesToRemove: dependencies,
    devDependenciesToRemove: devDependencies,
    lockfileAction: exists('package-lock.json')
      ? 'regenerate after package dependency removal'
      : 'none'
  };
};

const buildFilePlan = () => ({
  removeSourcePaths: electronSourcePaths.filter(exists),
  removeConfigPaths: electronConfigPaths.filter(exists),
  cleanGeneratedPaths: generatedElectronPaths.filter(exists),
  reviewHistoricalDocs: historicalDocsToReview.filter(exists),
  keepNativePaths: nativePathsToKeep.filter(exists)
});

const buildReadiness = (runChecks) => {
  if (!runChecks) {
    return {
      skipped: true,
      checks: []
    };
  }

  const checks = [
    {
      name: 'strict release preflight',
      requiredBeforeRemoval: true,
      command: 'npm run native:preflight:release',
      result: run('npm', ['run', 'native:preflight:release'], 60_000)
    },
    {
      name: 'local preflight',
      requiredBeforeRemoval: true,
      command: 'npm run native:preflight:local -- --skip-extended-stress',
      result: run('npm', ['run', 'native:preflight:local', '--', '--skip-extended-stress'], 120_000)
    },
    {
      name: 'pre-retirement parity',
      requiredBeforeRemoval: true,
      command: 'npm run native:parity -- --pre-retirement',
      result: run('npm', ['run', 'native:parity', '--', '--pre-retirement'], 60_000)
    }
  ];

  return {
    skipped: false,
    checks: checks.map((check) => ({
      name: check.name,
      requiredBeforeRemoval: check.requiredBeforeRemoval,
      command: check.command,
      ok: check.result.ok,
      status: check.result.status,
      signal: check.result.signal,
      outputPreview: compactOutput(check.result.output)
    }))
  };
};

const buildSequence = () => [
  'Pass native:preflight:release with Developer ID signing and notary credentials.',
  'Pass native:release, including strict PASS native/dist/release-verification-report.json and PASS native/dist/release-smoke-report.json evidence for bundle version metadata, the notarized app, quarantined Gatekeeper checks, mounted DMG, and copied installed app.',
  'Pass native:parity -- --pre-retirement.',
  'Commit or archive the last Electron reference state for rollback.',
  'Remove planned Electron source, configs, generated artifacts, scripts, dependencies, and lockfile entries in one audited change.',
  'Update README/docs so native macOS is the only primary app path.',
  'Run native:preflight:local, native:parity, and native:retire:check after removal.'
];

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  fs.mkdirSync(path.dirname(options.reportPath), { recursive: true });

  const packageJson = readPackageJson();
  const plan = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    status: 'DRY_RUN',
    purpose: 'Plan the final Electron retirement change after native notarized parity is proven.',
    removalIsSafeNow: false,
    blockingReason: 'Electron must remain until strict native release, Gatekeeper, and pre-retirement parity pass.',
    readiness: buildReadiness(options.runChecks),
    files: buildFilePlan(),
    package: buildPackagePlan(packageJson),
    sequence: buildSequence()
  };

  fs.writeFileSync(options.reportPath, `${JSON.stringify(plan, null, 2)}\n`);

  const readinessFailures = plan.readiness.checks?.filter((check) => !check.ok) || [];
  process.stdout.write(
    [
      '# Electron Retirement Plan',
      'status DRY_RUN',
      `report ${path.relative(rootDir, options.reportPath)}`,
      `remove source paths ${plan.files.removeSourcePaths.length}`,
      `remove config paths ${plan.files.removeConfigPaths.length}`,
      `remove scripts ${plan.package.scriptsToRemove.length}`,
      `remove dependencies ${plan.package.dependenciesToRemove.length + plan.package.devDependenciesToRemove.length}`,
      `readiness failures ${readinessFailures.length}`,
      ''
    ].join('\n')
  );

  if (readinessFailures.length > 0) {
    for (const failure of readinessFailures) {
      process.stdout.write(`- BLOCKED ${failure.name}: ${failure.command}\n`);
    }
  }
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
