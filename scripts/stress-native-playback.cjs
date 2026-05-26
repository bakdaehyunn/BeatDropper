#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const appPath = path.join(rootDir, 'native', 'dist', 'BeatDropper.app');
const executablePath = path.join(appPath, 'Contents', 'MacOS', 'BeatDropperNative');
const playbackTimeoutMs = 15_000;

const parseArgs = (argv) => {
  const options = {
    writeJson: null,
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
      options.writeJson = next;
      index += 1;
      continue;
    }
    if (arg.startsWith('--write-json=')) {
      options.writeJson = arg.slice('--write-json='.length);
      if (!options.writeJson) {
        throw new Error('--write-json requires a report path');
      }
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
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

const compactOutput = (output) => {
  const lines = String(output || '').split('\n').filter(Boolean);
  if (lines.length <= 12) {
    return lines;
  }
  return [...lines.slice(0, 6), '...', ...lines.slice(-6)];
};

const relative = (targetPath) => path.relative(rootDir, targetPath);

const resolveReportPath = (reportPath) => (
  path.isAbsolute(reportPath) ? reportPath : path.join(rootDir, reportPath)
);

const writeJsonReport = (reportPath, report) => {
  if (!reportPath) {
    return;
  }
  const resolved = resolveReportPath(reportPath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, `${JSON.stringify(report, null, 2)}\n`);
};

const makeBaseReport = (status) => ({
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  kind: 'playback-stress',
  status,
  app: {
    path: relative(appPath),
    executablePath: relative(executablePath)
  },
  stress: {
    timeoutMs: playbackTimeoutMs
  }
});

const makeFailureReport = (error) => ({
  ...makeBaseReport('FAIL'),
  error: error instanceof Error ? error.message : String(error)
});

const main = (options) => {
  if (options.help) {
    process.stdout.write(
      [
        'Usage: node scripts/stress-native-playback.cjs [options]',
        '',
        'Runs the packaged native app in playback stress mode.',
        '',
        'Options:',
        '  --write-json <path>  Write durable playback stress evidence.',
        '  --help               Show this message.',
        '',
        'Run npm run native:package first.',
        ''
      ].join('\n')
    );
    return;
  }

  assertFile(appPath, 'BeatDropper.app');
  assertFile(executablePath, 'BeatDropperNative executable');

  const codesign = run('codesign', ['--verify', '--deep', '--strict', appPath]);
  if (!codesign.ok) {
    throw new Error(codesign.output || 'codesign verification failed');
  }

  const launched = run(executablePath, [], {
    timeout: playbackTimeoutMs,
    env: {
      ...process.env,
      BEATDROPPER_NATIVE_PLAYBACK_STRESS: '1'
    }
  });
  if (!launched.ok) {
    throw new Error(
      launched.output || `native playback stress failed with status ${launched.status ?? launched.signal}`
    );
  }
  if (/BEATDROPPER_NATIVE_PLAYBACK_STRESS_FAILED/.test(launched.output)) {
    throw new Error(`native playback stress reported failure:\n${launched.output}`);
  }

  const match = launched.output.match(/BEATDROPPER_NATIVE_PLAYBACK_STRESS_READY state=([^\s]+)/);
  if (!match) {
    throw new Error(`native app did not print playback stress marker. Output:\n${launched.output}`);
  }
  if (match[1] !== 'Idle') {
    throw new Error(`native playback stress finished in unexpected state ${match[1]}. Output:\n${launched.output}`);
  }

  writeJsonReport(options.writeJson, {
    ...makeBaseReport('PASS'),
    codesign: {
      ok: codesign.ok,
      status: codesign.status,
      signal: codesign.signal,
      outputPreview: compactOutput(codesign.output)
    },
    launch: {
      ok: launched.ok,
      status: launched.status,
      signal: launched.signal,
      outputPreview: compactOutput(launched.output)
    },
    result: {
      finalState: match[1]
    }
  });

  process.stdout.write(
    [
      'BeatDropper native playback stress passed.',
      `final state ${match[1]}`
    ].join('\n') + '\n'
  );
};

let options;
try {
  options = parseArgs(process.argv.slice(2));
  main(options);
} catch (error) {
  writeJsonReport(options?.writeJson, makeFailureReport(error));
  fail(error instanceof Error ? error.message : String(error));
}
