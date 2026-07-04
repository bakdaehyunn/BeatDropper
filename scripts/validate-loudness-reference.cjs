#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const supportedExtensions = new Set(['.mp3', '.wav']);
const calibratedLufsTolerance = 3.9;
const calibratedTruePeakTolerance = 2.6;

const parseArgs = (argv) => {
  const options = {
    audioFile: null,
    analysisFile: null,
    folder: null,
    writeJson: 'native/dist/loudness-reference-validation-report.json',
    timeoutMs: 120_000,
    nativeTimeoutMs: 300_000,
    lufsTolerance: calibratedLufsTolerance,
    truePeakTolerance: calibratedTruePeakTolerance,
    minDurationSec: 0,
    maxFiles: 0,
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const readValue = (name) => {
      const next = argv[index + 1];
      if (!next) {
        throw new Error(`${name} requires a value`);
      }
      index += 1;
      return next;
    };

    if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else if (arg === '--audio-file') {
      options.audioFile = readValue('--audio-file');
    } else if (arg.startsWith('--audio-file=')) {
      options.audioFile = arg.slice('--audio-file='.length);
    } else if (arg === '--analysis-file') {
      options.analysisFile = readValue('--analysis-file');
    } else if (arg.startsWith('--analysis-file=')) {
      options.analysisFile = arg.slice('--analysis-file='.length);
    } else if (arg === '--folder') {
      options.folder = readValue('--folder');
    } else if (arg.startsWith('--folder=')) {
      options.folder = arg.slice('--folder='.length);
    } else if (arg === '--write-json') {
      options.writeJson = readValue('--write-json');
    } else if (arg.startsWith('--write-json=')) {
      options.writeJson = arg.slice('--write-json='.length);
    } else if (arg.startsWith('--timeout-ms=')) {
      options.timeoutMs = positiveNumber(arg.slice('--timeout-ms='.length), '--timeout-ms');
    } else if (arg.startsWith('--native-timeout-ms=')) {
      options.nativeTimeoutMs = positiveNumber(arg.slice('--native-timeout-ms='.length), '--native-timeout-ms');
    } else if (arg.startsWith('--lufs-tolerance=')) {
      options.lufsTolerance = positiveNumber(arg.slice('--lufs-tolerance='.length), '--lufs-tolerance');
    } else if (arg.startsWith('--true-peak-tolerance=')) {
      options.truePeakTolerance = positiveNumber(arg.slice('--true-peak-tolerance='.length), '--true-peak-tolerance');
    } else if (arg.startsWith('--min-duration-sec=')) {
      options.minDurationSec = nonNegativeNumber(arg.slice('--min-duration-sec='.length), '--min-duration-sec');
    } else if (arg.startsWith('--max-files=')) {
      options.maxFiles = Math.trunc(nonNegativeNumber(arg.slice('--max-files='.length), '--max-files'));
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
};

const positiveNumber = (value, name) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${name} requires a positive number`);
  }
  return parsed;
};

const nonNegativeNumber = (value, name) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`${name} requires a non-negative number`);
  }
  return parsed;
};

const usage = () => `Usage:
  npm run native:validate:loudness-reference -- --audio-file <local-audio> --analysis-file <track-analysis-json>
  npm run native:validate:loudness-reference -- --folder <local-audio-folder> --min-duration-sec=30 --max-files=8

Compares BeatDropper integrated LUFS and true peak against ffmpeg loudnorm locally.
Reports only anonymized file hashes; it does not upload audio or print private paths.`;

const resolveReportPath = (reportPath) => (
  path.isAbsolute(reportPath) ? reportPath : path.join(rootDir, reportPath)
);

const writeJsonReport = (reportPath, report) => {
  if (!reportPath) {
    return;
  }
  const resolved = resolveReportPath(reportPath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
};

const anonymizedPathHash = (filePath) =>
  crypto.createHash('sha256').update(path.resolve(filePath)).digest('hex').slice(0, 16);

const hashPath = anonymizedPathHash;

const toolAvailable = (command) => {
  const result = spawnSync(command, ['-version'], { encoding: 'utf8' });
  return result.status === 0;
};

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
      } else if (entry.isFile() && supportedExtensions.has(path.extname(entry.name).toLowerCase())) {
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

const stageCorpus = (records) => {
  const stageRoot = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'beatdropper-loudness-corpus-'));
  const stagedRecords = records.map((record, index) => {
    const extension = path.extname(record.filePath).toLowerCase();
    const anonymizedName = `track-${String(index + 1).padStart(4, '0')}${extension}`;
    const stagedPath = path.join(stageRoot, anonymizedName);
    try {
      fs.linkSync(record.filePath, stagedPath);
    } catch {
      fs.copyFileSync(record.filePath, stagedPath);
    }
    return {
      anonymizedName,
      stagedPath,
      originalPathHash: hashPath(record.filePath),
      durationSec: record.durationSec
    };
  });
  return {
    folderPath: stageRoot,
    records: stagedRecords,
    cleanup: () => fs.rmSync(stageRoot, { recursive: true, force: true })
  };
};

const prepareFolderCorpus = (folderPath, options) => {
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
  const staged = stageCorpus(selected);
  return {
    staged,
    info: {
      pathHash: hashPath(folderPath),
      pathProvided: true,
      supportedFileCount: collected.files.length,
      directoryCount: collected.directoryCount,
      selectedFileCount: selected.length,
      minDurationSec: options.minDurationSec,
      maxFiles: options.maxFiles,
      durationSummary: summarizeDurations(durations),
      staged: true,
      stagedPathHash: hashPath(staged.folderPath)
    }
  };
};

const readAnalysis = (analysisFile) => {
  if (!analysisFile) {
    return { error: 'analysis_file_required' };
  }
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(analysisFile, 'utf8'));
  } catch {
    return { error: 'analysis_file_unreadable' };
  }

  const candidates = [
    parsed?.loudness,
    parsed?.analysis?.loudness,
    parsed?.trackAnalysis?.loudness,
    parsed?.result?.analysis?.loudness
  ].filter(Boolean);
  const loudness = candidates.find((candidate) =>
    Number.isFinite(candidate?.integratedLUFS) && Number.isFinite(candidate?.truePeakDb)
  );
  if (!loudness) {
    return { error: 'analysis_loudness_missing' };
  }
  return {
    integratedLUFS: loudness.integratedLUFS,
    truePeakDb: loudness.truePeakDb,
    measurement: typeof loudness.measurement === 'string' ? loudness.measurement : null
  };
};

const parseLoudnormJson = (output) => {
  const text = String(output || '');
  const start = text.lastIndexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  try {
    const parsed = JSON.parse(text.slice(start, end + 1));
    const integratedLUFS = Number(parsed.input_i);
    const truePeakDb = Number(parsed.input_tp);
    if (!Number.isFinite(integratedLUFS) || !Number.isFinite(truePeakDb)) {
      return null;
    }
    return {
      integratedLUFS,
      truePeakDb,
      loudnessRangeLU: Number.isFinite(Number(parsed.input_lra)) ? Number(parsed.input_lra) : null,
      thresholdLUFS: Number.isFinite(Number(parsed.input_thresh)) ? Number(parsed.input_thresh) : null
    };
  } catch {
    return null;
  }
};

const runFfmpegLoudnorm = (audioFile, timeoutMs) => {
  const result = spawnSync(
    'ffmpeg',
    [
      '-hide_banner',
      '-nostats',
      '-i',
      audioFile,
      '-af',
      'loudnorm=I=-14:LRA=11:TP=-1:print_format=json',
      '-f',
      'null',
      '-'
    ],
    {
      cwd: rootDir,
      encoding: 'utf8',
      timeout: timeoutMs,
      maxBuffer: 1024 * 1024 * 8
    }
  );
  return {
    status: result.status,
    signal: result.signal,
    timedOut: result.error?.code === 'ETIMEDOUT',
    output: `${result.stdout || ''}\n${result.stderr || ''}`
  };
};

const compare = (reference, beatdropper, options) => {
  const integratedLUFSDiff = Math.abs(reference.integratedLUFS - beatdropper.integratedLUFS);
  const truePeakDiff = Math.abs(reference.truePeakDb - beatdropper.truePeakDb);
  const checks = [
    {
      metric: 'integratedLUFS',
      reference: reference.integratedLUFS,
      beatdropper: beatdropper.integratedLUFS,
      delta: Number(integratedLUFSDiff.toFixed(3)),
      tolerance: options.lufsTolerance,
      pass: integratedLUFSDiff <= options.lufsTolerance
    },
    {
      metric: 'truePeakDb',
      reference: reference.truePeakDb,
      beatdropper: beatdropper.truePeakDb,
      delta: Number(truePeakDiff.toFixed(3)),
      tolerance: options.truePeakTolerance,
      pass: truePeakDiff <= options.truePeakTolerance
    }
  ];
  return {
    status: checks.every((check) => check.pass) ? 'PASS' : 'FAIL',
    checks
  };
};

const runNativeLoudnessAnalysis = (folderPath, writeJsonPath, timeoutMs) => {
  const result = spawnSync(
    'swift',
    [
      'run',
      '--package-path',
      'native',
      'BeatDropperNativeLoudnessValidation',
      '--folder',
      folderPath,
      '--write-json',
      writeJsonPath
    ],
    {
      cwd: rootDir,
      encoding: 'utf8',
      timeout: timeoutMs,
      maxBuffer: 1024 * 1024 * 8
    }
  );
  return {
    ok: result.status === 0,
    status: result.status,
    signal: result.signal,
    timedOut: result.error?.code === 'ETIMEDOUT',
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const readNativeLoudnessReport = (reportPath) => {
  try {
    return JSON.parse(fs.readFileSync(reportPath, 'utf8'));
  } catch {
    return null;
  }
};

const percentile = (values, percentileValue) => {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length === 0) {
    return null;
  }
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil((percentileValue / 100) * sorted.length) - 1)
  );
  return sorted[index];
};

const summarizeDelta = (values) => {
  const finite = values.filter(Number.isFinite);
  if (finite.length === 0) {
    return { count: 0, avg: null, max: null, p95: null };
  }
  const avg = finite.reduce((sum, value) => sum + value, 0) / finite.length;
  return {
    count: finite.length,
    avg: Number(avg.toFixed(3)),
    max: Number(Math.max(...finite).toFixed(3)),
    p95: Number(percentile(finite, 95).toFixed(3))
  };
};

const roundTolerance = (value) => Number((Math.ceil(value * 10) / 10).toFixed(1));

const recommendedTolerance = (summary, floor, margin) => {
  if (!Number.isFinite(summary?.p95)) {
    return floor;
  }
  return roundTolerance(Math.max(floor, summary.p95 + margin));
};

const runFolderValidation = (options, baseReport) => {
  const folderPath = path.resolve(options.folder);
  if (!fs.existsSync(folderPath) || !fs.statSync(folderPath).isDirectory()) {
    const report = {
      ...baseReport,
      status: 'FAIL',
      reason: 'folder_unreadable',
      folder: {
        pathHash: hashPath(folderPath),
        pathProvided: true
      }
    };
    writeJsonReport(options.writeJson, report);
    process.stderr.write('Loudness reference validation failed: folder is not readable.\n');
    process.exitCode = 1;
    return;
  }

  const prepared = prepareFolderCorpus(folderPath, options);
  const folder = prepared.info;
  if (folder.selectedFileCount === 0) {
    const report = {
      ...baseReport,
      status: 'BLOCKED',
      reason: 'no_selected_audio_files',
      folder
    };
    writeJsonReport(options.writeJson, report);
    prepared.staged.cleanup();
    process.stdout.write('Loudness reference validation BLOCKED: no selected supported audio files.\n');
    return;
  }

  if (!toolAvailable('ffmpeg')) {
    const report = {
      ...baseReport,
      status: 'BLOCKED',
      reason: 'ffmpeg_not_found',
      requiredTool: 'ffmpeg with loudnorm filter',
      folder
    };
    writeJsonReport(options.writeJson, report);
    prepared.staged.cleanup();
    process.stdout.write('Loudness reference validation BLOCKED: ffmpeg with loudnorm is not installed.\n');
    return;
  }

  const nativeReportPath = path.join(prepared.staged.folderPath, 'beatdropper-native-loudness.json');
  try {
    const native = runNativeLoudnessAnalysis(prepared.staged.folderPath, nativeReportPath, options.nativeTimeoutMs);
    if (!native.ok) {
      const report = {
        ...baseReport,
        status: 'BLOCKED',
        reason: native.timedOut ? 'native_loudness_timeout' : 'native_loudness_analysis_failed',
        folder,
        nativeStatus: native.status,
        nativeSignal: native.signal
      };
      writeJsonReport(options.writeJson, report);
      process.stdout.write(`Loudness reference validation BLOCKED: ${report.reason}.\n`);
      return;
    }

    const nativeReport = readNativeLoudnessReport(nativeReportPath);
    const nativeRecords = Array.isArray(nativeReport?.records) ? nativeReport.records : [];
    const stagedByName = new Map(prepared.staged.records.map((record) => [record.anonymizedName, record]));
    const comparisons = [];
    for (const record of nativeRecords) {
      const staged = stagedByName.get(record.anonymizedName);
      const beatdropper = record.loudness;
      if (
        !staged ||
        !Number.isFinite(beatdropper?.integratedLUFS) ||
        !Number.isFinite(beatdropper?.truePeakDb)
      ) {
        comparisons.push({
          anonymizedName: record.anonymizedName,
          originalPathHash: staged?.originalPathHash ?? null,
          status: 'BLOCKED',
          reason: 'beatdropper_loudness_missing'
        });
        continue;
      }
      const ffmpeg = runFfmpegLoudnorm(staged.stagedPath, options.timeoutMs);
      const reference = parseLoudnormJson(ffmpeg.output);
      if (ffmpeg.status !== 0 || ffmpeg.timedOut || !reference) {
        comparisons.push({
          anonymizedName: record.anonymizedName,
          originalPathHash: staged.originalPathHash,
          status: 'BLOCKED',
          reason: ffmpeg.timedOut ? 'ffmpeg_timeout' : 'ffmpeg_loudnorm_unreadable',
          ffmpegStatus: ffmpeg.status,
          ffmpegSignal: ffmpeg.signal
        });
        continue;
      }
      const result = compare(reference, beatdropper, options);
      comparisons.push({
        anonymizedName: record.anonymizedName,
        originalPathHash: staged.originalPathHash,
        status: result.status,
        durationSec: record.durationSec,
        beatdropper: {
          integratedLUFS: beatdropper.integratedLUFS,
          truePeakDb: beatdropper.truePeakDb,
          measurement: beatdropper.measurement
        },
        reference,
        checks: result.checks
      });
    }

    const compared = comparisons.filter((record) => record.status === 'PASS' || record.status === 'FAIL');
    const lufsDelta = summarizeDelta(compared.map((record) =>
      record.checks.find((check) => check.metric === 'integratedLUFS')?.delta
    ));
    const truePeakDelta = summarizeDelta(compared.map((record) =>
      record.checks.find((check) => check.metric === 'truePeakDb')?.delta
    ));
    const blockedCount = comparisons.filter((record) => record.status === 'BLOCKED').length;
    const failedCount = comparisons.filter((record) => record.status === 'FAIL').length;
    const report = {
      ...baseReport,
      status: compared.length === 0 ? 'BLOCKED' : failedCount === 0 && blockedCount === 0 ? 'PASS' : 'FAIL',
      reason: compared.length === 0 ? 'no_reference_comparisons_completed' : undefined,
      folder,
      nativeAnalysis: {
        status: nativeReport?.status ?? 'unknown',
        recordCount: nativeRecords.length
      },
      summary: {
        selected: folder.selectedFileCount,
        compared: compared.length,
        passed: comparisons.filter((record) => record.status === 'PASS').length,
        failed: failedCount,
        blocked: blockedCount,
        integratedLUFSDeltas: lufsDelta,
        truePeakDeltas: truePeakDelta
      },
      recommendedTolerances: {
        method: 'ceil(max(existing floor, p95 observed delta + margin) to nearest 0.1)',
        integratedLUFS: recommendedTolerance(lufsDelta, options.lufsTolerance, 0.1),
        truePeakDb: recommendedTolerance(truePeakDelta, options.truePeakTolerance, 0.1),
        inputs: {
          integratedLUFSFloor: options.lufsTolerance,
          truePeakDbFloor: options.truePeakTolerance,
          margin: 0.1
        }
      },
      comparisons
    };
    writeJsonReport(options.writeJson, report);
    process.stdout.write(
      [
        `Loudness reference validation ${report.status}: compared ${compared.length}/${folder.selectedFileCount}.`,
        `LUFS delta avg ${lufsDelta.avg ?? '--'}, p95 ${lufsDelta.p95 ?? '--'}, max ${lufsDelta.max ?? '--'}.`,
        `True peak delta avg ${truePeakDelta.avg ?? '--'}, p95 ${truePeakDelta.p95 ?? '--'}, max ${truePeakDelta.max ?? '--'}.`,
        `Recommended tolerances LUFS ${report.recommendedTolerances.integratedLUFS}, true peak ${report.recommendedTolerances.truePeakDb}.`
      ].join('\n') + '\n'
    );
    if (report.status === 'FAIL') {
      process.exitCode = 1;
    }
  } finally {
    prepared.staged.cleanup();
  }
};

const main = () => {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }

  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  const baseReport = {
    generatedAt: new Date().toISOString(),
    referenceTool: 'ffmpeg loudnorm',
    privacy: 'Audio paths are hashed and audio never leaves the local machine.',
    tolerances: {
      integratedLUFS: options.lufsTolerance,
      truePeakDb: options.truePeakTolerance
    }
  };

  if (options.folder) {
    runFolderValidation(options, baseReport);
    return;
  }

  if (!toolAvailable('ffmpeg')) {
    const report = {
      ...baseReport,
      status: 'BLOCKED',
      reason: 'ffmpeg_not_found',
      requiredTool: 'ffmpeg with loudnorm filter'
    };
    writeJsonReport(options.writeJson, report);
    process.stdout.write('Loudness reference validation BLOCKED: ffmpeg with loudnorm is not installed.\n');
    return;
  }

  if (!options.audioFile) {
    const report = { ...baseReport, status: 'BLOCKED', reason: 'audio_file_required' };
    writeJsonReport(options.writeJson, report);
    process.stdout.write('Loudness reference validation BLOCKED: provide --audio-file.\n');
    return;
  }

  if (!fs.existsSync(options.audioFile)) {
    const report = {
      ...baseReport,
      status: 'FAIL',
      reason: 'audio_file_unreadable',
      audioFileHash: anonymizedPathHash(options.audioFile)
    };
    writeJsonReport(options.writeJson, report);
    process.stderr.write('Loudness reference validation failed: audio file is not readable.\n');
    process.exitCode = 1;
    return;
  }

  const beatdropper = readAnalysis(options.analysisFile);
  if (beatdropper.error) {
    const report = {
      ...baseReport,
      status: 'BLOCKED',
      reason: beatdropper.error,
      audioFileHash: anonymizedPathHash(options.audioFile),
      analysisFileHash: options.analysisFile ? anonymizedPathHash(options.analysisFile) : null
    };
    writeJsonReport(options.writeJson, report);
    process.stdout.write(`Loudness reference validation BLOCKED: ${beatdropper.error}.\n`);
    return;
  }

  const ffmpeg = runFfmpegLoudnorm(options.audioFile, options.timeoutMs);
  const reference = parseLoudnormJson(ffmpeg.output);
  if (ffmpeg.status !== 0 || ffmpeg.timedOut || !reference) {
    const report = {
      ...baseReport,
      status: 'BLOCKED',
      reason: ffmpeg.timedOut ? 'ffmpeg_timeout' : 'ffmpeg_loudnorm_unreadable',
      audioFileHash: anonymizedPathHash(options.audioFile),
      analysisFileHash: options.analysisFile ? anonymizedPathHash(options.analysisFile) : null,
      ffmpegStatus: ffmpeg.status,
      ffmpegSignal: ffmpeg.signal
    };
    writeJsonReport(options.writeJson, report);
    process.stdout.write(`Loudness reference validation BLOCKED: ${report.reason}.\n`);
    return;
  }

  const comparison = compare(reference, beatdropper, options);
  const report = {
    ...baseReport,
    status: comparison.status,
    audioFileHash: anonymizedPathHash(options.audioFile),
    analysisFileHash: options.analysisFile ? anonymizedPathHash(options.analysisFile) : null,
    beatdropper: {
      integratedLUFS: beatdropper.integratedLUFS,
      truePeakDb: beatdropper.truePeakDb,
      measurement: beatdropper.measurement
    },
    reference,
    checks: comparison.checks
  };
  writeJsonReport(options.writeJson, report);
  process.stdout.write(`Loudness reference validation ${report.status}: ${comparison.checks.map((check) => `${check.metric} delta ${check.delta}`).join(', ')}.\n`);
  if (report.status !== 'PASS') {
    process.exitCode = 1;
  }
};

main();
