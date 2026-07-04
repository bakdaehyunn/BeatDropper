#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const appPath = path.join(rootDir, 'native', 'dist', 'BeatDropper.app');
const executablePath = path.join(appPath, 'Contents', 'MacOS', 'BeatDropperNative');
const supportedExtensions = new Set(['.mp3', '.wav']);
const defaultTimeoutMs = 180_000;

const parseArgs = (argv) => {
  const options = {
    folder: null,
    writeJson: null,
    swiftRun: false,
    timeoutMs: defaultTimeoutMs,
    minDurationSec: 0,
    maxFiles: 0,
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      options.help = true;
      continue;
    }
    if (arg === '--swift-run') {
      options.swiftRun = true;
      continue;
    }
    if (arg === '--folder') {
      const next = argv[index + 1];
      if (!next) {
        throw new Error('--folder requires a path');
      }
      options.folder = next;
      index += 1;
      continue;
    }
    if (arg.startsWith('--folder=')) {
      options.folder = arg.slice('--folder='.length);
      if (!options.folder) {
        throw new Error('--folder requires a path');
      }
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
    if (arg.startsWith('--timeout-ms=')) {
      const value = Number(arg.slice('--timeout-ms='.length));
      if (!Number.isFinite(value) || value <= 0) {
        throw new Error('--timeout-ms requires a positive number');
      }
      options.timeoutMs = Math.trunc(value);
      continue;
    }
    if (arg.startsWith('--min-duration-sec=')) {
      const value = Number(arg.slice('--min-duration-sec='.length));
      if (!Number.isFinite(value) || value < 0) {
        throw new Error('--min-duration-sec requires a non-negative number');
      }
      options.minDurationSec = value;
      continue;
    }
    if (arg.startsWith('--max-files=')) {
      const value = Number(arg.slice('--max-files='.length));
      if (!Number.isFinite(value) || value < 0) {
        throw new Error('--max-files requires a non-negative number');
      }
      options.maxFiles = Math.trunc(value);
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
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
  if (lines.length <= 16) {
    return lines;
  }
  return [...lines.slice(0, 8), '...', ...lines.slice(-8)];
};

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

const fail = (message) => {
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
};

const hashPath = (folderPath) =>
  crypto.createHash('sha256').update(path.resolve(folderPath)).digest('hex').slice(0, 16);

const readDurationSec = (filePath) => {
  const result = spawnSync('afinfo', [filePath], { encoding: 'utf8' });
  if (result.status !== 0) {
    return null;
  }
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  const match = output.match(/estimated duration:\s*([0-9.]+)\s*sec/i);
  if (!match) {
    return null;
  }
  const durationSec = Number(match[1]);
  return Number.isFinite(durationSec) && durationSec >= 0 ? durationSec : null;
};

const collectSupportedFiles = (folderPath) => {
  const files = [];
  let directoryCount = 0;
  const stack = [folderPath];

  while (stack.length > 0) {
    const current = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (entry.name.startsWith('.')) {
        continue;
      }
      const childPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        directoryCount += 1;
        stack.push(childPath);
        continue;
      }
      if (entry.isFile() && supportedExtensions.has(path.extname(entry.name).toLowerCase())) {
        files.push(childPath);
      }
    }
  }

  files.sort();
  return { files, directoryCount };
};

const summarizeDurations = (durations) => {
  if (durations.length === 0) {
    return { count: 0, minSec: 0, maxSec: 0, avgSec: 0 };
  }
  const minSec = Math.min(...durations);
  const maxSec = Math.max(...durations);
  const avgSec = durations.reduce((sum, value) => sum + value, 0) / durations.length;
  return {
    count: durations.length,
    minSec: Number(minSec.toFixed(3)),
    maxSec: Number(maxSec.toFixed(3)),
    avgSec: Number(avgSec.toFixed(3))
  };
};

