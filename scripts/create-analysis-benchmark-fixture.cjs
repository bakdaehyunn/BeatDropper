#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const defaultOutDir = path.join(os.homedir(), 'beatdropper-analysis-snapshots');
const defaultCacheDirs = [
  process.env.BEATDROPPER_ANALYSIS_CACHE_DIR,
  path.join(os.homedir(), 'Library', 'Application Support', 'BeatDropper', 'track-analysis-cache'),
  path.join(os.homedir(), 'Library', 'Application Support', 'dropper-ai', 'track-analysis-cache')
].filter(Boolean);

const printUsage = () => {
  process.stdout.write(
    [
      'Usage: node scripts/create-analysis-benchmark-fixture.cjs [options]',
      '',
      'Source options:',
      '  --list-cache                 List saved app analysis cache entries.',
      '  --track-id <id>              Read analysis from the app cache by track id.',
      '  --analysis-file <path>       Read analysis from a JSON file.',
      '  --cache-dir <path>           Override the analysis cache directory.',
      '',
      'Fixture options:',
      `  --out-dir <path>             Output directory. Default: ${defaultOutDir}`,
      '  --id <id>                    Fixture id and filename stem.',
      '  --title <title>              Fixture title.',
      '  --artist <artist>            Optional private track artist label.',
      '  --track-title <title>        Optional private track title label.',
      '  --tags <a,b,c>               Comma-separated tags.',
      '  --notes <text>               Optional private notes.',
      '  --expected-grade <grade>     pass, warn, or fail. Default: pass.',
      '  --real-audio                 Emit schema-v2 real-audio corpus metadata.',
      '  --split <name>               calibration, validation, or regression.',
      '  --asset-id <opaque-id>       Anonymized, non-reversible local asset id.',
      '  --audio-rights <value>       private_user_owned or redistribution_cleared.',
      '  --duration <seconds>         Source audio duration for corpus integrity.',
      '  --sample-rate <hz>           Optional source sample rate.',
      '  --channel-count <count>      Optional source channel count.',
      '  --tempo-profile <value>      fixed, drifting, variable, or ambiguous.',
      '  --genre-tags <a,b,c>         Optional coarse, non-identifying genre tags.',
      '  --reviewed-by <id>           Pseudonymous reviewer id; omit for unreviewed bootstrap.',
      '  --labels-file <path>         Use an editable ground-truth labels JSON file as expected values.',
      '  --write-labels <path>        Write editable ground-truth labels JSON for review.',
      '',
      'Expected timing options:',
      '  --expected-bpm <number>',
      '  --first-downbeat <seconds>',
      '  --downbeats <sec,sec,...>',
      '  --outro <seconds>',
      '  --bar-grid <sec,sec,...>',
      '  --phrase-boundaries <sec,sec,...>',
      '  --planner-ready <true|false>',
      '  --expected-lufs <number>',
      '  --expected-true-peak <number>',
      '  --expected-key <tonic:mode>  Example: C#:minor.',
      '',
      'Safety:',
      '  --overwrite                  Replace an existing fixture file.',
      '  --help                       Show this message.',
      '',
      'When expected timing options are omitted, the script bootstraps them from the analysis.',
      'Review and correct expected values manually before treating a snapshot as ground truth.'
    ].join('\n') + '\n'
  );
};

const isFiniteNumber = (value) => typeof value === 'number' && Number.isFinite(value);

const parseNumber = (value, label) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`${label} must be a finite number.`);
  }
  return parsed;
};

const parseNumberList = (value, label) => {
  const values = String(value)
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => parseNumber(item, label));
  if (values.length === 0) {
    throw new Error(`${label} must include at least one number.`);
  }
  return values;
};

const parseBoolean = (value, label) => {
  if (value === 'true') {
    return true;
  }
  if (value === 'false') {
    return false;
  }
  throw new Error(`${label} must be true or false.`);
};

