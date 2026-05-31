#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const rootDir = path.resolve(__dirname, '..');
const nativeSourceDir = path.join(rootDir, 'native', 'Sources', 'BeatDropperNative');
const appPath = path.join(nativeSourceDir, 'BeatDropperNativeApp.swift');
const contentViewPaths = fs.readdirSync(nativeSourceDir)
  .filter((fileName) => /^ContentView(?:\+.+)?\.swift$/.test(fileName))
  .sort((left, right) => {
    if (left === 'ContentView.swift') return -1;
    if (right === 'ContentView.swift') return 1;
    return left.localeCompare(right);
  })
  .map((fileName) => path.join(nativeSourceDir, fileName));
const settingsViewPath = path.join(nativeSourceDir, 'MixSettingsView.swift');
const appModelPath = path.join(nativeSourceDir, 'BeatDropperAppModel.swift');
const appModelPaths = fs.readdirSync(nativeSourceDir)
  .filter((fileName) => /^BeatDropperAppModel(?:\+.+)?\.swift$/.test(fileName))
  .sort()
  .map((fileName) => path.join(nativeSourceDir, fileName));
const fileImporterPath = path.join(rootDir, 'native', 'Sources', 'BeatDropperNative', 'NativeFileImporter.swift');
const infoPlistPath = path.join(rootDir, 'native', 'Packaging', 'Info.plist');
const reportTitle = 'Native macOS Shell Check';

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
      'Usage: node scripts/check-native-macos-shell.cjs [options]',
      '',
      'Verifies native macOS shell integration, menus, settings, Finder Open With, and drag/drop evidence.',
      '',
      'Options:',
      '  --write-json <path>  Write durable macOS shell check evidence.',
      '  --help               Show this message.',
      ''
    ].join('\n')
  );
};

const read = (filePath) => fs.readFileSync(filePath, 'utf8');

const sources = {
  app: read(appPath),
  contentView: contentViewPaths.map(read).join('\n'),
  settingsView: read(settingsViewPath),
  appModel: read(appModelPath),
  appModelAll: appModelPaths.map(read).join('\n'),
  fileImporter: read(fileImporterPath),
  infoPlist: read(infoPlistPath)
};