const stageCorpus = (files) => {
  const stageRoot = fs.mkdtempSync(path.join(fs.realpathSync(require('node:os').tmpdir()), 'beatdropper-real-corpus-'));
  files.forEach((filePath, index) => {
    const extension = path.extname(filePath).toLowerCase();
    const stagedPath = path.join(stageRoot, `track-${String(index + 1).padStart(4, '0')}${extension}`);
    try {
      fs.linkSync(filePath, stagedPath);
    } catch {
      fs.copyFileSync(filePath, stagedPath);
    }
  });
  return {
    folderPath: stageRoot,
    cleanup: () => fs.rmSync(stageRoot, { recursive: true, force: true })
  };
};

const prepareValidationFolder = (folderPath, options) => {
  const collected = collectSupportedFiles(folderPath);
  const durationRecords = collected.files.map((filePath) => ({
    filePath,
    durationSec: options.minDurationSec > 0 ? readDurationSec(filePath) : null
  }));
  let selected = durationRecords;
  if (options.minDurationSec > 0) {
    selected = selected.filter((record) => record.durationSec !== null && record.durationSec >= options.minDurationSec);
  }
  if (options.maxFiles > 0) {
    selected = selected.slice(0, options.maxFiles);
  }
  const durations = selected
    .map((record) => record.durationSec)
    .filter((durationSec) => Number.isFinite(durationSec));
  const shouldStage = selected.length >= 2 && (options.minDurationSec > 0 || options.maxFiles > 0);
  const staged = shouldStage ? stageCorpus(selected.map((record) => record.filePath)) : null;

  return {
    appFolderPath: staged?.folderPath ?? folderPath,
    cleanup: staged?.cleanup ?? (() => {}),
    info: {
      pathHash: hashPath(folderPath),
      pathProvided: true,
      supportedFileCount: collected.files.length,
      directoryCount: collected.directoryCount,
      selectedFileCount: selected.length,
      minDurationSec: options.minDurationSec,
      durationSummary: summarizeDurations(durations),
      staged: Boolean(staged),
      stagedPathHash: staged ? hashPath(staged.folderPath) : null
    }
  };
};

const makeBaseReport = (status, options, folderInfo = null) => ({
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  kind: 'real-folder-validation',
  status,
  app: {
    mode: options?.swiftRun ? 'swift-run' : 'packaged-app',
    path: path.relative(rootDir, appPath),
    executablePath: path.relative(rootDir, executablePath)
  },
  folder: folderInfo,
  stress: {
    timeoutMs: options?.timeoutMs ?? defaultTimeoutMs,
    analysisTimeoutSec: Math.max(30, Math.floor((options?.timeoutMs ?? defaultTimeoutMs) / 1000) - 20),
    supportedExtensions: [...supportedExtensions].map((extension) => extension.slice(1))
  }
});

const makeFailureReport = (error, options, folderInfo = null) => ({
  ...makeBaseReport('FAIL', options, folderInfo),
  error: error instanceof Error ? error.message : String(error)
});

