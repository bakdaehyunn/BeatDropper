#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const statusRank = {
  pass: 0,
  warn: 1,
  blocked: 2
};

const parseArgs = (argv) => {
  const options = {
    preRetirement: false,
    reportOnly: false,
    allowMissingExtendedStress: false
  };

  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') {
      process.stdout.write(
        [
          'Usage: node scripts/evaluate-native-parity.cjs [options]',
          '',
          'Options:',
          '  --pre-retirement                 Check native parity without requiring Electron to already be retired.',
          '  --report-only                    Print the parity report but exit 0 even when blockers remain.',
          '  --allow-missing-extended-stress  Allow quick local preflight runs to skip the extended session stress report.',
          '  --help                           Show this message.',
          ''
        ].join('\n')
      );
      process.exit(0);
    }
    if (arg === '--report-only') {
      options.reportOnly = true;
      continue;
    }
    if (arg === '--pre-retirement') {
      options.preRetirement = true;
      continue;
    }
    if (arg === '--allow-missing-extended-stress') {
      options.allowMissingExtendedStress = true;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
};

const readText = (relativePath) => {
  const filePath = path.join(rootDir, relativePath);
  return fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
};

const readJson = (relativePath) => {
  const filePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
};

const exists = (relativePath) => fs.existsSync(path.join(rootDir, relativePath));

const run = (command, args) => {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8'
  });
  return {
    ok: result.status === 0,
    status: result.status,
    output: `${result.stdout || ''}${result.stderr || ''}`.trim()
  };
};

const add = (checks, category, name, status, detail) => {
  checks.push({ category, name, status, detail });
};

const addFileCheck = (checks, category, relativePath) => {
  add(
    checks,
    category,
    relativePath,
    exists(relativePath) ? 'pass' : 'blocked',
    exists(relativePath) ? 'present' : 'missing'
  );
};

const addContainsCheck = (checks, category, relativePath, pattern, label) => {
  const text = readText(relativePath);
  const matched = pattern.test(text);
  add(
    checks,
    category,
    label,
    matched ? 'pass' : 'blocked',
    matched ? `${relativePath} contains expected evidence` : `${relativePath} lacks expected evidence`
  );
};

const addCombinedContainsCheck = (checks, category, relativePaths, pattern, label) => {
  const combinedText = relativePaths
    .map((relativePath) => `\n// ${relativePath}\n${readText(relativePath)}`)
    .join('\n');
  const matched = pattern.test(combinedText);
  add(
    checks,
    category,
    label,
    matched ? 'pass' : 'blocked',
    matched
      ? `${relativePaths.join(', ')} contain expected evidence`
      : `${relativePaths.join(', ')} lack expected evidence`
  );
};

const loadPackageJson = () => {
  const packagePath = path.join(rootDir, 'package.json');
  return JSON.parse(fs.readFileSync(packagePath, 'utf8'));
};

const getCodesignDetails = () => {
  const appPath = path.join(rootDir, 'native', 'dist', 'BeatDropper.app');
  if (!fs.existsSync(appPath)) {
    return { exists: false, verify: null, details: null };
  }

  return {
    exists: true,
    verify: run('codesign', ['--verify', '--deep', '--strict', appPath]),
    details: run('codesign', ['-dv', '--verbose=4', appPath])
  };
};