const parseGrade = (value) => {
  if (value === 'pass' || value === 'warn' || value === 'fail') {
    return value;
  }
  throw new Error('--expected-grade must be pass, warn, or fail.');
};

const parseTags = (value) => {
  return String(value)
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
};

const parseChoice = (value, label, choices) => {
  if (!choices.includes(value)) {
    throw new Error(`${label} must be one of: ${choices.join(', ')}.`);
  }
  return value;
};

const parseExpectedKey = (value) => {
  const [tonic, mode] = String(value).split(':');
  if (!tonic || (mode !== 'major' && mode !== 'minor')) {
    throw new Error('--expected-key must use tonic:major or tonic:minor.');
  }
  return { tonic, mode };
};

const parseArgs = (argv) => {
  const options = {
    listCache: false,
    outDir: defaultOutDir,
    tags: [],
    expectedGrade: 'pass',
    overwrite: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      const value = argv[index + 1];
      if (!value) {
        throw new Error(`${arg} requires a value.`);
      }
      index += 1;
      return value;
    };

    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    } else if (arg === '--list-cache') {
      options.listCache = true;
    } else if (arg === '--track-id') {
      options.trackId = next();
    } else if (arg === '--analysis-file') {
      options.analysisFile = path.resolve(process.cwd(), next());
    } else if (arg === '--cache-dir') {
      options.cacheDir = path.resolve(process.cwd(), next());
    } else if (arg === '--out-dir') {
      options.outDir = path.resolve(process.cwd(), next());
    } else if (arg === '--id') {
      options.id = next();
    } else if (arg === '--title') {
      options.title = next();
    } else if (arg === '--artist') {
      options.artist = next();
    } else if (arg === '--track-title') {
      options.trackTitle = next();
    } else if (arg === '--tags') {
      options.tags = parseTags(next());
    } else if (arg === '--notes') {
      options.notes = next();
    } else if (arg === '--expected-grade') {
      options.expectedGrade = parseGrade(next());
    } else if (arg === '--real-audio') {
      options.realAudio = true;
    } else if (arg === '--split') {
      options.split = parseChoice(next(), '--split', ['calibration', 'validation', 'regression']);
    } else if (arg === '--asset-id') {
      options.assetId = next();
    } else if (arg === '--audio-rights') {
      options.audioRights = parseChoice(next(), '--audio-rights', [
        'private_user_owned',
        'redistribution_cleared'
      ]);
    } else if (arg === '--duration') {
      options.audioDurationSec = parseNumber(next(), '--duration');
    } else if (arg === '--sample-rate') {
      options.sampleRate = parseNumber(next(), '--sample-rate');
    } else if (arg === '--channel-count') {
      options.channelCount = parseNumber(next(), '--channel-count');
    } else if (arg === '--tempo-profile') {
      options.tempoProfile = parseChoice(next(), '--tempo-profile', [
        'fixed',
        'drifting',
        'variable',
        'ambiguous'
      ]);
    } else if (arg === '--genre-tags') {
      options.genreTags = parseTags(next());
    } else if (arg === '--reviewed-by') {
      options.reviewedBy = next();
    } else if (arg === '--labels-file') {
      options.labelsFile = path.resolve(process.cwd(), next());
    } else if (arg === '--write-labels') {
      options.writeLabels = path.resolve(process.cwd(), next());
    } else if (arg === '--expected-bpm') {
      options.expectedBpm = parseNumber(next(), '--expected-bpm');
    } else if (arg === '--first-downbeat') {
      options.firstDownbeatSec = parseNumber(next(), '--first-downbeat');
    } else if (arg === '--downbeats') {
      options.downbeatSec = parseNumberList(next(), '--downbeats');
    } else if (arg === '--outro') {
      options.outroCueSec = parseNumber(next(), '--outro');
    } else if (arg === '--bar-grid') {
      options.barGridSec = parseNumberList(next(), '--bar-grid');
    } else if (arg === '--phrase-boundaries') {
      options.phraseBoundarySec = parseNumberList(next(), '--phrase-boundaries');
    } else if (arg === '--planner-ready') {
      options.plannerReady = parseBoolean(next(), '--planner-ready');
    } else if (arg === '--expected-lufs') {
      options.expectedLUFS = parseNumber(next(), '--expected-lufs');
    } else if (arg === '--expected-true-peak') {
      options.expectedTruePeakDb = parseNumber(next(), '--expected-true-peak');
    } else if (arg === '--expected-key') {
      options.expectedKey = parseExpectedKey(next());
    } else if (arg === '--overwrite') {
      options.overwrite = true;
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (options.trackId && options.analysisFile) {
    throw new Error('Use either --track-id or --analysis-file, not both.');
  }
  if (options.realAudio) {
    for (const [label, value] of [
      ['--split', options.split],
      ['--asset-id', options.assetId],
      ['--audio-rights', options.audioRights],
      ['--duration', options.audioDurationSec]
    ]) {
      if (value === undefined) {
        throw new Error(`${label} is required with --real-audio.`);
      }
    }
    if (options.audioDurationSec <= 0) {
      throw new Error('--duration must be greater than zero.');
    }
    if (options.channelCount !== undefined && (!Number.isInteger(options.channelCount) || options.channelCount <= 0)) {
      throw new Error('--channel-count must be a positive integer.');
    }
  }

  return options;
};

