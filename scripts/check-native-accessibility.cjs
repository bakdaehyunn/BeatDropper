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

const firstNumber = (pattern, target = source) => {
  const match = target.match(pattern);
  if (!match) {
    return null;
  }
  const value = Number(match[1]);
  return Number.isFinite(value) ? value : null;
};

const sourceSection = (startPattern, endPattern) => {
  const start = source.search(startPattern);
  if (start < 0) {
    return '';
  }
  const rest = source.slice(start);
  const end = rest.search(endPattern);
  return end < 0 ? rest : rest.slice(0, end);
};

const sumMinWidths = (target) => {
  const matches = [...target.matchAll(/\.frame\(minWidth: ([0-9]+)/g)];
  return matches.reduce((total, match) => total + Number(match[1]), 0);
};

const rootHasTwoAxisScrollFallback = () => (
  /GeometryReader\s*\{ proxy in[\s\S]*ScrollView\(\[\.horizontal, \.vertical\], showsIndicators: true\)[\s\S]*width: max\(proxy\.size\.width, AppLayoutMetrics\.minimumContentWidth\)[\s\S]*height: max\(proxy\.size\.height, AppLayoutMetrics\.minimumContentHeight\)/.test(source)
);

const splitPaneMinWidthsFitWindow = () => {
  const contentMinWidth = firstNumber(/minimumContentWidth: CGFloat = ([0-9]+)/);
  if (!contentMinWidth) {
    return false;
  }

  const playingWorkspace = sourceSection(
    /private var playingWorkspace:/,
    /private var creativeWorkspace:/
  );
  const creativeWorkspace = sourceSection(
    /private var creativeWorkspace:/,
    /private var mixMonitor:/
  );

  return (
    sumMinWidths(playingWorkspace) <= contentMinWidth &&
    sumMinWidths(creativeWorkspace) <= contentMinWidth
  ) || rootHasTwoAxisScrollFallback();
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
    label: 'workspace mode picker label',
    pattern: /accessibilityLabel\("Workspace mode"\)/
  },
  {
    label: 'live mix monitor label',
    pattern: /accessibilityLabel\("Live mix monitor"\)/
  },
  {
    label: 'playing monitor exposes a dedicated waveform stack',
    pattern: /private var playingWaveformStack:[\s\S]*deckWaveformRow[\s\S]*title: "Current"[\s\S]*deckWaveformRow[\s\S]*title: "Next"[\s\S]*accessibilityLabel\("Playing waveform stack"\)/
  },
  {
    label: 'playing monitor keeps deck and AI status secondary',
    pattern: /private var playingMonitorMetaBar:[\s\S]*Text\(playingMixStatusText\)[\s\S]*private var playingMixStatusText: String/
  },
  {
    label: 'playing waveform rows are larger than summary cards',
    pattern: /private func deckWaveformRow[\s\S]*miniDeckMeter\(meter\)[\s\S]*\.frame\(height: 118\)/
  },
  {
    label: 'playing waveform strip renders through Canvas',
    pattern: /private func trackWaveformStrip[\s\S]*waveformRenderPoints\(for: analysis\)[\s\S]*return Canvas/
  },
  {
    label: 'playing waveform strip includes bar phrase and transient evidence',
    pattern: /private func trackWaveformStrip[\s\S]*drawBarMarkers[\s\S]*drawPhraseMarkers[\s\S]*drawTransientMarkers/
  },
  {
    label: 'waveform renderer prefers detailed DSP data with fallback peaks',
    pattern: /func waveformRenderPoints[\s\S]*analysis\.waveformDetail[\s\S]*spectralBand[\s\S]*analysis\.waveformPeaks/
  },
  {
    label: 'playing waveform cursors include play out and in markers',
    pattern: /cueLabel: "OUT"[\s\S]*cueLabel: "IN"[\s\S]*label: "PLAY"/
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
    label: 'creative workspace label',
    pattern: /accessibilityLabel\("Creative workspace"\)/
  },
  {
    label: 'creative workspace includes a track preparation monitor',
    pattern: /private var creativeTrackMonitor:[\s\S]*accessibilityLabel\("Creative track monitor"\)/
  },
  {
    label: 'creative waveform supports click to preview',
    pattern: /private func creativeWaveform[\s\S]*DragGesture\(minimumDistance: 0\)[\s\S]*model\.previewCreativeTrack[\s\S]*accessibilityLabel\("Creative waveform editor"\)/
  },
  {
    label: 'creative preparation exposes BPM tap and hot cue actions',
    pattern: /TextField\("BPM"[\s\S]*setCreativeBPMOverride[\s\S]*Button\("Tap"[\s\S]*applyTappedBPMToCreativeTrack[\s\S]*Add Cue[\s\S]*addCreativeHotCue/
  },
  {
    label: 'search library label',
    pattern: /accessibilityLabel\("Search library"\)/
  },
  {
    label: 'move up icon label',
    pattern: /accessibilityLabel(?:\(|:) ?"Move selected track up"/
  },
  {
    label: 'move down icon label',
    pattern: /accessibilityLabel(?:\(|:) ?"Move selected track down"/
  },
  {
    label: 'remove icon label',
    pattern: /accessibilityLabel(?:\(|:) ?"Remove selected track"/
  },
  {
    label: 'clear icon label',
    pattern: /accessibilityLabel(?:\(|:) ?"Clear playlist"/
  },
  {
    label: 'hide library icon label',
    pattern: /accessibilityLabel(?:\(|:) ?"Hide library browser"/
  },
  {
    label: 'previous transport icon label',
    pattern: /accessibilityLabel(?:\(|:) ?"Crossfade to previous track"/
  },
  {
    label: 'play pause dynamic label',
    pattern: /accessibilityLabel(?:\(|:) ?model\.isPlaybackActive \? "Pause playback" : "Start playback"/
  },
  {
    label: 'next transport icon label',
    pattern: /accessibilityLabel(?:\(|:) ?"Crossfade to next track"/
  },
  {
    label: 'transport controls label',
    pattern: /accessibilityLabel\("Transport controls"\)/
  },
  {
    label: 'transport uses AI mix toggle instead of one-shot plan button',
    pattern: /Toggle\([\s\S]*get: \{ model\.isAIMixEnabled \}[\s\S]*set: \{ model\.setAIMixEnabled\(\$0\) \}[\s\S]*Text\("AI Mix"\)[\s\S]*toggleStyle\(AIMixSwitchToggleStyle\(\)\)/
  },
  {
    label: 'output meters have value labels',
    pattern: /accessibilityValue\(meter\.clipped \? "clipping" : "\\\(Int\(meter\.peakDb\.rounded\(\)\)\) decibels"\)/
  },
  {
    label: 'live mix monitor is hidden until a playable surface exists',
    pattern: /if shouldShowMixMonitor[\s\S]*mixMonitor[\s\S]*private var shouldShowMixMonitor: Bool[\s\S]*model\.workspaceMode == \.playing && hasPlayableSurface/
  },
  {
    label: 'transport controls sit under live monitor',
    pattern: /private var playingWorkspace:[\s\S]*playbackControlBar[\s\S]*playlistPane/
  },
  {
    label: 'playing shell places controls between monitor and playlist',
    pattern: /private var mainStage:[\s\S]*mixMonitor[\s\S]*frame\(height: 360\)[\s\S]*workspaceContent[\s\S]*private var playingWorkspace:[\s\S]*playbackControlBar[\s\S]*playlistPane/
  },
  {
    label: 'root window uses two-axis scroll fallback when content is larger than the window',
    test: rootHasTwoAxisScrollFallback
  },
  {
    label: 'playing inspector uses a drawer overlay instead of relayouting workspace',
    pattern: /ZStack\(alignment: \.trailing\)[\s\S]*if shouldShowInspectorDrawer[\s\S]*inspectorDrawer[\s\S]*private var shouldShowInspectorDrawer: Bool[\s\S]*model\.workspaceMode == \.playing && model\.isInspectorVisible[\s\S]*private var inspectorDrawer:[\s\S]*\.frame\(width: 360\)[\s\S]*accessibilityLabel\("Mix inspector drawer"\)/
  },
  {
    label: 'add tracks toolbar action is hidden for empty playlists',
    pattern: /if !model\.playlist\.isEmpty\s*\{[\s\S]*Button\("Add Tracks", systemImage: "plus\.circle"\)/
  },
  {
    label: 'creative toolbar hides no-op inspector control',
    pattern: /if model\.workspaceMode == \.playing\s*\{[\s\S]*Button\(model\.isInspectorVisible \? "Hide Inspector" : "Inspector", systemImage: "sidebar\.right"\)/
  },
  {
    label: 'inspector pane has an in-pane close action',
    pattern: /private var inspectorContent:[\s\S]*centeredIconButton\([\s\S]*systemImage: "xmark"[\s\S]*accessibilityLabel: "Close mix inspector"[\s\S]*model\.isInspectorVisible = false/
  },
  {
    label: 'playlist empty state replaces table chrome',
    pattern: /if model\.playlist\.isEmpty\s*\{[\s\S]*emptyPanel\("No Tracks", systemImage: "music\.note"\)[\s\S]*\}\s*else\s*\{[\s\S]*Table\(model\.playlist/
  },
  {
    label: 'library empty state replaces table chrome',
    pattern: /if model\.filteredLibraryTracks\.isEmpty\s*\{[\s\S]*emptyPanel\(libraryEmptyTitle, systemImage: "rectangle\.stack"\)[\s\S]*\}\s*else\s*\{[\s\S]*Table\(model\.filteredLibraryTracks/
  },
  {
    label: 'library add-to-set action is hidden until a row is selected',
    pattern: /if model\.canAddSelectedLibraryTrackToPlaylist\s*\{[\s\S]*Button\("Add to Set", systemImage: "plus\.circle"\)/
  },
  {
    label: 'saved set actions are hidden until actionable',
    pattern: /private var shouldShowSavedSetActions: Bool[\s\S]*shouldShowSaveSetAction \|\| model\.canLoadSelectedSet/
  },
  {
    label: 'split pane minimum widths fit inside the content canvas or scroll fallback exists',
    test: splitPaneMinWidthsFitWindow
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
  status: (check.test ? check.test() : check.pattern.test(source)) ? 'pass' : 'fail'
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