const checks = [
  {
    label: 'main window keeps native command menus',
    source: sources.app,
    pattern: /WindowGroup\("BeatDropper"\)[\s\S]*\.commands[\s\S]*CommandGroup\(replacing: \.newItem\)[\s\S]*CommandMenu\("Set"\)[\s\S]*CommandMenu\("Playback"\)[\s\S]*CommandMenu\("Workspace"\)/
  },
  {
    label: 'standard Settings scene exists',
    source: sources.app,
    pattern: /Settings\s*\{[\s\S]*MixSettingsView\(\)[\s\S]*\.environmentObject\(model\)/
  },
  {
    label: 'file commands expose macOS shortcuts',
    source: sources.app,
    pattern: /Button\("New Set\.\.\."[\s\S]*keyboardShortcut\("o", modifiers: \[\.command\]\)[\s\S]*Button\("Add Tracks\.\.\."[\s\S]*keyboardShortcut\("o", modifiers: \[\.command, \.shift\]\)[\s\S]*Button\("Import Music Folder\.\.\."[\s\S]*keyboardShortcut\("i", modifiers: \[\.command, \.shift\]\)/
  },
  {
    label: 'playback commands expose DJ shortcuts',
    source: sources.app,
    pattern: /Button\("Play\/Pause"[\s\S]*keyboardShortcut\(\.space, modifiers: \[\]\)[\s\S]*"Turn Off AI Mix"[\s\S]*"Turn On AI Mix"[\s\S]*keyboardShortcut\("m", modifiers: \[\.command\]\)[\s\S]*Button\("Cancel AI Mix"[\s\S]*keyboardShortcut\("\.", modifiers: \[\.command\]\)/
  },
  {
    label: 'set commands expose playlist editing shortcuts',
    source: sources.app,
    pattern: /CommandMenu\("Set"\)[\s\S]*Button\("Move Selected Track Up"[\s\S]*keyboardShortcut\(\.upArrow, modifiers: \[\.command, \.option\]\)[\s\S]*Button\("Move Selected Track Down"[\s\S]*keyboardShortcut\(\.downArrow, modifiers: \[\.command, \.option\]\)[\s\S]*Button\("Remove Selected Track"[\s\S]*keyboardShortcut\(\.delete, modifiers: \[\]\)[\s\S]*Button\("Add Selected Library Track to Set"[\s\S]*keyboardShortcut\(\.return, modifiers: \[\.command\]\)/
  },
  {
    label: 'set commands expose library maintenance actions',
    source: sources.app,
    pattern: /CommandMenu\("Set"\)[\s\S]*Button\("Clear Set"[\s\S]*keyboardShortcut\(\.delete, modifiers: \[\.command, \.shift\]\)[\s\S]*Button\("Rescan Library Folders"[\s\S]*keyboardShortcut\("r", modifiers: \[\.command\]\)[\s\S]*Button\("Relink Selected Track\.\.\."[\s\S]*keyboardShortcut\("l", modifiers: \[\.command\]\)/
  },
  {
    label: 'workspace commands expose pane shortcuts',
    source: sources.app,
    pattern: /Button\("Playing Workspace"[\s\S]*keyboardShortcut\("1", modifiers: \[\.command\]\)[\s\S]*Button\("Creative Workspace"[\s\S]*keyboardShortcut\("2", modifiers: \[\.command\]\)[\s\S]*"Hide Library Browser"[\s\S]*"Show Library Browser"[\s\S]*keyboardShortcut\("2", modifiers: \[\.command, \.shift\]\)[\s\S]*"Hide Inspector"[\s\S]*"Show Inspector"[\s\S]*keyboardShortcut\("3", modifiers: \[\.command\]\)/
  },
  {
    label: 'settings view uses native form sections',
    source: sources.settingsView,
    pattern: /Form\s*\{[\s\S]*Section\("Mix"\)[\s\S]*Section\("AI Mix Planning"\)[\s\S]*accessibilityLabel\("BeatDropper settings"\)/
  },
  {
    label: 'Info.plist declares Finder-open audio and folder document types',
    source: sources.infoPlist,
    pattern: /CFBundleDocumentTypes[\s\S]*public\.audio[\s\S]*public\.mp3[\s\S]*com\.microsoft\.waveform-audio[\s\S]*public\.folder/
  },
  {
    label: 'app delegate handles Finder-opened files',
    source: sources.app,
    pattern: /func application\(_ application: NSApplication, open urls: \[URL\]\)[\s\S]*model\.openFinderItemsAsSet\(urls\)[\s\S]*pendingOpenURLs\.append/
  },
  {
    label: 'Finder-open import uses existing library pipeline',
    source: sources.appModelAll,
    pattern: /func openFinderItemsAsSet\(_ urls: \[URL\]\)[\s\S]*func openDroppedItemsAsSet\(_ urls: \[URL\]\)[\s\S]*openExternalItemsAsSet[\s\S]*NativeFileImporter\.classifyOpenURLs\(urls\)[\s\S]*replaceSetFromOpenSelection[\s\S]*upsertLibraryRecords[\s\S]*persistLibraryState\(\)[\s\S]*refreshAnalyses/
  },
  {
    label: 'workspace accepts dropped file URLs',
    source: sources.contentView,
    pattern: /@State (?:private )?var isFileDropTargeted = false[\s\S]*\.onDrop\(of: \[\.fileURL\], isTargeted: \$isFileDropTargeted\)[\s\S]*loadDroppedFileURLs\(from: providers\)[\s\S]*model\.openDroppedItemsAsSet\(urls\)/
  },
  {
    label: 'drop highlight stays transient and unframed',
    source: sources.contentView,
    pattern: /if isFileDropTargeted[\s\S]*RoundedRectangle\(cornerRadius: 10\)[\s\S]*\.stroke\(Color\.accentColor, lineWidth: 3\)[\s\S]*\.allowsHitTesting\(false\)/
  },
  {
    label: 'file importer classifies open URLs by folder and supported audio',
    source: sources.fileImporter,
    pattern: /struct NativeOpenImportSelection[\s\S]*supportedExtensions = Set\(\["mp3", "wav"\]\)[\s\S]*static func classifyOpenURLs\(_ urls: \[URL\]\)[\s\S]*isDirectory\(url\)[\s\S]*isSupportedAudioFile\(url\)/
  },
  {
    label: 'main toolbar does not carry a settings popover',
    source: sources.contentView,
    forbidden: /isSettingsPopoverVisible|Button\("Mix Settings"|popover\(isPresented:/
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

const results = checks.map((check) => {
  if (check.forbidden) {
    return {
      label: check.label,
      status: check.forbidden.test(check.source) ? 'fail' : 'pass'
    };
  }
  return {
    label: check.label,
    status: check.pattern.test(check.source) ? 'pass' : 'fail'
  };
});
const failures = results.filter((check) => check.status !== 'pass');
const status = failures.length === 0 ? 'PASS' : 'FAIL';

writeJsonReport(options.writeJson, {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  kind: 'macos-shell-check',
  status,
  sources: {
    app: relative(appPath),
    contentViewSources: contentViewPaths.map(relative),
    settingsView: relative(settingsViewPath),
    appModel: relative(appModelPath),
    appModelSources: appModelPaths.map(relative),
    fileImporter: relative(fileImporterPath),
    infoPlist: relative(infoPlistPath)
  },
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