const main = () => {
  const options = parseArgs(process.argv.slice(2));
  const checks = [];
  const packageJson = loadPackageJson();
  const scripts = packageJson.scripts || {};

  for (const relativePath of [
    'native/Package.swift',
    'native/Packaging/Info.plist',
    'native/Sources/BeatDropperCore/NativeLibraryStore.swift',
    'native/Sources/BeatDropperCore/NativeLibraryMigration.swift',
    'native/Sources/BeatDropperCore/NativeLibraryReconciler.swift',
    'native/Sources/BeatDropperCore/NativeLibraryRelinkAssessment.swift',
    'native/Sources/BeatDropperCore/NativeLibraryBrowserIndex.swift',
    'native/Sources/BeatDropperCore/NativeLibraryStress.swift',
    'native/Sources/BeatDropperCore/NativeSettingsStore.swift',
    'native/Sources/BeatDropperCore/NativeDSPAnalyzer.swift',
    'native/Sources/BeatDropperCore/NativeAnalysisQueue.swift',
    'native/Sources/BeatDropperCore/NativePlannerBenchmark.swift',
    'native/Sources/BeatDropperCore/PlannerContract.swift',
    'native/Sources/BeatDropperCore/PlannerEvidence.swift',
    'native/Sources/BeatDropperCore/PlannerProcessOutput.swift',
    'native/Sources/BeatDropperCore/NativeFallbackMixPlanner.swift',
    'native/Sources/BeatDropperNative/NativeAudioEngine.swift',
    'native/Sources/BeatDropperNative/NativeMixPlanner.swift',
    'native/Sources/BeatDropperNative/BeatDropperNativeApp.swift',
    'native/Sources/BeatDropperNative/ContentView.swift',
    'native/Sources/BeatDropperNative/MixSettingsView.swift',
    'native/Sources/BeatDropperNativeLoudnessValidation/main.swift',
    'scripts/package-native-app.sh',
    'scripts/plan-electron-retirement.cjs',
    'scripts/run-native-local-preflight.cjs',
    'scripts/setup-native-release-profile.cjs',
    'scripts/smoke-native-dmg.cjs',
    'scripts/smoke-native-release.cjs',
    'scripts/write-native-release-manifest.cjs',
    'scripts/verify-native-release.cjs',
    'scripts/check-native-accessibility.cjs',
    'scripts/check-native-macos-shell.cjs',
    'scripts/evaluate-native-planner-benchmarks.cjs',
    'scripts/stress-native-library.cjs',
    'scripts/stress-native-open-import.cjs',
    'scripts/stress-native-playback.cjs',
    'scripts/stress-native-session.cjs',
    'scripts/validate-loudness-reference.cjs',
    'scripts/validate-native-real-folder.cjs',
    'scripts/codex-mix-planner.cjs'
  ]) {
    addFileCheck(checks, 'native structure', relativePath);
  }

  for (const scriptName of [
    'native:build',
    'native:accessibility:check',
    'native:macos-shell:check',
    'native:benchmark:analysis',
    'native:benchmark:analysis:gate',
    'native:benchmark:planner',
    'native:test',
    'native:package',
    'native:parity',
    'native:parity:report',
    'native:preflight:local',
    'native:preflight:release',
    'native:release',
    'native:release:check',
    'native:release:manifest',
    'native:release:setup',
    'native:release:setup:check',
    'native:release:smoke',
    'native:release:verify',
    'native:release:verify:local',
    'native:retire:check',
    'native:retire:plan',
    'native:smoke',
    'native:smoke:dmg',
    'native:stress:library',
    'native:stress:open-import',
    'native:stress:playback',
    'native:stress:session',
    'native:stress:session:extended',
    'native:validate:loudness-reference',
    'native:validate:real-folder'
  ]) {
    add(
      checks,
      'native commands',
      scriptName,
      scripts[scriptName] ? 'pass' : 'blocked',
      scripts[scriptName] || 'missing package script'
    );
  }

  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryStore.swift',
    /NativeLibrarySourceFolder/,
    'source folders persist in native library state'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryMigration.swift',
    /migrateElectronState[\s\S]*ElectronMusicLibraryFile[\s\S]*ElectronUserPlaylistFile/,
    'native can migrate Electron library and saved playlist files'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryStore.swift',
    /loadMigratingElectronStateIfNeeded/,
    'native store auto-migrates Electron state when native state is missing'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryStore.swift',
    /backupFileURL[\s\S]*loadState\(at: backupFileURL\)[\s\S]*writeCurrentStateBackup/,
    'native library persistence can recover human-curated sets from a backup when the primary store is corrupt'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Tests/BeatDropperCoreTests/NativeLibraryStoreTests.swift',
    /saveWritesBackupAndLoadFallsBackWhenPrimaryIsCorrupt/,
    'native library backup recovery has focused unit coverage'
  );
  addContainsCheck(
    checks,
    'settings parity',
    'native/Sources/BeatDropperCore/NativeSettingsStore.swift',
    /backupFileURL[\s\S]*loadSettings\(at: backupFileURL\)[\s\S]*writeCurrentSettingsBackup/,
    'native settings persistence can recover DJ preferences from backup when the primary store is corrupt or missing'
  );
  addContainsCheck(
    checks,
    'settings parity',
    'native/Tests/BeatDropperCoreTests/NativeSettingsStoreTests.swift',
    /saveWritesBackupAndLoadFallsBackWhenPrimaryIsCorrupt[\s\S]*loadFallsBackToBackupWhenPrimaryIsMissing/,
    'native settings backup recovery has focused unit coverage'
  );
  addContainsCheck(
    checks,
    'settings parity',
    'native/Sources/BeatDropperCore/NativeSettingsStore.swift',
    /loadMigratingElectronSettingsIfNeeded[\s\S]*player-settings\.json/,
    'native can migrate Electron player settings'
  );
  addContainsCheck(
    checks,
    'settings parity',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+AIMixPlanning.swift',
    /PlannerSettingsSnapshot[\s\S]*settings\.fadeDurationSec[\s\S]*settings\.aiDjMode/,
    'native planner request uses persisted mix settings'
  );
  addContainsCheck(
    checks,
    'settings parity',
    'native/Sources/BeatDropperNative/NativeAudioEngine.swift',
    /setMasterGain[\s\S]*mainMixerNode\.outputVolume/,
    'native audio engine applies persisted master gain'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryReconciler.swift',
    /markSourceFolderMissing/,
    'rescan can mark missing source folders'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+TrackState.swift',
    /isTrackAvailableForImmediateUse[\s\S]*FileManager\.default\.fileExists/,
    'missing files are guarded before playback and planning'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryReconciler.swift',
    /relinkTrack/,
    'native library can explicitly relink a missing track while preserving taste ids'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryRelinkAssessment.swift',
    /NativeLibraryRelinkAssessment[\s\S]*requiresUserConfirmation/,
    'native library assesses relink conflicts before changing a saved taste reference'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryRelinkAssessment.swift',
    /assessFolder[\s\S]*NativeLibraryFolderRelinkAssessment/,
    'native library assesses folder relink coverage before reconciling moved folders'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+LibraryWorkflow.swift',
    /confirmRelinkIfNeeded[\s\S]*NSAlert/,
    'native app requires confirmation for risky track relinks'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+LibraryWorkflow.swift',
    /confirmFolderRelinkIfNeeded[\s\S]*NSAlert/,
    'native app requires confirmation for risky folder relinks'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+LibraryWorkflow.swift',
    /relinkSelectedTrack[\s\S]*relinkMissingSourceFolder/,
    'native app exposes missing track and source folder relink flows'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNative/ContentView+CollectionPanes.swift',
    /Relink[\s\S]*Relink File/,
    'native UI offers explicit relink actions for unavailable library items'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNative/ContentView+CollectionPanes.swift',
    /libraryPane[\s\S]*Search library[\s\S]*Add to Set/,
    'native UI has a dedicated full-library browser that keeps playlist taste human-controlled'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+PlaylistManagement.swift',
    /addSelectedLibraryTrackToPlaylist[\s\S]*selectedLibraryTrack[\s\S]*addLibraryTrackToPlaylist/,
    'native app can browse the full library and add selected tracks to the current set'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryBrowserIndex.swift',
    /NativeLibraryBrowserIndex[\s\S]*searchKey[\s\S]*filter/,
    'native library browser uses a cached sorted index for larger library browsing'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperCore/NativeLibraryStress.swift',
    /NativeLibraryStressSuite[\s\S]*1_200[\s\S]*stablePlaylistReferenceCount/,
    'native library has large-library stress coverage for persistence, search, missing-folder marking, and moved-folder relink'
  );
  addContainsCheck(
    checks,
    'library parity',
    'scripts/stress-native-library.cjs',
    /BeatDropperNativeLibraryStress/,
    'native library stress command executes the Swift large-library stress suite'
  );
  addContainsCheck(
    checks,
    'library parity',
    'native/Sources/BeatDropperNativeLibraryStress/main.swift',
    /--write-json[\s\S]*LibraryStressReport[\s\S]*stablePlaylistReferenceCount/,
    'native library stress command writes durable large-library persistence evidence'
  );
  addCombinedContainsCheck(
    checks,
    'native DJ UX',
    [
      'native/Sources/BeatDropperNative/ContentView.swift',
      'native/Sources/BeatDropperNative/ContentView+CollectionPanes.swift',
      'native/Sources/BeatDropperNative/ContentView+PlayingMonitor.swift',
      'native/Sources/BeatDropperNative/ContentView+TransportStatus.swift'
    ],
    /accessibilityLabel\("BeatDropper DJ workspace"\)[\s\S]*accessibilityLabel\("Transport controls"\)/,
    'native DJ workspace exposes accessibility labels for major panes and transport controls'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'native/Sources/BeatDropperNative/BeatDropperNativeApp.swift',
    /WindowGroup\("BeatDropper"\)[\s\S]*\.commands[\s\S]*CommandMenu\("Set"\)[\s\S]*CommandMenu\("Playback"\)[\s\S]*CommandMenu\("Workspace"\)[\s\S]*Settings\s*\{[\s\S]*MixSettingsView\(\)/,
    'native app exposes macOS command menus and a standard Settings scene'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'native/Packaging/Info.plist',
    /CFBundleDocumentTypes[\s\S]*public\.audio[\s\S]*public\.mp3[\s\S]*com\.microsoft\.waveform-audio[\s\S]*public\.folder/,
    'native app declares Finder Open With support for audio files and music folders'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'native/Sources/BeatDropperNative/BeatDropperNativeApp.swift',
    /func application\(_ application: NSApplication, open urls: \[URL\]\)[\s\S]*openFinderItemsAsSet/,
    'native app delegate imports Finder-opened items'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+LibraryWorkflow.swift',
    /openFinderItemsAsSet[\s\S]*openDroppedItemsAsSet[\s\S]*classifyOpenURLs[\s\S]*replaceSetFromOpenSelection[\s\S]*upsertLibraryRecords[\s\S]*persistLibraryState\(\)[\s\S]*refreshAnalyses/,
    'Finder-opened and dropped items enter the library, playlist, persistence, and analysis pipeline'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'native/Sources/BeatDropperNative/ContentView+DropHandling.swift',
    /loadDroppedFileURLs[\s\S]*openDroppedItemsAsSet/,
    'native workspace accepts dragged audio files and folders'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'native/Sources/BeatDropperNative/BeatDropperNativeApp.swift',
    /BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS[\s\S]*runOpenImportStress[\s\S]*BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS_READY[\s\S]*private func runOpenImportStress\(\)[\s\S]*openExternalItemsForAutomation/,
    'packaged native app can run external open-import stress'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'scripts/stress-native-open-import.cjs',
    /--write-json[\s\S]*BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS[\s\S]*BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS_READY[\s\S]*opened[\s\S]*writeJsonReport/,
    'native open-import stress script verifies external import marker and writes durable evidence'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'scripts/check-native-macos-shell.cjs',
    /(?=[\s\S]*--write-json)(?=[\s\S]*Native macOS Shell Check)(?=[\s\S]*standard Settings scene exists)(?=[\s\S]*set commands expose playlist editing shortcuts)(?=[\s\S]*Info\.plist declares Finder-open audio and folder document types)(?=[\s\S]*workspace accepts dropped file URLs)(?=[\s\S]*main toolbar does not carry a settings popover)(?=[\s\S]*writeJsonReport)/,
    'native macOS shell check verifies menus, shortcuts, Settings scene, Finder-open, drag/drop, toolbar clutter, and writes durable evidence'
  );
  addContainsCheck(
    checks,
    'native DJ UX',
    'scripts/check-native-accessibility.cjs',
    /(?=[\s\S]*--write-json)(?=[\s\S]*Native Accessibility Check)(?=[\s\S]*workspace root label)(?=[\s\S]*Crossfade to next track)(?=[\s\S]*writeJsonReport)/,
    'native accessibility check verifies critical VoiceOver labels and writes durable evidence'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/NativeAudioEngine.swift',
    /AVAudioEngine[\s\S]*crossfadeTo/,
    'native two-deck AVAudioEngine crossfade exists'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/NativeAudioEngine.swift',
    /mainMixerNode\.installTap/,
    'native master output metering is wired to the audio graph'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/NativeAudioEngine.swift',
    /deckAMeter[\s\S]*deckBMeter[\s\S]*installAudioMeterTaps/,
    'native audio engine exposes per-deck meters from the audio graph'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/ContentView+PlayingMonitor.swift',
    /currentDeckMeter[\s\S]*nextDeckMeter/,
    'native DJ UI shows current and next deck meters'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/NativeAudioEngine.swift',
    /AVAudioEngineConfigurationChange[\s\S]*recoverAfterEngineConfigurationChange/,
    'native audio engine attempts recovery after device or configuration changes'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/BeatDropperNativeApp.swift',
    /BEATDROPPER_NATIVE_PLAYBACK_STRESS[\s\S]*waitUntil[\s\S]*crossfadeTo[\s\S]*resume[\s\S]*playbackStressSnapshot/,
    'packaged native app can run condition-based playback stress with diagnostics'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'scripts/stress-native-playback.cjs',
    /--write-json[\s\S]*BEATDROPPER_NATIVE_PLAYBACK_STRESS_READY[\s\S]*writeJsonReport/,
    'native playback stress script verifies packaged app playback marker and writes durable evidence'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/BeatDropperNativeApp.swift',
    /BEATDROPPER_NATIVE_SESSION_STRESS[\s\S]*importFolderForAutomation[\s\S]*waitUntil[\s\S]*requestMixPlan[\s\S]*playbackStressSnapshot/,
    'packaged native app can run condition-based real-session stress with diagnostics'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'scripts/stress-native-session.cjs',
    /--write-json[\s\S]*BEATDROPPER_NATIVE_SESSION_STRESS_READY[\s\S]*max analysis concurrency[\s\S]*writeJsonReport/,
    'native session stress script verifies import, analysis, planner, playback, and durable evidence'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'scripts/stress-native-session.cjs',
    /--extended[\s\S]*BEATDROPPER_NATIVE_SESSION_STRESS_TRACKS[\s\S]*transitions/,
    'native session stress can run a longer repeated transition loop'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'scripts/run-native-local-preflight.cjs',
    /stress-native-open-import\.cjs[\s\S]*--write-json[\s\S]*native\/dist\/open-import-stress-report\.json[\s\S]*stress-native-playback\.cjs[\s\S]*--write-json[\s\S]*native\/dist\/playback-stress-report\.json[\s\S]*stress-native-session\.cjs[\s\S]*--write-json[\s\S]*native\/dist\/session-stress-report\.json/,
    'native local preflight writes packaged open-import, playback, and session stress evidence'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'scripts/run-native-local-preflight.cjs',
    /--skip-extended-stress[\s\S]*session-stress-extended-report\.json[\s\S]*--allow-missing-extended-stress/,
    'native local preflight writes extended session stress evidence unless quick mode explicitly skips it'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperCore/PlaybackMath.swift',
    /PlaybackPositionMath[\s\S]*clampedElapsed[\s\S]*remaining/,
    'native playback position math clamps invalid long-session elapsed values'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperCore/PlaybackMath.swift',
    /CrossfadeMath[\s\S]*clampedProgress[\s\S]*equalPowerGains/,
    'native crossfade math sanitizes invalid progress before applying equal-power gains'
  );
  addContainsCheck(
    checks,
    'playback parity',
    'native/Sources/BeatDropperNative/NativeAudioEngine.swift',
    /startFadeTimer[\s\S]*clampedProgress[\s\S]*applyCrossfadeGains[\s\S]*clampedProgress/,
    'native audio engine clamps crossfade progress before timers and published state'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperCore/NativeDSPAnalyzer.swift',
    /spectralBands[\s\S]*transientMarkers[\s\S]*barGrid/,
    'native DSP emits spectral, transient, and bar evidence'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperCore/TrackAnalysis.swift',
    /trackAnalysisSchemaVersion\s*=\s*7/,
    'native DSP cache schema is bumped for harmonic key and loudness evidence upgrades'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Tests/BeatDropperCoreTests/NativeDSPAnalyzerTests.swift',
    /stableRMSFrequencyChangesBuildSpectralFluxTransients[\s\S]*frequencyStepSignal[\s\S]*hasTransient/,
    'native DSP has regression coverage for spectral-flux transients when RMS stays stable'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperCore/NativeDSPAnalyzer.swift',
    /buildPhraseMarkers[\s\S]*energySectionChangeScore[\s\S]*averageEnergy/,
    'native DSP phrase confidence uses section-change evidence'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Tests/BeatDropperCoreTests/NativeDSPAnalyzerTests.swift',
    /phraseConfidenceHighlightsEnergySectionChanges[\s\S]*sectionedPulseTrain/,
    'native DSP has regression coverage for phrase confidence on energy section changes'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperCore/NativeDSPAnalyzer.swift',
    /buildDownbeatGrid[\s\S]*spectralBands[\s\S]*lowBandDownbeatScore[\s\S]*spectralBandAt/,
    'native DSP downbeat phase scoring uses low-band spectral evidence'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Tests/BeatDropperCoreTests/NativeDSPAnalyzerTests.swift',
    /downbeatPhasePrefersLowBandKickOverLouderHighBandBackbeat[\s\S]*kickAndBackbeatPattern/,
    'native DSP has regression coverage for low-band downbeat phase detection'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperNativeAnalysisBenchmarks/main.swift',
    /allowExpectedGrades[\s\S]*writeJSONReport[\s\S]*gradeMismatches/,
    'native DSP benchmark gate allows expected weak fixtures while failing unexpected regressions'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperCore/NativeAnalysisQueue.swift',
    /NativeAnalysisQueueState[\s\S]*startAvailable[\s\S]*recommendedConcurrency/,
    'native DSP analysis uses a bounded work queue for larger libraries'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperNative/BeatDropperAppModel+AnalysisQueue.swift',
    /maxConcurrentAnalysisTasks[\s\S]*drainAnalysisQueue[\s\S]*syncAnalysisQueuePublishedState/,
    'native app drains DSP analysis work with bounded concurrency'
  );
  addContainsCheck(
    checks,
    'DSP parity',
    'native/Sources/BeatDropperNative/ContentView+Shell.swift',
    /analysisQueueStatus[\s\S]*Text\(analysisQueueStatus\)/,
    'native UI surfaces DSP analysis queue progress without adding another panel'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperCore/PlannerContract.swift',
    /analysisSummary[\s\S]*pairContext/,
    'native planner request carries summary evidence'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperCore/NativeFallbackMixPlanner.swift',
    /buildPlan[\s\S]*pairContext[\s\S]*local fallback/,
    'native has deterministic local fallback plans when the CLI planner fails'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperCore/NativeFallbackMixPlanner.swift',
    /candidateSort[\s\S]*sourceRank[\s\S]*evidenceRank[\s\S]*recommendedCandidateId/,
    'native fallback planner ranks analysis evidence before stale tail recommendations'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Tests/BeatDropperCoreTests/NativeFallbackMixPlannerTests.swift',
    /staleTailRecommendationDoesNotOverrideAnalysisCandidate[\s\S]*source analysis[\s\S]*phrase aligned/,
    'native fallback planner has regression coverage for stale tail recommendations'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperCore/PlannerProcessOutput.swift',
    /decodePlannerResponse[\s\S]*terminationStatus == 0[\s\S]*decoder\.decode\(PlannerResponse\.self/,
    'native planner bridge has a tested parser for CLI stdout/stderr/exit status'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Tests/BeatDropperCoreTests/PlannerProcessOutputTests.swift',
    /decodesValidStdoutEvenWhenStderrHasWarnings/,
    'native planner parser accepts valid stdout even when CLI stderr contains warnings'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperCore/NativePlannerBenchmark.swift',
    /NativePlannerBenchmarkSuite[\s\S]*requiredEvidence[\s\S]*cueRichCloseBPMCase[\s\S]*sparseBigGapCase[\s\S]*staleTailRecommendationCase/,
    'native fallback planner benchmark covers timing, candidate choice, and required evidence for cue-rich, sparse, stale-tail, and emergency cases'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperNativePlannerBenchmarks/main.swift',
    /(?=[\s\S]*PlannerBenchmarkReport)(?=[\s\S]*writeJSONReport)(?=[\s\S]*plan\.evidence\.joined)/,
    'native planner benchmark report writes durable JSON and prints fallback evidence strings'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'scripts/run-native-local-preflight.cjs',
    /native planner benchmark[\s\S]*--write-json[\s\S]*native\/dist\/planner-benchmark-report\.json/,
    'native local preflight writes planner benchmark evidence'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'scripts/evaluate-native-planner-benchmarks.cjs',
    /BeatDropperNativePlannerBenchmarks/,
    'native planner benchmark command executes the Swift benchmark suite'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperNative/NativeMixPlanner.swift',
    /NativeFallbackMixPlanner\.buildPlan/,
    'native planner bridge invokes local fallback after CLI planner failure'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'native/Sources/BeatDropperNative/NativeMixPlanner.swift',
    /(?=[\s\S]*Runtime\/node)(?=[\s\S]*defaultSearchPaths)(?=[\s\S]*\/opt\/homebrew\/bin)(?=[\s\S]*plannerProcessEnvironment)/,
    'native planner bridge prefers bundled Node and augments PATH for GUI-launched macOS apps'
  );
  addContainsCheck(
    checks,
    'planner parity',
    'scripts/codex-mix-planner.cjs',
    /Prefer analysisSummary and pairContext[\s\S]*Preparation hints:[\s\S]*human intent/,
    'planner prompt prefers summary, pair context, and user prep evidence'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/package-native-app.sh',
    /NOTARIZE[\s\S]*notarytool[\s\S]*hdiutil create/,
    'package script supports notarization and dmg creation'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/package-native-app.sh',
    /package\.json[\s\S]*CFBundleShortVersionString[\s\S]*CFBundleVersion/,
    'package script writes package version metadata into the app bundle Info.plist'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/package-native-app.sh',
    /(?=[\s\S]*NODE_BINARY)(?=[\s\S]*RUNTIME_RESOURCES_DIR="\$RESOURCES_DIR\/Runtime")(?=[\s\S]*cp "\$NODE_BINARY" "\$RUNTIME_RESOURCES_DIR\/node")/,
    'package script bundles a Node runtime for the native planner bridge'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/package-native-app.sh',
    /(?=[\s\S]*THIRD_PARTY_RESOURCES_DIR="\$RESOURCES_DIR\/ThirdParty")(?=[\s\S]*NODE_LICENSE_FILE)(?=[\s\S]*Node-LICENSE\.txt)(?=[\s\S]*THIRD-PARTY-NOTICES\.txt)/,
    'package script bundles third-party notices for the Node planner runtime'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/run-native-local-preflight.cjs',
    /verify-native-release\.cjs[\s\S]*stress-native-open-import\.cjs[\s\S]*stress-native-session\.cjs[\s\S]*evaluate-native-parity\.cjs/,
    'local native preflight verifies package, stress, and parity gates before release signing'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/smoke-native-dmg.cjs',
    /hdiutil[\s\S]*attach[\s\S]*BEATDROPPER_NATIVE_SMOKE_READY[\s\S]*detach/,
    'native DMG smoke verifies mounted distribution launch'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/smoke-native-release.cjs',
    /(?=[\s\S]*release-smoke-report\.json)(?=[\s\S]*releaseManifest)(?=[\s\S]*source: manifest\.source)(?=[\s\S]*signing: manifest\.signing)(?=[\s\S]*thirdPartyNotice)(?=[\s\S]*nodeLicense)(?=[\s\S]*smoke-native-app\.cjs)(?=[\s\S]*smoke-native-dmg\.cjs)(?=[\s\S]*runInstalledAppSmoke)/,
    'native release smoke writes durable packaged, DMG, installed launch, source provenance, and bundled runtime notice evidence'
  );
  add(
    checks,
    'packaging parity',
    'native release runs post-release smoke',
    /native:release:smoke/.test(scripts['native:release'] || '') &&
      /smoke-native-release\.cjs/.test(scripts['native:release:smoke'] || '')
      ? 'pass'
      : 'blocked',
      /native:release:smoke/.test(scripts['native:release'] || '') &&
      /smoke-native-release\.cjs/.test(scripts['native:release:smoke'] || '')
      ? 'native:release writes packaged, DMG, and installed smoke evidence after strict release verification'
      : 'native:release must record final packaged, mounted DMG, and installed launch-smoke evidence after strict release verification'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/run-native-local-preflight.cjs',
    /strictRelease[\s\S]*release-preflight-report\.json[\s\S]*strict native release readiness/,
    'strict native release preflight requires signing readiness before notarization'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/plan-electron-retirement.cjs',
    /electronSourcePaths[\s\S]*dependenciesToRemove[\s\S]*native:retire:check/,
    'Electron retirement has a dry-run removal plan before deletion'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/check-electron-retirement-readiness.cjs',
    /(?=[\s\S]*electron-retirement-readiness-report\.json)(?=[\s\S]*Strict release verification report)(?=[\s\S]*Info\.plist package version)(?=[\s\S]*installed Info\.plist package version)(?=[\s\S]*writeFileSync)/,
    'Electron retirement readiness writes durable evidence and requires strict release version metadata evidence'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/setup-native-release-profile.cjs',
    /NOTARY_KEYCHAIN_PROFILE[\s\S]*notarytool[\s\S]*store-credentials/,
    'native release setup can store a notary keychain profile'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/check-native-release-readiness.cjs',
    /notarytool[\s\S]*history[\s\S]*Notary credential validation/,
    'native release readiness validates configured notary credentials before release'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/check-native-release-readiness.cjs',
    /Node runtime for planner bridge[\s\S]*Codex CLI for AI planner bridge[\s\S]*Bundled planner script syntax[\s\S]*Bundled Node runtime for packaged app[\s\S]*Bundled Node codesign verification[\s\S]*Bundled Node dependency closure[\s\S]*Bundled Node third-party notices[\s\S]*Bundled Node license notice/,
    'native release readiness verifies AI planner bridge runtime prerequisites and bundled runtime notices'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/check-native-release-readiness.cjs',
    /release-readiness-report\.json[\s\S]*Current app Info\.plist package version[\s\S]*Current release manifest Info\.plist version metadata/,
    'native release readiness writes durable evidence and checks bundle version metadata'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/check-native-release-readiness.cjs',
    /(?=[\s\S]*analysis-benchmark-report\.json)(?=[\s\S]*planner-benchmark-report\.json)(?=[\s\S]*accessibility-check-report\.json)(?=[\s\S]*macos-shell-check-report\.json)(?=[\s\S]*library-stress-report\.json)(?=[\s\S]*open-import-stress-report\.json)(?=[\s\S]*playback-stress-report\.json)(?=[\s\S]*session-stress-report\.json)(?=[\s\S]*session-stress-extended-report\.json)(?=[\s\S]*Current analysis benchmark report)(?=[\s\S]*Current extended session stress report)/,
    'native release readiness requires durable local quality evidence before release'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/check-native-release-readiness.cjs',
    /Current release manifest source provenance[\s\S]*source revision matches current checkout[\s\S]*source tree clean for release/,
    'native release readiness verifies source provenance evidence'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/verify-native-release.cjs',
    /(?=[\s\S]*release-verification-report\.json)(?=[\s\S]*stapler)(?=[\s\S]*Gatekeeper)(?=[\s\S]*Developer ID)(?=[\s\S]*notary submission evidence)(?=[\s\S]*bundled planner script syntax)(?=[\s\S]*bundled Node codesign verification)(?=[\s\S]*bundled Node dependency closure)(?=[\s\S]*third-party notice)(?=[\s\S]*Node license)(?=[\s\S]*manifest source provenance)(?=[\s\S]*source tree clean for release)(?=[\s\S]*quarantineAttributeValue)(?=[\s\S]*zip app quarantined Gatekeeper assessment)(?=[\s\S]*installed quarantined app Gatekeeper assessment)/,
    'post-release verifier records notarization logs, Gatekeeper, Developer ID, source provenance, runtime notice, quarantine, ZIP-app, and installed-app evidence'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/write-native-release-manifest.cjs',
    /(?=[\s\S]*buildGitProvenance)(?=[\s\S]*buildEnvironmentProvenance)(?=[\s\S]*infoPlistMetadata)(?=[\s\S]*bundledNodeRuntime)(?=[\s\S]*thirdPartyNotice)(?=[\s\S]*nodeLicense)(?=[\s\S]*CFBundleShortVersionString)(?=[\s\S]*packageVersion)/,
    'release manifest records app bundle version metadata, source provenance, and bundled runtime notice evidence'
  );
  addContainsCheck(
    checks,
    'packaging parity',
    'scripts/verify-native-release.cjs',
    /Info\.plist package version[\s\S]*zip app Info\.plist package version[\s\S]*installed Info\.plist package version/,
    'post-release verifier checks app, ZIP, and installed Info.plist version metadata'
  );

  for (const relativePath of [
    'native/dist/BeatDropper.app',
    'native/dist/BeatDropper.zip',
    'native/dist/BeatDropper.dmg',
    'native/dist/release-manifest.json'
  ]) {
    addFileCheck(checks, 'distribution artifacts', relativePath);
  }

  const codesign = getCodesignDetails();
  if (codesign.exists) {
    add(
      checks,
      'distribution artifacts',
      'codesign verification',
      codesign.verify.ok ? 'pass' : 'blocked',
      codesign.verify.ok ? 'codesign --verify passed' : codesign.verify.output || 'codesign verify failed'
    );

    const detailsOutput = codesign.details?.output || '';
    const hasDeveloperId = /Authority=Developer ID Application:/.test(detailsOutput);
    const isAdhoc = /Signature=adhoc/.test(detailsOutput);
    add(
      checks,
      'release blockers',
      'Developer ID signing',
      hasDeveloperId ? 'pass' : 'blocked',
      hasDeveloperId
        ? 'Developer ID Application authority found'
        : isAdhoc
          ? 'current app is ad-hoc signed'
          : 'Developer ID Application authority not found'
    );

    const spctl = run('spctl', ['--assess', '--type', 'execute', '--verbose', path.join(rootDir, 'native', 'dist', 'BeatDropper.app')]);
    add(
      checks,
      'release blockers',
      'Gatekeeper assessment',
      spctl.ok ? 'pass' : 'blocked',
      spctl.ok ? 'spctl accepted app' : spctl.output || 'spctl assessment failed'
    );
  } else {
    add(
      checks,
      'distribution artifacts',
      'codesign verification',
      'blocked',
      'native/dist/BeatDropper.app does not exist; run npm run native:package'
    );
  }

  if (exists('native/dist/BeatDropper.dmg')) {
  const dmgVerify = run('hdiutil', ['verify', path.join(rootDir, 'native', 'dist', 'BeatDropper.dmg')]);
    add(
      checks,
      'distribution artifacts',
      'dmg verification',
      dmgVerify.ok ? 'pass' : 'blocked',
      dmgVerify.ok ? 'hdiutil verify passed' : dmgVerify.output || 'hdiutil verify failed'
    );
  }

  const releaseManifest = readJson('native/dist/release-manifest.json');
  const releaseSmokeReport = readJson('native/dist/release-smoke-report.json');
  const analysisBenchmarkReport = readJson('native/dist/analysis-benchmark-report.json');
  const plannerBenchmarkReport = readJson('native/dist/planner-benchmark-report.json');
  const accessibilityCheckReport = readJson('native/dist/accessibility-check-report.json');
  const macosShellCheckReport = readJson('native/dist/macos-shell-check-report.json');
  const libraryStressReport = readJson('native/dist/library-stress-report.json');
  const openImportStressReport = readJson('native/dist/open-import-stress-report.json');
  const playbackStressReport = readJson('native/dist/playback-stress-report.json');
  const sessionStressReport = readJson('native/dist/session-stress-report.json');
  const extendedSessionStressReport = readJson('native/dist/session-stress-extended-report.json');
  const strictReleaseVerificationReport = readJson('native/dist/release-verification-report.json');
  const analysisBenchmarkPassed =
    analysisBenchmarkReport?.schemaVersion === 1 &&
    analysisBenchmarkReport?.status === 'PASS' &&
    analysisBenchmarkReport?.allowExpectedGrades === true &&
    Array.isArray(analysisBenchmarkReport?.gradeMismatches) &&
    analysisBenchmarkReport.gradeMismatches.length === 0 &&
    Array.isArray(analysisBenchmarkReport?.suite?.results) &&
    analysisBenchmarkReport.suite.results.length >= 3 &&
    analysisBenchmarkReport.suite.results.every(
      (result) => result?.expectedGrade && result?.result?.grade === result.expectedGrade
    );
  add(
    checks,
    'distribution artifacts',
    'analysis benchmark report',
    analysisBenchmarkPassed ? 'pass' : 'blocked',
    analysisBenchmarkPassed
      ? 'native/dist/analysis-benchmark-report.json records passing expected-grade DSP fixture evidence'
      : 'run npm run native:benchmark:analysis:gate before parity/preflight'
  );
  const plannerBenchmarkEvidence = (plannerBenchmarkReport?.results || [])
    .flatMap((result) => result?.plan?.evidence || []);
  const plannerBenchmarkPassed =
    Number(plannerBenchmarkReport?.schemaVersion) >= 1 &&
    plannerBenchmarkReport?.status === 'PASS' &&
    plannerBenchmarkReport?.summary?.passCount >= 6 &&
    plannerBenchmarkReport?.summary?.failCount === 0 &&
    plannerBenchmarkEvidence.some((evidence) => /source analysis/i.test(evidence)) &&
    plannerBenchmarkEvidence.some((evidence) => /planner failure/i.test(evidence));
  add(
    checks,
    'distribution artifacts',
    'planner benchmark report',
    plannerBenchmarkPassed ? 'pass' : 'blocked',
    plannerBenchmarkPassed
      ? 'native/dist/planner-benchmark-report.json records passing fallback planner cases with analysis-source and planner-failure evidence'
      : 'run npm run native:benchmark:planner -- --write-json native/dist/planner-benchmark-report.json before parity/preflight'
  );
  const accessibilityCheckPassed =
    accessibilityCheckReport?.schemaVersion === 1 &&
    accessibilityCheckReport?.kind === 'accessibility-check' &&
    accessibilityCheckReport?.status === 'PASS' &&
    Number(accessibilityCheckReport?.summary?.checkCount) >= 17 &&
    Number(accessibilityCheckReport?.summary?.failCount) === 0;
  add(
    checks,
    'distribution artifacts',
    'accessibility check report',
    accessibilityCheckPassed ? 'pass' : 'blocked',
    accessibilityCheckPassed
      ? 'native/dist/accessibility-check-report.json records passing VoiceOver label evidence'
      : 'run node scripts/check-native-accessibility.cjs --write-json native/dist/accessibility-check-report.json before parity/preflight'
  );
  const macosShellCheckPassed =
    macosShellCheckReport?.schemaVersion === 1 &&
    macosShellCheckReport?.kind === 'macos-shell-check' &&
    macosShellCheckReport?.status === 'PASS' &&
    Number(macosShellCheckReport?.summary?.checkCount) >= 15 &&
    Number(macosShellCheckReport?.summary?.failCount) === 0;
  add(
    checks,
    'distribution artifacts',
    'macOS shell check report',
    macosShellCheckPassed ? 'pass' : 'blocked',
    macosShellCheckPassed
      ? 'native/dist/macos-shell-check-report.json records passing command menu, Settings, Finder Open With, drag/drop, and toolbar-clutter evidence'
      : 'run node scripts/check-native-macos-shell.cjs --write-json native/dist/macos-shell-check-report.json before parity/preflight'
  );
  const libraryStressTrackCount = Number(libraryStressReport?.result?.trackCount) || 0;
  const libraryStressPassed =
    libraryStressReport?.schemaVersion === 1 &&
    libraryStressReport?.kind === 'library-stress' &&
    libraryStressReport?.status === 'PASS' &&
    libraryStressTrackCount >= 1_200 &&
    Number(libraryStressReport?.result?.savedSetCount) > 0 &&
    Number(libraryStressReport?.result?.indexedCount) === libraryStressTrackCount &&
    Number(libraryStressReport?.result?.searchHitCount) > 0 &&
    Number(libraryStressReport?.result?.missingCount) === libraryStressTrackCount &&
    Number(libraryStressReport?.result?.relinkedCount) === libraryStressTrackCount &&
    Number(libraryStressReport?.result?.stablePlaylistReferenceCount) >= 64;
  add(
    checks,
    'distribution artifacts',
    'library stress report',
    libraryStressPassed ? 'pass' : 'blocked',
    libraryStressPassed
      ? 'native/dist/library-stress-report.json records passing large-library persistence, search, missing-folder, relink, and stable playlist reference evidence'
      : 'run node scripts/stress-native-library.cjs --write-json native/dist/library-stress-report.json before parity/preflight'
  );
  const openImportStressPassed =
    openImportStressReport?.schemaVersion === 1 &&
    openImportStressReport?.kind === 'open-import-stress' &&
    openImportStressReport?.status === 'PASS' &&
    openImportStressReport?.result?.opened === 3 &&
    openImportStressReport?.result?.library === 3 &&
    openImportStressReport?.result?.sourceFolders === 1 &&
    Number(openImportStressReport?.result?.analyzed) >= 3 &&
    openImportStressReport?.result?.finalState === 'Idle' &&
    openImportStressReport?.launch?.ok === true;
  add(
    checks,
    'distribution artifacts',
    'open-import stress report',
    openImportStressPassed ? 'pass' : 'blocked',
    openImportStressPassed
      ? 'native/dist/open-import-stress-report.json records passing packaged Finder/Open With import evidence'
      : 'run node scripts/stress-native-open-import.cjs --write-json native/dist/open-import-stress-report.json before parity/preflight'
  );
  const playbackStressPassed =
    playbackStressReport?.schemaVersion === 1 &&
    playbackStressReport?.kind === 'playback-stress' &&
    playbackStressReport?.status === 'PASS' &&
    playbackStressReport?.result?.finalState === 'Idle' &&
    playbackStressReport?.launch?.ok === true;
  add(
    checks,
    'distribution artifacts',
    'playback stress report',
    playbackStressPassed ? 'pass' : 'blocked',
    playbackStressPassed
      ? 'native/dist/playback-stress-report.json records passing packaged playback stress evidence'
      : 'run node scripts/stress-native-playback.cjs --write-json native/dist/playback-stress-report.json before parity/preflight'
  );
  const expectedSessionTransitions = Math.min(
    Number(sessionStressReport?.stress?.transitionCount) || 0,
    Math.max(0, (Number(sessionStressReport?.result?.imported) || 0) - 1)
  );
  const sessionStressPassed =
    sessionStressReport?.schemaVersion === 1 &&
    sessionStressReport?.kind === 'session-stress' &&
    sessionStressReport?.status === 'PASS' &&
    sessionStressReport?.stress?.mode === 'normal' &&
    sessionStressReport?.result?.finalState === 'Idle' &&
    Number(sessionStressReport?.result?.imported) >= Number(sessionStressReport?.stress?.trackCount) &&
    Number(sessionStressReport?.result?.analyzed) >= Number(sessionStressReport?.result?.imported) &&
    Number(sessionStressReport?.result?.maxRunning) >= 1 &&
    Number(sessionStressReport?.result?.maxRunning) <= 4 &&
    Number(sessionStressReport?.result?.planConfidence) > 0 &&
    Number(sessionStressReport?.result?.transitions) >= expectedSessionTransitions &&
    sessionStressReport?.launch?.ok === true;
  add(
    checks,
    'distribution artifacts',
    'session stress report',
    sessionStressPassed ? 'pass' : 'blocked',
    sessionStressPassed
      ? 'native/dist/session-stress-report.json records passing packaged import, analysis, planner, playback, and transition evidence'
      : 'run node scripts/stress-native-session.cjs --write-json native/dist/session-stress-report.json before parity/preflight'
  );
  const expectedExtendedSessionTransitions = Math.min(
    Number(extendedSessionStressReport?.stress?.transitionCount) || 0,
    Math.max(0, (Number(extendedSessionStressReport?.result?.imported) || 0) - 1)
  );
  const extendedSessionStressPassed =
    extendedSessionStressReport?.schemaVersion === 1 &&
    extendedSessionStressReport?.kind === 'session-stress' &&
    extendedSessionStressReport?.status === 'PASS' &&
    extendedSessionStressReport?.stress?.mode === 'extended' &&
    extendedSessionStressReport?.stress?.extended === true &&
    Number(extendedSessionStressReport?.stress?.trackCount) >= 12 &&
    Number(extendedSessionStressReport?.stress?.transitionCount) >= 6 &&
    extendedSessionStressReport?.result?.finalState === 'Idle' &&
    Number(extendedSessionStressReport?.result?.imported) >= Number(extendedSessionStressReport?.stress?.trackCount) &&
    Number(extendedSessionStressReport?.result?.analyzed) >= Number(extendedSessionStressReport?.result?.imported) &&
    Number(extendedSessionStressReport?.result?.maxRunning) >= 1 &&
    Number(extendedSessionStressReport?.result?.maxRunning) <= 4 &&
    Number(extendedSessionStressReport?.result?.planConfidence) > 0 &&
    Number(extendedSessionStressReport?.result?.transitions) >= expectedExtendedSessionTransitions &&
    extendedSessionStressReport?.launch?.ok === true;
  add(
    checks,
    'distribution artifacts',
    'extended session stress report',
    extendedSessionStressPassed || (options.allowMissingExtendedStress && !extendedSessionStressReport)
      ? 'pass'
      : 'blocked',
    extendedSessionStressPassed
      ? 'native/dist/session-stress-extended-report.json records passing repeated packaged import, analysis, planner, playback, and transition evidence'
      : options.allowMissingExtendedStress && !extendedSessionStressReport
        ? 'skipped by quick local preflight; default parity still requires native/dist/session-stress-extended-report.json'
        : 'run node scripts/stress-native-session.cjs --extended --write-json native/dist/session-stress-extended-report.json before parity/preflight'
  );
  add(
    checks,
    'distribution artifacts',
    'release manifest schema',
    releaseManifest?.schemaVersion === 1 ? 'pass' : 'blocked',
    releaseManifest?.schemaVersion === 1
      ? 'release manifest schema v1 is present'
      : 'native/dist/release-manifest.json is missing or invalid'
  );
  add(
    checks,
    'distribution artifacts',
    'release manifest checksums',
    releaseManifest?.artifacts?.zip?.sha256 &&
    releaseManifest?.artifacts?.dmg?.sha256 &&
    releaseManifest?.artifacts?.app?.executable?.sha256 &&
    releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
    releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 &&
    releaseManifest?.artifacts?.app?.nodeLicense?.sha256
      ? 'pass'
      : 'blocked',
    releaseManifest?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256
      ? 'zip, dmg, app executable, bundled Node, and bundled runtime notice checksums are recorded'
      : 'release manifest must record zip, dmg, app executable, bundled Node, and bundled runtime notice checksums'
  );
  add(
    checks,
    'distribution artifacts',
    'release manifest Info.plist version metadata',
    releaseManifest?.packageVersion === packageJson.version &&
      releaseManifest?.artifacts?.app?.infoPlistMetadata?.shortVersion === packageJson.version &&
      /^[0-9]+([.][0-9]+){0,2}$/.test(releaseManifest?.artifacts?.app?.infoPlistMetadata?.bundleVersion || '')
      ? 'pass'
      : 'blocked',
    releaseManifest?.packageVersion === packageJson.version &&
      releaseManifest?.artifacts?.app?.infoPlistMetadata?.shortVersion === packageJson.version &&
      /^[0-9]+([.][0-9]+){0,2}$/.test(releaseManifest?.artifacts?.app?.infoPlistMetadata?.bundleVersion || '')
      ? 'release manifest records app Info.plist version metadata matching package.json'
      : 'release manifest must record packageVersion and app Info.plist version metadata'
  );
  add(
    checks,
    'distribution artifacts',
    'release manifest source provenance',
    /^[a-f0-9]{40}$/i.test(releaseManifest?.source?.git?.commit || '') &&
      typeof releaseManifest?.source?.git?.isDirty === 'boolean' &&
      Number.isInteger(releaseManifest?.source?.git?.statusEntryCount) &&
      releaseManifest?.source?.environment?.nodeVersion &&
      releaseManifest?.source?.environment?.xcodebuildVersion &&
      releaseManifest?.source?.environment?.swiftVersion &&
      releaseManifest?.source?.environment?.macOSVersion &&
      releaseManifest?.source?.environment?.architecture
      ? 'pass'
      : 'blocked',
    /^[a-f0-9]{40}$/i.test(releaseManifest?.source?.git?.commit || '') &&
      typeof releaseManifest?.source?.git?.isDirty === 'boolean' &&
      Number.isInteger(releaseManifest?.source?.git?.statusEntryCount) &&
      releaseManifest?.source?.environment?.nodeVersion &&
      releaseManifest?.source?.environment?.xcodebuildVersion &&
      releaseManifest?.source?.environment?.swiftVersion &&
      releaseManifest?.source?.environment?.macOSVersion &&
      releaseManifest?.source?.environment?.architecture
      ? `release manifest records source commit ${releaseManifest.source.git.shortCommit || releaseManifest.source.git.commit.slice(0, 12)} and build toolchain provenance`
      : 'release manifest must record git source and build toolchain provenance'
  );
  add(
    checks,
    'distribution artifacts',
    'release manifest verification evidence',
    releaseManifest?.verification?.appCodesign?.ok === true &&
      releaseManifest?.verification?.dmgVerify?.ok === true
      ? 'pass'
      : 'blocked',
    releaseManifest?.verification?.appCodesign?.ok === true &&
      releaseManifest?.verification?.dmgVerify?.ok === true
      ? 'release manifest records passing app codesign and DMG verification'
      : 'release manifest must record passing app codesign and DMG verification'
  );
  const releaseSmokePassed =
    releaseSmokeReport?.schemaVersion === 1 &&
    releaseSmokeReport?.status === 'PASS' &&
    releaseManifest?.packageVersion === releaseSmokeReport?.releaseManifest?.packageVersion &&
    releaseManifest?.source?.git?.commit === releaseSmokeReport?.releaseManifest?.source?.git?.commit &&
    releaseManifest?.source?.git?.isDirty === releaseSmokeReport?.releaseManifest?.source?.git?.isDirty &&
    releaseManifest?.source?.environment?.xcodebuildVersion === releaseSmokeReport?.releaseManifest?.source?.environment?.xcodebuildVersion &&
    releaseManifest?.signing?.notarizeRequested === releaseSmokeReport?.releaseManifest?.signing?.notarizeRequested &&
    releaseManifest?.releaseMode === releaseSmokeReport?.releaseManifest?.releaseMode &&
    releaseManifest?.artifacts?.manifest?.path === releaseSmokeReport?.artifacts?.manifest?.path &&
    releaseManifest?.artifacts?.zip?.sha256 === releaseSmokeReport?.artifacts?.zip?.sha256 &&
    releaseManifest?.artifacts?.dmg?.sha256 === releaseSmokeReport?.artifacts?.dmg?.sha256 &&
    releaseManifest?.artifacts?.app?.executable?.sha256 === releaseSmokeReport?.artifacts?.app?.executable?.sha256 &&
    releaseManifest?.artifacts?.app?.infoPlist?.sha256 === releaseSmokeReport?.artifacts?.app?.infoPlist?.sha256 &&
    releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === releaseSmokeReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
    releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === releaseSmokeReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
    releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === releaseSmokeReport?.artifacts?.app?.nodeLicense?.sha256 &&
    releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === releaseSmokeReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
    releaseSmokeReport?.steps?.some((step) => step.label === 'packaged app smoke' && step.outcome === 'pass') &&
    releaseSmokeReport?.steps?.some((step) => step.label === 'mounted DMG smoke' && step.outcome === 'pass') &&
    releaseSmokeReport?.steps?.some((step) => step.label === 'installed app smoke' && step.outcome === 'pass');
  add(
    checks,
    'distribution artifacts',
    'release smoke report',
    releaseSmokePassed ? 'pass' : 'blocked',
    releaseSmokePassed
      ? 'native/dist/release-smoke-report.json records passing launch smoke for the current manifest checksums and source provenance'
      : 'run npm run native:release:smoke after packaging to record launch evidence for the current manifest checksums and source provenance'
  );

  const localReleaseVerify = run('node', [
    'scripts/verify-native-release.cjs',
    '--allow-ad-hoc',
    '--report-only'
  ]);
  const localReleaseVerificationReport = readJson('native/dist/local-release-verification-report.json');
  add(
    checks,
    'distribution artifacts',
    'local post-release verification',
    localReleaseVerify.ok && /^status (PASS|WARN)$/m.test(localReleaseVerify.output) ? 'pass' : 'blocked',
    localReleaseVerify.ok
      ? (localReleaseVerify.output.match(/^status .+$/m)?.[0] || 'local release verifier ran')
      : localReleaseVerify.output || 'local post-release verification failed'
  );
  add(
    checks,
    'distribution artifacts',
    'local release verification report',
    localReleaseVerificationReport?.schemaVersion === 1 &&
      /^(PASS|WARN)$/.test(localReleaseVerificationReport.status || '') &&
      releaseManifest?.artifacts?.zip?.sha256 === localReleaseVerificationReport?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 === localReleaseVerificationReport?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 === localReleaseVerificationReport?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.infoPlist?.sha256 === localReleaseVerificationReport?.artifacts?.app?.infoPlist?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === localReleaseVerificationReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === localReleaseVerificationReport?.artifacts?.app?.nodeLicense?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest source provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest build toolchain provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source revision matches current checkout' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source tree clean for release' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled planner script syntax' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node runtime execution' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node dependency closure' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node runtime' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node codesign' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node dependencies' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app extraction' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Finder-open document types' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app copy' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Finder-open document types' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node runtime' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node codesign' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node dependencies' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed quarantined app Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app codesign verification' && check.status === 'pass')
      ? 'pass'
      : 'blocked',
    localReleaseVerificationReport?.schemaVersion === 1 &&
      /^(PASS|WARN)$/.test(localReleaseVerificationReport.status || '') &&
      releaseManifest?.artifacts?.zip?.sha256 === localReleaseVerificationReport?.artifacts?.zip?.sha256 &&
      releaseManifest?.artifacts?.dmg?.sha256 === localReleaseVerificationReport?.artifacts?.dmg?.sha256 &&
      releaseManifest?.artifacts?.app?.executable?.sha256 === localReleaseVerificationReport?.artifacts?.app?.executable?.sha256 &&
      releaseManifest?.artifacts?.app?.infoPlist?.sha256 === localReleaseVerificationReport?.artifacts?.app?.infoPlist?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
      releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === localReleaseVerificationReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
      releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === localReleaseVerificationReport?.artifacts?.app?.nodeLicense?.sha256 &&
      releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === localReleaseVerificationReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest source provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest build toolchain provenance' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source revision matches current checkout' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'source tree clean for release' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled planner script syntax' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node runtime execution' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node dependency closure' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node runtime' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node codesign' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node dependencies' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG quarantined Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app extraction' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Finder-open document types' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app codesign verification' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app copy' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist validation' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Finder-open document types' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist package version' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node runtime' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node codesign' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node dependencies' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed third-party notice' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Node license' && check.status === 'pass') &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed quarantined app Gatekeeper assessment' && /^(pass|warn)$/.test(check.status || '')) &&
      localReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app codesign verification' && check.status === 'pass')
      ? 'native/dist/local-release-verification-report.json records passing local ZIP, source provenance, quarantine simulation, bundled runtime notices, Finder-open, version metadata, and installed-app verification for the current manifest checksums'
      : 'local release verifier must write native/dist/local-release-verification-report.json for the current manifest checksums'
  );

  const strictReleaseVerificationPassed =
    strictReleaseVerificationReport?.schemaVersion === 1 &&
    strictReleaseVerificationReport?.status === 'PASS' &&
    strictReleaseVerificationReport?.mode === 'strict-release' &&
    releaseManifest?.artifacts?.zip?.sha256 === strictReleaseVerificationReport?.artifacts?.zip?.sha256 &&
    releaseManifest?.artifacts?.dmg?.sha256 === strictReleaseVerificationReport?.artifacts?.dmg?.sha256 &&
    releaseManifest?.artifacts?.app?.executable?.sha256 === strictReleaseVerificationReport?.artifacts?.app?.executable?.sha256 &&
    releaseManifest?.artifacts?.app?.infoPlist?.sha256 === strictReleaseVerificationReport?.artifacts?.app?.infoPlist?.sha256 &&
    releaseManifest?.artifacts?.app?.bundledNodeRuntime?.sha256 === strictReleaseVerificationReport?.artifacts?.app?.bundledNodeRuntime?.sha256 &&
    releaseManifest?.artifacts?.app?.thirdPartyNotice?.sha256 === strictReleaseVerificationReport?.artifacts?.app?.thirdPartyNotice?.sha256 &&
    releaseManifest?.artifacts?.app?.nodeLicense?.sha256 === strictReleaseVerificationReport?.artifacts?.app?.nodeLicense?.sha256 &&
    releaseManifest?.artifacts?.app?.bundledPlannerScript?.sha256 === strictReleaseVerificationReport?.artifacts?.app?.bundledPlannerScript?.sha256 &&
    releaseManifest?.artifacts?.notaryEvidence?.zipSubmit?.sha256 === strictReleaseVerificationReport?.artifacts?.notaryEvidence?.zipSubmit?.sha256 &&
    releaseManifest?.artifacts?.notaryEvidence?.zipLog?.sha256 === strictReleaseVerificationReport?.artifacts?.notaryEvidence?.zipLog?.sha256 &&
    releaseManifest?.artifacts?.notaryEvidence?.dmgSubmit?.sha256 === strictReleaseVerificationReport?.artifacts?.notaryEvidence?.dmgSubmit?.sha256 &&
    releaseManifest?.artifacts?.notaryEvidence?.dmgLog?.sha256 === strictReleaseVerificationReport?.artifacts?.notaryEvidence?.dmgLog?.sha256 &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest Info.plist package version' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest source provenance' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'manifest build toolchain provenance' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'source revision matches current checkout' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'source tree clean for release' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'Info.plist package version' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled planner script syntax' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node runtime execution' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node codesign verification' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'bundled Node dependency closure' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'app third-party notice' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'app Node license' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'Finder-open document types' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'Developer ID app signature' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'app notarization ticket' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'app Gatekeeper assessment' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'app quarantined Gatekeeper assessment' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'Developer ID DMG signature' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG notarization ticket' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG Gatekeeper assessment' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG quarantined Gatekeeper assessment' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Finder-open document types' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Info.plist package version' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node runtime' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node codesign' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app bundled Node dependencies' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app third-party notice' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Node license' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app notarization ticket' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app Gatekeeper assessment' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip app quarantined Gatekeeper assessment' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip notary submission evidence' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'zip notary log evidence' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG notary submission evidence' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'DMG notary log evidence' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Finder-open document types' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Info.plist package version' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node runtime' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node codesign' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed bundled Node dependencies' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed third-party notice' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed Node license' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed quarantined app Gatekeeper assessment' && check.status === 'pass') &&
    strictReleaseVerificationReport?.checks?.some((check) => check.name === 'installed app Gatekeeper assessment' && check.status === 'pass');
  add(
    checks,
    'release blockers',
    'Strict release verification report',
    strictReleaseVerificationPassed ? 'pass' : 'blocked',
    strictReleaseVerificationPassed
      ? 'native/dist/release-verification-report.json proves Developer ID, notarization logs, source provenance, bundled runtime notices, quarantined Gatekeeper, ZIP/DMG Gatekeeper, and installed-app Gatekeeper for the current manifest checksums'
      : 'run npm run native:release with Developer ID/notary credentials to write a strict PASS release-verification-report.json for the current manifest checksums'
  );

  add(
    checks,
    'release blockers',
    'native DSP benchmark parity',
    exists('scripts/evaluate-native-analysis-benchmarks.cjs') &&
      exists('native/Sources/BeatDropperCore/AnalysisBenchmark.swift') &&
      exists('native/Sources/BeatDropperNativeAnalysisBenchmarks/main.swift')
      ? 'pass'
      : 'blocked',
    exists('scripts/evaluate-native-analysis-benchmarks.cjs') &&
      exists('native/Sources/BeatDropperCore/AnalysisBenchmark.swift') &&
      exists('native/Sources/BeatDropperNativeAnalysisBenchmarks/main.swift')
      ? 'native analysis benchmark evaluator is wired to curated fixture expectations'
      : 'native DSP is tested with unit fixtures, but no native benchmark evaluator is wired to curated fixture expectations yet'
  );
  add(
    checks,
    'release blockers',
    'native UI/real-session parity evidence',
    exists('scripts/smoke-native-app.cjs') &&
      /BEATDROPPER_NATIVE_SMOKE_READY/.test(readText('native/Sources/BeatDropperNative/BeatDropperNativeApp.swift'))
      ? 'pass'
      : 'blocked',
    exists('scripts/smoke-native-app.cjs') &&
      /BEATDROPPER_NATIVE_SMOKE_READY/.test(readText('native/Sources/BeatDropperNative/BeatDropperNativeApp.swift'))
      ? 'packaged native app smoke launch evidence is available'
      : 'native app still needs repeatable UI or documented real-session parity evidence before Electron retirement'
  );
  add(
    checks,
    'release blockers',
    'Electron retirement',
    options.preRetirement ? 'pass' : 'blocked',
    options.preRetirement
      ? 'pre-retirement mode: Electron may remain while native parity is being proven'
      : 'Electron remains the reference app until all release blockers pass'
  );

  const grouped = new Map();
  for (const check of checks) {
    if (!grouped.has(check.category)) {
      grouped.set(check.category, []);
    }
    grouped.get(check.category).push(check);
  }

  const totals = checks.reduce(
    (acc, check) => {
      acc[check.status] += 1;
      return acc;
    },
    { pass: 0, warn: 0, blocked: 0 }
  );
  const overall = checks.reduce((max, check) => Math.max(max, statusRank[check.status]), 0);
  const overallStatus = Object.entries(statusRank).find(([, rank]) => rank === overall)?.[0] || 'blocked';

  process.stdout.write(
    [
      '# Native Parity Audit',
      `status ${overallStatus.toUpperCase()}`,
      `pass ${totals.pass}`,
      `warn ${totals.warn}`,
      `blocked ${totals.blocked}`,
      ''
    ].join('\n')
  );

  for (const [category, items] of grouped) {
    process.stdout.write(`## ${category}\n`);
    for (const item of items) {
      process.stdout.write(`- ${item.status.toUpperCase()} ${item.name}: ${item.detail}\n`);
    }
    process.stdout.write('\n');
  }

  if (overallStatus === 'blocked' && !options.reportOnly) {
    process.exitCode = 1;
  }
};

try {
  main();
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