const resolveCacheDir = (options) => {
  if (options.cacheDir) {
    return options.cacheDir;
  }
  return defaultCacheDirs.find((cacheDir) => fs.existsSync(cacheDir)) ?? defaultCacheDirs[0];
};

const readJsonFile = (filePath) => {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
};

const collectCacheEntries = (cacheDir) => {
  if (!fs.existsSync(cacheDir)) {
    return [];
  }
  const stat = fs.statSync(cacheDir);
  if (!stat.isDirectory()) {
    throw new Error(`Cache path is not a directory: ${cacheDir}`);
  }

  return fs
    .readdirSync(cacheDir)
    .filter((name) => name.endsWith('.json'))
    .sort()
    .map((name) => {
      const filePath = path.join(cacheDir, name);
      const analysis = readJsonFile(filePath);
      const fallbackTrackId = decodeURIComponent(path.basename(name, '.json'));
      return {
        filePath,
        analysis,
        trackId:
          typeof analysis.trackId === 'string' && analysis.trackId.length > 0
            ? analysis.trackId
            : fallbackTrackId
      };
    });
};

const printCacheEntries = (cacheDir) => {
  const entries = collectCacheEntries(cacheDir);
  process.stdout.write(
    ['# Analysis Cache', `cache dir ${cacheDir}`, `entries ${entries.length}`, ''].join('\n')
  );

  for (const entry of entries) {
    const bpm = isFiniteNumber(entry.analysis.bpm) ? entry.analysis.bpm.toFixed(2) : '--';
    const bars = Array.isArray(entry.analysis.barGrid) ? entry.analysis.barGrid.length : 0;
    const generatedAt =
      typeof entry.analysis.generatedAt === 'string' ? entry.analysis.generatedAt : '--';
    process.stdout.write(
      `- ${entry.trackId} | bpm ${bpm} | bars ${bars} | generated ${generatedAt}\n`
    );
  }
};

const readAnalysis = (options) => {
  if (options.analysisFile) {
    return readJsonFile(options.analysisFile);
  }

  if (!options.trackId) {
    throw new Error('Use --analysis-file, --track-id, or --list-cache.');
  }

  const cacheDir = resolveCacheDir(options);
  const filePath = path.join(cacheDir, `${encodeURIComponent(options.trackId)}.json`);
  if (!fs.existsSync(filePath)) {
    throw new Error(`No cached analysis found for track id: ${options.trackId}`);
  }
  return readJsonFile(filePath);
};

const slugify = (value) => {
  const slug = String(value)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug.length > 0 ? slug : 'analysis-snapshot';
};

