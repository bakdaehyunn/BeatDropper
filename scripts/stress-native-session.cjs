#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const appPath = path.join(rootDir, 'native', 'dist', 'BeatDropper.app');
const executablePath = path.join(appPath, 'Contents', 'MacOS', 'BeatDropperNative');
const normalSessionTimeoutMs = 90_000;
const extendedSessionTimeoutMs = 120_000;

const parseArgs = (argv) => {
  const options = {
    extended: false,
    trackCount: null,
    transitionCount: null,
    writeJson: null,
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      options.help = true;
      continue;
    }
    if (arg === '--extended') {
      options.extended = true;
      continue;
    }
    if (arg.startsWith('--tracks=')) {
      options.trackCount = Number(arg.slice('--tracks='.length));
      continue;
    }
    if (arg.startsWith('--transitions=')) {
      options.transitionCount = Number(arg.slice('--transitions='.length));
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

const resolveCounts = (options) => {
  const trackCount = Number.isFinite(options.trackCount)
    ? Math.trunc(options.trackCount)
    : options.extended
      ? 12
      : 4;
  const transitionCount = Number.isFinite(options.transitionCount)
    ? Math.trunc(options.transitionCount)
    : options.extended
      ? 6
      : 1;
  return { trackCount, transitionCount };
};

const makeBaseReport = (status, options, counts) => ({
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  kind: 'session-stress',
  status,
  app: {
    path: relative(appPath),
    executablePath: relative(executablePath)
  },
  stress: {
    mode: options?.extended ? 'extended' : 'normal',
    extended: Boolean(options?.extended),
    trackCount: counts?.trackCount ?? null,
    transitionCount: counts?.transitionCount ?? null,
    timeoutMs: options?.extended ? extendedSessionTimeoutMs : normalSessionTimeoutMs
  }
});

const makeFailureReport = (error, options, counts) => ({
  ...makeBaseReport('FAIL', options, counts),
  error: error instanceof Error ? error.message : String(error)
});

const main = (options) => {
  if (options.help) {
    process.stdout.write(
      [
        'Usage: node scripts/stress-native-session.cjs [options]',
        '',
        'Runs the packaged native app through folder import, bounded DSP analysis, planner fallback, playback, and crossfade.',
        '',
        'Options:',
        '  --extended           Run a longer synthetic set with repeated transition planning/crossfades.',
        '  --tracks=<count>     Override synthetic track count for session stress.',
        '  --transitions=<n>    Override repeated transition count.',
        '  --write-json <path>  Write durable session stress evidence.',
        '  --help               Show this message.',
        '',
        'Run npm run native:package first.',
        ''
      ].join('\n')
    );
    return null;
  }

  assertFile(appPath, 'BeatDropper.app');
  assertFile(executablePath, 'BeatDropperNative executable');

  const codesign = run('codesign', ['--verify', '--deep', '--strict', appPath]);
  if (!codesign.ok) {
    throw new Error(codesign.output || 'codesign verification failed');
  }

  const counts = resolveCounts(options);
  const launched = run(executablePath, [], {
    timeout: options.extended ? extendedSessionTimeoutMs : normalSessionTimeoutMs,
    env: {
      ...process.env,
      BEATDROPPER_NATIVE_SESSION_STRESS: '1',
      BEATDROPPER_NATIVE_SESSION_STRESS_TRACKS: String(counts.trackCount),
      BEATDROPPER_NATIVE_SESSION_STRESS_TRANSITIONS: String(counts.transitionCount)
    }
  });
  if (!launched.ok) {
    throw new Error(
      launched.output || `native session stress failed with status ${launched.status ?? launched.signal}`
    );
  }
  if (/BEATDROPPER_NATIVE_SESSION_STRESS_FAILED/.test(launched.output)) {
    throw new Error(`native session stress reported failure:\n${launched.output}`);
  }

  const match = launched.output.match(
    /BEATDROPPER_NATIVE_SESSION_STRESS_READY imported=(\d+) analyzed=(\d+) maxRunning=(\d+) planConfidence=([0-9.]+) state=([^\s]+)/
  );
  if (!match) {
    throw new Error(`native app did not print session stress marker. Output:\n${launched.output}`);
  }

  const imported = Number(match[1]);
  const analyzed = Number(match[2]);
  const maxRunning = Number(match[3]);
  const planConfidence = Number(match[4]);
  const finalState = match[5];
  const transitionsMatch = launched.output.match(/\btransitions=(\d+)/);
  const transitions = transitionsMatch ? Number(transitionsMatch[1]) : 1;

  if (imported < counts.trackCount || analyzed < imported) {
    throw new Error(`native session stress did not analyze the imported folder. Output:\n${launched.output}`);
  }
  if (maxRunning < 1 || maxRunning > 4) {
    throw new Error(`native session stress reported invalid analysis concurrency ${maxRunning}. Output:\n${launched.output}`);
  }
  if (!Number.isFinite(planConfidence) || planConfidence <= 0) {
    throw new Error(`native session stress reported invalid planner confidence ${planConfidence}. Output:\n${launched.output}`);
  }
  if (finalState !== 'Idle') {
    throw new Error(`native session stress finished in unexpected state ${finalState}. Output:\n${launched.output}`);
  }
  if (transitions < Math.min(counts.transitionCount, imported - 1)) {
    throw new Error(`native session stress completed too few transitions (${transitions}). Output:\n${launched.output}`);
  }

  writeJsonReport(options.writeJson, {
    ...makeBaseReport('PASS', options, counts),
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
      imported,
      analyzed,
      maxRunning,
      planConfidence,
      transitions,
      finalState
    }
  });

  process.stdout.write(
    [
      options.extended
        ? 'BeatDropper native extended session stress passed.'
        : 'BeatDropper native session stress passed.',
      `imported ${imported}`,
      `analyzed ${analyzed}`,
      `max analysis concurrency ${maxRunning}`,
      `plan confidence ${planConfidence.toFixed(2)}`,
      `transitions ${transitions}`,
      `final state ${finalState}`
    ].join('\n') + '\n'
  );

  return counts;
};

let options;
let counts = null;
try {
  options = parseArgs(process.argv.slice(2));
  counts = resolveCounts(options);
  main(options);
} catch (error) {
  writeJsonReport(options?.writeJson, makeFailureReport(error, options, counts));
  fail(error instanceof Error ? error.message : String(error));
}
