#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const rootDir = path.resolve(__dirname, '..');
const contentViewPath = path.join(rootDir, 'native', 'Sources', 'BeatDropperNative', 'ContentView.swift');
const source = fs.readFileSync(contentViewPath, 'utf8');
const reportTitle = 'Native Accessibility Check';

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

const printUsage = () => {
  process.stdout.write(
    [
      'Usage: node scripts/check-native-accessibility.cjs [options]',
      '',
      'Verifies critical native SwiftUI accessibility labels.',
      '',
      'Options:',
      '  --write-json <path>  Write durable accessibility check evidence.',
      '  --help               Show this message.',
      ''
    ].join('\n')
  );
};

const checks = [
  {
    label: 'workspace root label',
    pattern: /accessibilityLabel\("BeatDropper DJ workspace"\)/
  },
  {
    label: 'primary toolbar label',
    pattern: /accessibilityLabel\("Primary toolbar"\)/
  },
  {
    label: 'live mix monitor label',
    pattern: /accessibilityLabel\("Live mix monitor"\)/
  },
  {
    label: 'current playlist table label',
    pattern: /accessibilityLabel\("Current playlist"\)/
  },
  {
    label: 'library browser table label',
    pattern: /accessibilityLabel\("Library browser"\)/
  },
  {
    label: 'search library label',
    pattern: /accessibilityLabel\("Search library"\)/
  },
  {
    label: 'move up icon label',
    pattern: /accessibilityLabel\("Move selected track up"\)/
  },
  {
    label: 'move down icon label',
    pattern: /accessibilityLabel\("Move selected track down"\)/
  },
  {
    label: 'remove icon label',
    pattern: /accessibilityLabel\("Remove selected track"\)/
  },
  {
    label: 'clear icon label',
    pattern: /accessibilityLabel\("Clear playlist"\)/
  },
  {
    label: 'hide library icon label',
    pattern: /accessibilityLabel\("Hide library browser"\)/
  },
  {
    label: 'cancel plan icon label',
    pattern: /accessibilityLabel\("Cancel AI mix plan"\)/
  },
  {
    label: 'previous transport icon label',
    pattern: /accessibilityLabel\("Crossfade to previous track"\)/
  },
  {
    label: 'play pause dynamic label',
    pattern: /accessibilityLabel\(model\.isPlaybackActive \? "Pause playback" : "Start playback"\)/
  },
  {
    label: 'next transport icon label',
    pattern: /accessibilityLabel\("Crossfade to next track"\)/
  },
  {
    label: 'transport controls label',
    pattern: /accessibilityLabel\("Transport controls"\)/
  },
  {
    label: 'output meters have value labels',
    pattern: /accessibilityValue\(meter\.clipped \? "clipping" : "\\\(Int\(meter\.peakDb\.rounded\(\)\)\) decibels"\)/
  }
];

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

const results = checks.map((check) => ({
  label: check.label,
  status: check.pattern.test(source) ? 'pass' : 'fail'
}));
const failures = results.filter((check) => check.status !== 'pass');
const status = failures.length === 0 ? 'PASS' : 'FAIL';

writeJsonReport(options.writeJson, {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  kind: 'accessibility-check',
  status,
  source: relative(contentViewPath),
  summary: {
    checkCount: checks.length,
    failCount: failures.length
  },
  checks: results
});

process.stdout.write(`# ${reportTitle}\n`);
if (failures.length === 0) {
  process.stdout.write(`status PASS\nchecks ${checks.length}\n`);
  process.exit(0);
}

process.stdout.write(`status FAIL\nchecks ${checks.length}\nfailed ${failures.length}\n`);
for (const failure of failures) {
  process.stdout.write(`- ${failure.label}\n`);
}
process.exit(1);
