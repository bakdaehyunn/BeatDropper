#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const defaultFixtureDir = path.resolve(__dirname, '..', 'tests', 'fixtures', 'analysis-benchmarks');
const benchmarkModulePath = path.resolve(
  __dirname,
  '..',
  'dist-electron',
  'shared',
  'analysisBenchmark.js'
);

const printUsage = () => {
  process.stdout.write(
    [
      'Usage: node scripts/evaluate-analysis-benchmarks.cjs [options]',
      '',
      'Options:',
      '  --fixture-dir <path>       Add a benchmark fixture directory. May be repeated.',
      '  --no-default-fixtures      Skip tests/fixtures/analysis-benchmarks.',
      '  --help                    Show this message.',
      '',
      'Fixture directories are scanned recursively for .json files.'
    ].join('\n') + '\n'
  );
};

const parseArgs = (argv) => {
  const options = {
    includeDefaultFixtures: true,
    fixtureDirs: []
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
    if (arg === '--no-default-fixtures') {
      options.includeDefaultFixtures = false;
      continue;
    }
    if (arg === '--fixture-dir') {
      const next = argv[index + 1];
      if (!next) {
        throw new Error('--fixture-dir requires a path.');
      }
      options.fixtureDirs.push(path.resolve(process.cwd(), next));
      index += 1;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  if (process.env.ANALYSIS_BENCHMARK_FIXTURE_DIR) {
    options.fixtureDirs.push(path.resolve(process.cwd(), process.env.ANALYSIS_BENCHMARK_FIXTURE_DIR));
  }

  return options;
};

const loadBenchmarkModule = () => {
  if (!fs.existsSync(benchmarkModulePath)) {
    throw new Error(
      'analysis benchmark module is not built. Run `npm run build:main` before this script.'
    );
  }

  return require(benchmarkModulePath);
};

const collectFixtureFiles = (fixtureDir) => {
  if (!fs.existsSync(fixtureDir)) {
    return [];
  }

  const stat = fs.statSync(fixtureDir);
  if (!stat.isDirectory()) {
    throw new Error(`Fixture path is not a directory: ${fixtureDir}`);
  }

  const files = [];
  for (const entry of fs.readdirSync(fixtureDir, { withFileTypes: true })) {
    const entryPath = path.join(fixtureDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectFixtureFiles(entryPath));
      continue;
    }
    if (entry.isFile() && entry.name.endsWith('.json')) {
      files.push(entryPath);
    }
  }
  return files;
};

const loadFixtures = (fixtureDirs) => {
  const files = [...new Set(fixtureDirs.flatMap(collectFixtureFiles))].sort();
  return files.map((filePath) => ({
    name: path.relative(process.cwd(), filePath),
    fixture: JSON.parse(fs.readFileSync(filePath, 'utf8'))
  }));
};

const formatMetric = (value, suffix = '') => {
  return typeof value === 'number' && Number.isFinite(value) ? `${value.toFixed(2)}${suffix}` : '--';
};

const formatDistanceMetric = (metric) => {
  if (!metric) {
    return '--';
  }

  return [
    `expected ${formatMetric(metric.expectedSec, 's')}`,
    `actual ${formatMetric(metric.actualSec, 's')}`,
    `distance ${formatMetric(metric.distanceSec, 's')}`
  ].join(', ');
};

const formatKeyMetric = (metric) => {
  if (!metric) {
    return '--';
  }
  const expected = [metric.expectedTonic, metric.expectedMode].filter(Boolean).join(' ');
  const actual = [metric.actualTonic, metric.actualMode].filter(Boolean).join(' ');
  return `expected ${expected || '--'}, actual ${actual || '--'}, confidence ${formatMetric(metric.confidence)}, matched ${metric.matched ?? '--'}`;
};

const formatLoudnessMetric = (metric) => {
  if (!metric) {
    return '--';
  }
  return [
    `RMS ${formatMetric(metric.actualIntegratedRMSDb, ' dB')} delta ${formatMetric(metric.integratedRMSDeltaDb, ' dB')}`,
    `LUFS ${formatMetric(metric.actualIntegratedLUFS, ' LUFS')} delta ${formatMetric(metric.integratedLUFSDelta, ' LU')}`,
    `peak ${formatMetric(metric.actualPeakDb, ' dB')} delta ${formatMetric(metric.peakDeltaDb, ' dB')}`,
    `true peak ${formatMetric(metric.actualTruePeakDb, ' dBTP')} delta ${formatMetric(metric.truePeakDeltaDb, ' dB')}`,
    `headroom ${formatMetric(metric.headroomDb, ' dB')}`,
    `LRA ${formatMetric(metric.loudnessRangeLU, ' LU')}`,
    `measurement ${metric.measurement ?? '--'}`,
    `confidence ${formatMetric(metric.confidence)}`
  ].join(', ');
};

const formatStereoMetric = (metric) => {
  if (!metric) {
    return '--';
  }
  return [
    `channels ${metric.actualChannelCount ?? '--'}`,
    `width ${formatMetric(metric.stereoWidth)}`,
    `phase ${formatMetric(metric.phaseCorrelation)}`,
    `mid/side ${formatMetric(metric.midSideBalance)}`,
    `confidence ${formatMetric(metric.confidence)}`
  ].join(', ');
};

const formatCueMetrics = (metrics) => {
  if (!Array.isArray(metrics) || metrics.length === 0) {
    return '--';
  }
  return metrics
    .map((metric) =>
      `${metric.type} expected ${formatMetric(metric.expectedSec, 's')} actual ${formatMetric(metric.actualSec, 's')} distance ${formatMetric(metric.distanceSec, 's')} confidence ${formatMetric(metric.confidence)} origin ${metric.origin ?? '--'}`
    )
    .join(' | ');
};

const formatMixReadinessMetric = (metric) => {
  if (!metric) {
    return '--';
  }
  const warnings = Array.isArray(metric.forbiddenWarningsPresent)
    ? metric.forbiddenWarningsPresent.join(',')
    : '';
  return `analysis ${formatMetric(metric.analysisConfidence)}, harmonic ${formatMetric(metric.harmonicKeyQuality)}, loudness ${formatMetric(metric.loudnessConfidence)}, forbidden warnings ${warnings || '--'}`;
};

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  const { evaluateAnalysisBenchmarkSuite } = loadBenchmarkModule();
  const fixtureDirs = [
    ...(options.includeDefaultFixtures ? [defaultFixtureDir] : []),
    ...options.fixtureDirs
  ];
  const fixtures = loadFixtures(fixtureDirs);
  const suite = evaluateAnalysisBenchmarkSuite(fixtures.map((item) => item.fixture));

  process.stdout.write(
    [
      '# Analysis Benchmarks',
      `fixture dirs ${fixtureDirs.length}`,
      `fixtures ${suite.results.length}`,
      `grade ${suite.grade}`,
      `score ${suite.score.toFixed(3)}`,
      `pass ${suite.passed}`,
      `warn ${suite.warned}`,
      `fail ${suite.failed}`,
      ''
    ].join('\n')
  );

  if (suite.byKind.length > 0) {
    process.stdout.write('## Fixture Kinds\n');
    for (const summary of suite.byKind) {
      process.stdout.write(
        `${summary.kind}: ${summary.grade.toUpperCase()} | fixtures ${summary.total} | score ${summary.score.toFixed(3)} | pass ${summary.passed} warn ${summary.warned} fail ${summary.failed}\n`
      );
    }
    process.stdout.write('\n');
  }

  for (const result of suite.results) {
    process.stdout.write(
      [
        `## ${result.fixtureId}`,
        `${result.grade.toUpperCase()} | score ${result.score.toFixed(3)} | ${result.title}`,
        `Kind: ${result.kind}`,
        `BPM error: ${formatMetric(result.metrics.bpmError)}`,
        `First downbeat: ${formatDistanceMetric(result.metrics.firstDownbeat)}`,
        `Outro cue: ${formatDistanceMetric(result.metrics.outro)}`,
        `Bar grid: checked ${result.metrics.barGrid.checkedCount}, avg drift ${formatMetric(result.metrics.barGrid.averageDriftSec, 's')}, max drift ${formatMetric(result.metrics.barGrid.maxDriftSec, 's')}`,
        `Phrase: checked ${result.metrics.phraseBoundaries.checkedCount}, avg distance ${formatMetric(result.metrics.phraseBoundaries.averageDistanceSec, 's')}, max distance ${formatMetric(result.metrics.phraseBoundaries.maxDistanceSec, 's')}`,
        `Planner ready match: ${
          result.metrics.plannerReadyMatch === null ? '--' : result.metrics.plannerReadyMatch
        }`,
        `Key: ${formatKeyMetric(result.metrics.musicalKey)}`,
        `Loudness: ${formatLoudnessMetric(result.metrics.loudness)}`,
        `Stereo: ${formatStereoMetric(result.metrics.stereo)}`,
        `Cue calibration: ${formatCueMetrics(result.metrics.cueCandidates)}`,
        `Mix readiness: ${formatMixReadinessMetric(result.metrics.mixReadiness)}`
      ].join('\n') + '\n'
    );

    if (result.issues.length > 0) {
      for (const issue of result.issues) {
        process.stdout.write(`- ${issue.grade.toUpperCase()} ${issue.code}: ${issue.message}\n`);
      }
    } else {
      process.stdout.write('- no issues\n');
    }
    process.stdout.write('\n');
  }

  if (suite.failed > 0) {
    process.exitCode = 1;
  }
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