const cueTime = (analysis, type) => {
  if (!Array.isArray(analysis.cueCandidates)) {
    return null;
  }
  const cue = analysis.cueCandidates.find((item) => item && item.type === type);
  return cue && isFiniteNumber(cue.startSec) ? cue.startSec : null;
};

const firstFinite = (...values) => {
  return values.find(isFiniteNumber) ?? null;
};

const rounded = (value) => {
  return Number(value.toFixed(3));
};

const finiteArray = (value) => {
  return Array.isArray(value) ? value.filter(isFiniteNumber) : [];
};

const inferPlannerReady = (analysis) => {
  const quality = analysis.analysisQuality ?? {};
  const warnings = Array.isArray(analysis.analysisWarnings) ? analysis.analysisWarnings : [];
  return Boolean(
    Array.isArray(analysis.waveformDetail) &&
      analysis.waveformDetail.length > 0 &&
      Array.isArray(analysis.energyProfile) &&
      analysis.energyProfile.length > 0 &&
      Array.isArray(analysis.barGrid) &&
      analysis.barGrid.length > 0 &&
      isFiniteNumber(analysis.bpmConfidence) &&
      analysis.bpmConfidence >= 0.45 &&
      isFiniteNumber(quality.waveformDetail) &&
      quality.waveformDetail >= 0.2 &&
      isFiniteNumber(quality.beatGrid) &&
      quality.beatGrid >= 0.35 &&
      !warnings.includes('analysis_upgrade_available') &&
      !warnings.includes('bpm_low_confidence')
  );
};

const bootstrapBarGrid = (analysis) => {
  if (!Array.isArray(analysis.barGrid)) {
    return [];
  }
  return analysis.barGrid
    .map((bar) => bar?.startSec)
    .filter(isFiniteNumber)
    .slice(0, 16)
    .map(rounded);
};

const bootstrapPhraseBoundaries = (analysis) => {
  if (!Array.isArray(analysis.phraseMarkers)) {
    return [];
  }
  return analysis.phraseMarkers
    .map((marker) => marker?.startSec)
    .filter(isFiniteNumber)
    .slice(0, 8)
    .map(rounded);
};

const bootstrapDownbeats = (analysis) => finiteArray(analysis.downbeatsSec)
  .slice(0, 32)
  .map(rounded);

const bootstrapCueCandidates = (analysis) => {
  if (!Array.isArray(analysis.cueCandidates)) {
    return [];
  }
  return analysis.cueCandidates
    .filter((cue) => cue && typeof cue.type === 'string' && isFiniteNumber(cue.startSec))
    .slice(0, 8)
    .map((cue) => ({
      type: cue.type,
      startSec: rounded(cue.startSec),
      ...(typeof cue.origin === 'string' ? { origin: cue.origin } : {})
    }));
};

const compactAnalysis = (analysis) => {
  return {
    ...analysis,
    generatedAt: analysis.generatedAt,
    fileRevision: analysis.fileRevision ?? null
  };
};

const loadGroundTruthLabels = (filePath) => {
  const labels = readJsonFile(filePath);
  if (!labels || typeof labels !== 'object' || !labels.expected || typeof labels.expected !== 'object') {
    throw new Error(`Ground-truth labels file must contain an expected object: ${filePath}`);
  }
  return {
    schemaVersion: Number.isInteger(labels.schemaVersion) ? labels.schemaVersion : 1,
    ...(typeof labels.reviewedBy === 'string' ? { reviewedBy: labels.reviewedBy } : {}),
    ...(typeof labels.reviewedAt === 'string' ? { reviewedAt: labels.reviewedAt } : {}),
    ...(typeof labels.notes === 'string' ? { notes: labels.notes } : {}),
    expected: labels.expected
  };
};

const loadReferenceTools = (filePath) => {
  if (!filePath) return [];
  const labels = readJsonFile(filePath);
  return Array.isArray(labels.referenceTools)
    ? labels.referenceTools.filter((tool) => tool && typeof tool.name === 'string' && tool.name.trim())
    : [];
};

