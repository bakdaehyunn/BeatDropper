#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const distDir = path.join(rootDir, 'native', 'dist');
const defaultReportPath = path.join(distDir, 'electron-retirement-readiness-report.json');

const electronPaths = [
  'src/main',
  'src/preload',
  'src/renderer',
  'src/shared',
  'tests/e2e-electron',
  'tests/e2e',
  'tests/integration',
  'tests/unit',
  'playwright.electron.config.ts',
  'electron.vite.config.ts',
  'tsconfig.electron.json'
];

const electronPackageDeps = [
  'electron',
  'react',
  'react-dom',
  '@vitejs/plugin-react',
  'vite'
];

const parseArgs = (argv) => {
  const options = {
    reportPath: null,
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      options.help = true;
      continue;
    }
    if (arg === '--write-json') {
      const next = argv[index + 1];
      if (!next) {
        throw new Error('--write-json requires a report path');
      }
      options.reportPath = path.resolve(rootDir, next);
      index += 1;
      continue;
    }
    if (arg.startsWith('--write-json=')) {
      const next = arg.slice('--write-json='.length);
      if (!next) {
        throw new Error('--write-json requires a report path');
      }
      options.reportPath = path.resolve(rootDir, next);
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
};

const printUsage = () => {
  process.stdout.write(
    [
      'Usage: node scripts/check-electron-retirement-readiness.cjs [options]',
      '',
      'Checks whether Electron can be removed after native notarized parity is proven.',
      '',
      'Options:',
      '  --write-json <path>  Write durable Electron retirement readiness evidence.',
      '  --help               Show this message.',
      ''
    ].join('\n')
  );
};

let options;
try {
  options = parseArgs(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
}

if (options.help) {
  printUsage();
  process.exit(0);
}

const run = (command, args) => {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8'
  });
  return {
    ok: result.status === 0,
    status: result.status,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const packageJson = JSON.parse(fs.readFileSync(path.join(rootDir, 'package.json'), 'utf8'));
const scripts = packageJson.scripts || {};
const deps = {
  ...(packageJson.dependencies || {}),
  ...(packageJson.devDependencies || {})
};

const existingElectronPaths = electronPaths.filter((relativePath) =>
  fs.existsSync(path.join(rootDir, relativePath))
);
const existingElectronDeps = electronPackageDeps.filter((name) => deps[name]);
const electronScripts = Object.keys(scripts)
  .filter((name) => !name.startsWith('native:'))
  .filter((name) =>
    /^(dev|build|test:e2e|test:e2e:electron|test:e2e:all|benchmark:analysis|benchmark:analysis:create)$/.test(name) ||
    /electron|renderer|main/.test(scripts[name])
  );

const checks = [];
const add = (name, status, detail) => checks.push({ name, status, detail });
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

const strictReleaseVerificationReport = readJson('native/dist/release-verification-report.json');
const strictReleaseVerificationPassed =
  strictReleaseVerificationReport?.schemaVersion === 1 &&
  strictReleaseVerificationReport?.status === 'PASS' &&
  strictReleaseVerificationReport?.mode === 'strict-release' &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'manifest Info.plist package version' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'manifest source provenance' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'manifest build toolchain provenance' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'source revision matches current checkout' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'source tree clean for release' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'Info.plist package version' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'bundled planner script syntax' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'bundled Node runtime execution' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'bundled Node codesign verification' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'bundled Node dependency closure' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'app third-party notice' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'app Node license' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip notary submission evidence' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'DMG notary submission evidence' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app Gatekeeper assessment' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app quarantined Gatekeeper assessment' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app Info.plist package version' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app bundled Node runtime' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app bundled Node codesign' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app bundled Node dependencies' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app third-party notice' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'zip app Node license' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed app Gatekeeper assessment' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed quarantined app Gatekeeper assessment' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed Info.plist package version' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed bundled Node runtime' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed bundled Node codesign' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed bundled Node dependencies' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed third-party notice' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'installed Node license' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'app quarantined Gatekeeper assessment' && check.status === 'pass'
  ) &&
  strictReleaseVerificationReport?.checks?.some(
    (check) => check.name === 'DMG quarantined Gatekeeper assessment' && check.status === 'pass'
  );

const preRetirementParity = run('node', [
  'scripts/evaluate-native-parity.cjs',
  '--pre-retirement'
]);
add(
  'Native pre-retirement parity',
  preRetirementParity.ok ? 'pass' : 'blocked',
  preRetirementParity.ok
    ? 'native parity passes when Electron presence is ignored'
    : 'native parity still has release blockers; run npm run native:parity:report'
);

const releaseReadiness = run('node', ['scripts/check-native-release-readiness.cjs']);
add(
  'Native release readiness',
  releaseReadiness.ok ? 'pass' : 'blocked',
  releaseReadiness.ok
    ? 'Developer ID signing and notarization preflight passed'
    : 'release signing/notarization is not ready; run npm run native:release:check'
);

add(
  'Strict release verification report',
  strictReleaseVerificationPassed ? 'pass' : 'blocked',
  strictReleaseVerificationPassed
      ? 'native/dist/release-verification-report.json passed strict source provenance, app, ZIP, DMG, quarantined Gatekeeper, bundled planner runtime/license, version metadata, notary-log, and installed-app verification'
    : 'strict release verification report is missing, not PASS, or lacks source provenance, bundled planner runtime/license, version metadata, notary-log, ZIP, quarantine, or installed-app Gatekeeper evidence; run npm run native:release'
);

const nativeSmoke = run('node', ['scripts/smoke-native-release.cjs']);
add(
  'Packaged native release smoke',
  nativeSmoke.ok ? 'pass' : 'blocked',
  nativeSmoke.ok
    ? 'packaged app, mounted DMG, and installed app smoke passed'
    : nativeSmoke.output || 'native release smoke failed'
);

const retirementPlan = run('node', ['scripts/plan-electron-retirement.cjs', '--no-checks']);
add(
  'Electron retirement dry-run plan',
  retirementPlan.ok ? 'pass' : 'blocked',
  retirementPlan.ok
    ? 'native/dist/electron-retirement-plan.json can be generated before deletion'
    : retirementPlan.output || 'retirement plan generation failed'
);

add(
  'Electron source footprint',
  existingElectronPaths.length === 0 ? 'pass' : 'blocked',
  existingElectronPaths.length === 0
    ? 'Electron source/test paths have been removed'
    : `Electron reference paths still present: ${existingElectronPaths.join(', ')}`
);
add(
  'Electron package dependencies',
  existingElectronDeps.length === 0 ? 'pass' : 'blocked',
  existingElectronDeps.length === 0
    ? 'Electron/React/Vite dependencies have been removed'
    : `Electron-era dependencies still present: ${existingElectronDeps.join(', ')}`
);
add(
  'Electron package scripts',
  electronScripts.length === 0 ? 'pass' : 'blocked',
  electronScripts.length === 0
    ? 'Electron package scripts have been removed'
    : `Electron-era scripts still present: ${electronScripts.join(', ')}`
);

const blocked = checks.filter((check) => check.status === 'blocked');
const status = blocked.length === 0 ? 'PASS' : 'BLOCKED';
const reportPath = options.reportPath || defaultReportPath;

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(
  reportPath,
  `${JSON.stringify(
    {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      kind: 'electron-retirement-readiness',
      status,
      summary: {
        checkCount: checks.length,
        passCount: checks.length - blocked.length,
        blockedCount: blocked.length
      },
      checks,
      electronFootprint: {
        paths: existingElectronPaths,
        dependencies: existingElectronDeps,
        scripts: electronScripts
      },
      strictReleaseVerification: {
        reportPath: 'native/dist/release-verification-report.json',
        passed: strictReleaseVerificationPassed
      }
    },
    null,
    2
  )}\n`
);

process.stdout.write(
  [
    '# Electron Retirement Readiness',
    `status ${status}`,
    `pass ${checks.length - blocked.length}`,
    `blocked ${blocked.length}`,
    `report ${path.relative(rootDir, reportPath)}`,
    ''
  ].join('\n')
);
for (const check of checks) {
  process.stdout.write(`- ${check.status.toUpperCase()} ${check.name}: ${check.detail}\n`);
}

if (blocked.length > 0) {
  process.stdout.write(
    [
      '',
      'Retirement sequence:',
      '1. Pass npm run native:release:check with Developer ID and notary credentials.',
      '2. Pass npm run native:release.',
      '3. Confirm native/dist/release-verification-report.json is strict PASS with source provenance, bundled planner runtime/license, version metadata, notary-log, app, ZIP, DMG, quarantine, and installed-app Gatekeeper evidence.',
      '4. Confirm native/dist/release-smoke-report.json is PASS for packaged, DMG, and installed app smoke.',
      '5. Pass npm run native:parity -- --pre-retirement.',
      '6. Run npm run native:retire:plan and review native/dist/electron-retirement-plan.json.',
      '7. Remove Electron source, tests, dependencies, and package scripts in one audited change.',
      '8. Re-run npm run native:retire:check.',
      ''
    ].join('\n')
  );
  process.exitCode = 1;
}