const parseReadyMarker = (output) => {
  const markerLine = String(output || '')
    .split('\n')
    .find((line) => line.startsWith('BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION_READY '));
  if (!markerLine) {
    return null;
  }
  const raw = {};
  for (const token of markerLine.split(/\s+/).slice(1)) {
    const separatorIndex = token.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    raw[token.slice(0, separatorIndex)] = token.slice(separatorIndex + 1);
  }
  const numberValue = (key) => {
    const value = Number(raw[key]);
    return Number.isFinite(value) ? value : 0;
  };
  return {
    imported: numberValue('imported'),
    analyzed: numberValue('analyzed'),
    sourceFolders: numberValue('sourceFolders'),
    maxRunning: numberValue('maxRunning'),
    planConfidence: numberValue('planConfidence'),
    planSource: raw.planSource || 'unknown',
    phraseAlignment: raw.phraseAlignment || 'unknown',
    tempoSync: raw.tempoSync === 'true',
    evidenceCount: numberValue('evidenceCount'),
    keyAvailable: numberValue('keyAvailable'),
    keyStrong: numberValue('keyStrong'),
    keyPartial: numberValue('keyPartial'),
    keyFallback: numberValue('keyFallback'),
    keyLowConfidence: numberValue('keyLowConfidence'),
    keyUnavailable: numberValue('keyUnavailable'),
    keyConfidenceAvg: numberValue('keyConfidenceAvg'),
    keyConfidenceMin: numberValue('keyConfidenceMin'),
    loudnessAvailable: numberValue('loudnessAvailable'),
    loudnessStrong: numberValue('loudnessStrong'),
    loudnessPartial: numberValue('loudnessPartial'),
    loudnessFallback: numberValue('loudnessFallback'),
    loudnessLowConfidence: numberValue('loudnessLowConfidence'),
    headroomLow: numberValue('headroomLow'),
    rmsAvgDb: numberValue('rmsAvgDb'),
    rmsMinDb: numberValue('rmsMinDb'),
    rmsMaxDb: numberValue('rmsMaxDb'),
    lufsAvg: numberValue('lufsAvg'),
    lufsMin: numberValue('lufsMin'),
    lufsMax: numberValue('lufsMax'),
    peakMaxDb: numberValue('peakMaxDb'),
    truePeakMaxDb: numberValue('truePeakMaxDb'),
    headroomMinDb: numberValue('headroomMinDb'),
    loudnessRangeAvgLU: numberValue('loudnessRangeAvgLU'),
    dynamicRangeAvgDb: numberValue('dynamicRangeAvgDb'),
    stereoAvailable: numberValue('stereoAvailable'),
    stereoTracks: numberValue('stereoTracks'),
    channelCountMax: numberValue('channelCountMax'),
    stereoWidthAvg: numberValue('stereoWidthAvg'),
    phaseCorrelationAvg: numberValue('phaseCorrelationAvg'),
    midSideBalanceAvg: numberValue('midSideBalanceAvg'),
    finalState: raw.state || 'unknown'
  };
};