const buildGroundTruthLabels = (expected, options) => ({
  schemaVersion: options.realAudio ? 2 : 1,
  reviewedBy: options.reviewedBy ?? (options.realAudio ? 'UNREVIEWED' : 'user'),
  reviewedAt: new Date().toISOString(),
  notes:
    options.notes ??
    'Editable BeatDropper DSP ground-truth labels. Review values before using them as calibration truth.',
  expected
});

const buildFixture = (analysis, options) => {
  const baseId = options.id ?? analysis.trackId ?? options.trackTitle ?? 'analysis-snapshot';
  const id = slugify(baseId);
  const firstDownbeatSec = firstFinite(
    options.firstDownbeatSec,
    cueTime(analysis, 'first_downbeat'),
    finiteArray(analysis.downbeatsSec)[0],
    analysis.introCueSec
  );
  const outroCueSec = firstFinite(options.outroCueSec, cueTime(analysis, 'outro'), analysis.outroCueSec);
  const expected = {};

  const expectedBpm = firstFinite(options.expectedBpm, analysis.bpm);
  if (expectedBpm !== null) {
    expected.bpm = rounded(expectedBpm);
  }
  if (firstDownbeatSec !== null) {
    expected.firstDownbeatSec = rounded(firstDownbeatSec);
  }
  const downbeatSec = options.downbeatSec ?? (options.realAudio ? bootstrapDownbeats(analysis) : []);
  if (downbeatSec.length > 0) {
    expected.downbeatSec = downbeatSec.map(rounded);
  }
  if (outroCueSec !== null) {
    expected.outroCueSec = rounded(outroCueSec);
  }

  const barGridSec = options.barGridSec ?? bootstrapBarGrid(analysis);
  if (barGridSec.length > 0) {
    expected.barGridSec = barGridSec.map(rounded);
  }

  const phraseBoundarySec = options.phraseBoundarySec ?? bootstrapPhraseBoundaries(analysis);
  if (phraseBoundarySec.length > 0) {
    expected.phraseBoundarySec = phraseBoundarySec.map(rounded);
  }

  const expectedKey = options.expectedKey ?? (options.realAudio &&
    typeof analysis.musicalKey?.tonic === 'string' &&
    (analysis.musicalKey?.mode === 'major' || analysis.musicalKey?.mode === 'minor')
      ? { tonic: analysis.musicalKey.tonic, mode: analysis.musicalKey.mode }
      : null
  );
  if (expectedKey) {
    expected.musicalKey = expectedKey;
  }

  const cueCandidates = options.realAudio ? bootstrapCueCandidates(analysis) : [];
  if (cueCandidates.length > 0) {
    expected.cueCandidates = cueCandidates;
  }

  expected.plannerReady =
    typeof options.plannerReady === 'boolean' ? options.plannerReady : inferPlannerReady(analysis);

  const expectedLUFS = firstFinite(options.expectedLUFS, analysis.loudness?.integratedLUFS);
  const expectedTruePeakDb = firstFinite(options.expectedTruePeakDb, analysis.loudness?.truePeakDb);
  if (
    expectedLUFS !== null ||
    expectedTruePeakDb !== null ||
    isFiniteNumber(analysis.loudness?.integratedRMSDb) ||
    isFiniteNumber(analysis.loudness?.peakDb)
  ) {
    expected.loudness = {
      ...(isFiniteNumber(analysis.loudness?.integratedRMSDb)
        ? { integratedRMSDb: rounded(analysis.loudness.integratedRMSDb) }
        : {}),
      ...(expectedLUFS !== null ? { integratedLUFS: rounded(expectedLUFS) } : {}),
      ...(isFiniteNumber(analysis.loudness?.peakDb) ? { peakDb: rounded(analysis.loudness.peakDb) } : {}),
      ...(expectedTruePeakDb !== null ? { truePeakDb: rounded(expectedTruePeakDb) } : {}),
      ...(isFiniteNumber(analysis.loudness?.headroomDb)
        ? { minHeadroomDb: rounded(Math.max(0, Math.min(analysis.loudness.headroomDb, 1))) }
        : {}),
      ...(isFiniteNumber(analysis.loudness?.confidence)
        ? { minConfidence: rounded(Math.max(0.45, Math.min(analysis.loudness.confidence, 0.8))) }
        : {})
    };
  }

  const groundTruthLabels = options.labelsFile
    ? loadGroundTruthLabels(options.labelsFile)
    : buildGroundTruthLabels(expected, options);
  const authoritativeExpected = groundTruthLabels.expected;

  return {
    id,
    title: options.title ?? `Private snapshot: ${id}`,
    kind: options.realAudio ? 'real_audio' : 'snapshot',
    tags: options.tags,
    ...(options.realAudio
      ? {
          corpus: {
            schemaVersion: 2,
            split: options.split,
            anonymizedAssetId: options.assetId,
            audioRights: options.audioRights,
            audioDurationSec: rounded(options.audioDurationSec),
            ...(options.sampleRate !== undefined ? { sampleRate: rounded(options.sampleRate) } : {}),
            ...(options.channelCount !== undefined ? { channelCount: options.channelCount } : {}),
            genreTags: options.genreTags ?? [],
            tempoProfile: options.tempoProfile ?? 'fixed',
            referenceTools: loadReferenceTools(options.labelsFile)
          }
        }
      : {
          trackReference: {
            source: 'private-library',
            ...(options.artist ? { artist: options.artist } : {}),
            ...(options.trackTitle ? { title: options.trackTitle } : {}),
            notes:
              options.notes ??
              'Bootstrapped from analyzer output. Review expected timing values manually.'
          }
        }),
    expectedGrade: options.expectedGrade,
    expected: authoritativeExpected,
    groundTruthLabels,
    analysis: compactAnalysis(analysis)
  };
};

