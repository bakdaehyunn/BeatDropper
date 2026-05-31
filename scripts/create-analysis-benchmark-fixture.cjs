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
      '',
      'Expected timing options:',
      '  --expected-bpm <number>',
      '  --first-downbeat <seconds>',
      '  --outro <seconds>',
      '  --bar-grid <sec,sec,...>',
      '  --phrase-boundaries <sec,sec,...>',
      '  --planner-ready <true|false>',
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
    } else if (arg === '--expected-bpm') {
      options.expectedBpm = parseNumber(next(), '--expected-bpm');
    } else if (arg === '--first-downbeat') {
      options.firstDownbeatSec = parseNumber(next(), '--first-downbeat');
    } else if (arg === '--outro') {
      options.outroCueSec = parseNumber(next(), '--outro');
    } else if (arg === '--bar-grid') {
      options.barGridSec = parseNumberList(next(), '--bar-grid');
    } else if (arg === '--phrase-boundaries') {
      options.phraseBoundarySec = parseNumberList(next(), '--phrase-boundaries');
    } else if (arg === '--planner-ready') {
      options.plannerReady = parseBoolean(next(), '--planner-ready');
    } else if (arg === '--overwrite') {
      options.overwrite = true;
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (options.trackId && options.analysisFile) {
    throw new Error('Use either --track-id or --analysis-file, not both.');
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

const compactAnalysis = (analysis) => {
  return {
    ...analysis,
    generatedAt: analysis.generatedAt,
    fileRevision: analysis.fileRevision ?? null
  };
};

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

  expected.plannerReady =
    typeof options.plannerReady === 'boolean' ? options.plannerReady : inferPlannerReady(analysis);

  return {
    id,
    title: options.title ?? `Private snapshot: ${id}`,
    kind: 'snapshot',
    tags: options.tags,
    trackReference: {
      source: 'private-library',
      ...(options.artist ? { artist: options.artist } : {}),
      ...(options.trackTitle ? { title: options.trackTitle } : {}),
      notes:
        options.notes ??
        'Bootstrapped from analyzer output. Review expected timing values manually.'
    },
    expectedGrade: options.expectedGrade,
    expected,
    analysis: compactAnalysis(analysis)
  };
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
  const filePath = writeFixture(fixture, options);

  process.stdout.write(
    [
      `Created ${filePath}`,
      `Fixture id: ${fixture.id}`,
      'Review expected timing values manually before treating this as ground truth.',
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