const main = (options) => {
  if (options.help) {
    process.stdout.write(
      [
        'Usage: node scripts/validate-native-real-folder.cjs --folder <path> [options]',
        '',
        'Runs the native app through a local real-track folder import, analysis queue drain, and one planner request.',
        'The report records counts and planner evidence categories only; it does not print track names or upload audio.',
        '',
        'Options:',
        '  --folder <path>       Local folder containing .mp3 or .wav files.',
        '  --write-json <path>   Write durable real-folder validation evidence.',
        '  --swift-run           Run through swift run instead of the packaged app; avoids packaging/signing.',
        '  --timeout-ms=<n>      Override app automation timeout. Default: 180000.',
        '  --min-duration-sec=<n> Stage only supported files at least this long using anonymized names.',
        '  --max-files=<n>        Stage at most this many selected files. Default: no cap.',
        '  --help                Show this message.',
        '',
        'Run npm run native:package first for packaged-app mode after changing the native app.',
        ''
      ].join('\n')
    );
    return;
  }

  if (!options.folder) {
    throw new Error('--folder is required');
  }

  const folderPath = path.resolve(options.folder);
  const folderInfo = {
    pathHash: hashPath(folderPath),
    pathProvided: true,
    supportedFileCount: 0,
    directoryCount: 0
  };

  if (!fs.existsSync(folderPath) || !fs.statSync(folderPath).isDirectory()) {
    throw new Error('folder does not exist or is not a directory');
  }

  const prepared = prepareValidationFolder(folderPath, options);
  Object.assign(folderInfo, prepared.info);
  if (folderInfo.selectedFileCount < 2) {
    throw new Error(`folder must contain at least two selected supported audio files; found ${folderInfo.selectedFileCount}`);
  }

  let codesign = null;
  let command = executablePath;
  let args = [];
  if (options.swiftRun) {
    command = 'swift';
    args = ['run', '--package-path', 'native', 'BeatDropperNative'];
  } else {
    if (!fs.existsSync(appPath)) {
      throw new Error(`BeatDropper.app missing: ${appPath}`);
    }
    if (!fs.existsSync(executablePath)) {
      throw new Error(`BeatDropperNative executable missing: ${executablePath}`);
    }
    codesign = run('codesign', ['--verify', '--deep', '--strict', appPath]);
    if (!codesign.ok) {
      throw new Error(codesign.output || 'codesign verification failed');
    }
  }

  let launched;
  try {
    launched = run(command, args, {
      timeout: options.timeoutMs,
      env: {
        ...process.env,
        BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION: '1',
        BEATDROPPER_NATIVE_REAL_FOLDER_PATH: prepared.appFolderPath,
        BEATDROPPER_NATIVE_REAL_FOLDER_ANALYSIS_TIMEOUT_SEC: String(
          Math.max(30, Math.floor(options.timeoutMs / 1000) - 20)
        )
      }
    });
  } finally {
    prepared.cleanup();
  }
  if (!launched.ok) {
    throw new Error(
      launched.output || `native real-folder validation failed with status ${launched.status ?? launched.signal}`
    );
  }
  if (/BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION_FAILED/.test(launched.output)) {
    throw new Error(`native real-folder validation reported failure:\n${launched.output}`);
  }

  const result = parseReadyMarker(launched.output);
  if (!result) {
    throw new Error(`native app did not print real-folder validation marker. Output:\n${launched.output}`);
  }
  if (result.imported < 2 || result.analyzed < result.imported || result.sourceFolders !== 1) {
    throw new Error(`native real-folder validation returned unexpected counts. Output:\n${launched.output}`);
  }
  if (!Number.isFinite(result.planConfidence) || result.planConfidence <= 0) {
    throw new Error(`native real-folder validation returned invalid planner confidence. Output:\n${launched.output}`);
  }
  if (result.finalState !== 'Idle') {
    throw new Error(`native real-folder validation finished in unexpected state ${result.finalState}`);
  }

  writeJsonReport(options.writeJson, {
    ...makeBaseReport('PASS', options, folderInfo),
    codesign: codesign
      ? {
          ok: codesign.ok,
          status: codesign.status,
          signal: codesign.signal,
          outputPreview: compactOutput(codesign.output)
        }
      : {
          skipped: true,
          reason: '--swift-run mode avoids packaging/signing'
        },
    launch: {
      ok: launched.ok,
      status: launched.status,
      signal: launched.signal,
      outputPreview: compactOutput(launched.output)
    },
    result
  });

  process.stdout.write(
    [
      'BeatDropper native real-folder validation passed.',
      `supported files ${folderInfo.supportedFileCount}`,
      `selected files ${folderInfo.selectedFileCount}`,
      `imported ${result.imported}`,
      `analyzed ${result.analyzed}`,
      `max analysis concurrency ${result.maxRunning}`,
      `plan confidence ${result.planConfidence.toFixed(2)}`,
      `plan source ${result.planSource}`,
      `phrase alignment ${result.phraseAlignment}`,
      `tempo sync ${result.tempoSync ? 'true' : 'false'}`,
      `key evidence ${result.keyAvailable}/${result.analyzed} available, avg confidence ${result.keyConfidenceAvg.toFixed(3)}`,
      `loudness evidence ${result.loudnessAvailable}/${result.analyzed} available, avg RMS ${result.rmsAvgDb.toFixed(2)} dB`,
      `LUFS evidence avg ${result.lufsAvg.toFixed(2)} LUFS, range avg ${result.loudnessRangeAvgLU.toFixed(2)} LU, true peak max ${result.truePeakMaxDb.toFixed(2)} dBTP`,
      `stereo evidence ${result.stereoAvailable}/${result.analyzed} available, stereo tracks ${result.stereoTracks}, avg width ${result.stereoWidthAvg.toFixed(3)}, avg phase ${result.phaseCorrelationAvg.toFixed(3)}`,
      `headroom low ${result.headroomLow}`,
      `final state ${result.finalState}`
    ].join('\n') + '\n'
  );
};

let options;
let folderInfo = null;
try {
  options = parseArgs(process.argv.slice(2));
  if (options.folder) {
    const folderPath = path.resolve(options.folder);
    folderInfo = {
      pathHash: hashPath(folderPath),
      pathProvided: true
    };
  }
  main(options);
} catch (error) {
  writeJsonReport(options?.writeJson, makeFailureReport(error, options, folderInfo));
  fail(error instanceof Error ? error.message : String(error));
}