const writeLabels = (labels, options) => {
  if (!options.writeLabels) {
    return null;
  }
  fs.mkdirSync(path.dirname(options.writeLabels), { recursive: true });
  if (fs.existsSync(options.writeLabels) && !options.overwrite) {
    throw new Error(`Labels file already exists: ${options.writeLabels}. Use --overwrite to replace it.`);
  }
  fs.writeFileSync(options.writeLabels, `${JSON.stringify(labels, null, 2)}\n`, 'utf8');
  return options.writeLabels;
};

const writeFixture = (fixture, options) => {
  fs.mkdirSync(options.outDir, { recursive: true });
  const filePath = path.join(options.outDir, `${fixture.id}.json`);
  if (fs.existsSync(filePath) && !options.overwrite) {
    throw new Error(`Fixture already exists: ${filePath}. Use --overwrite to replace it.`);
  }
  fs.writeFileSync(filePath, `${JSON.stringify(fixture, null, 2)}\n`, 'utf8');
  return filePath;
};

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  const cacheDir = resolveCacheDir(options);

  if (options.listCache) {
    printCacheEntries(cacheDir);
    return;
  }

  const analysis = readAnalysis(options);
  const fixture = buildFixture(analysis, options);
  const labelsPath = writeLabels(fixture.groundTruthLabels, options);
  const filePath = writeFixture(fixture, options);

  process.stdout.write(
    [
      `Created ${filePath}`,
      ...(labelsPath ? [`Wrote editable labels ${labelsPath}`] : []),
      `Fixture id: ${fixture.id}`,
      ...(fixture.kind === 'real_audio' && fixture.groundTruthLabels.reviewedBy === 'UNREVIEWED'
        ? ['Real-audio fixture remains invalid until --reviewed-by and independently verified labels are supplied.']
        : []),
      'Review groundTruthLabels.expected values manually before treating this as calibration truth.',
      `Run: npm run native:benchmark:analysis -- --no-default-fixtures --fixture-dir ${options.outDir}`
    ].join('\n') + '\n'
  );
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
