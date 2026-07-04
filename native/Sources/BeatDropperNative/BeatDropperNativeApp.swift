import AppKit
import AVFoundation
import BeatDropperCore
import SwiftUI

@main
struct BeatDropperNativeApp: App {
    @NSApplicationDelegateAdaptor(BeatDropperApplicationDelegate.self) private var appDelegate
    @StateObject private var model: BeatDropperAppModel

    init() {
        let model = Self.makeModel()
        _model = StateObject(wrappedValue: model)
        BeatDropperApplicationDelegate.model = model
    }

    private static func makeModel() -> BeatDropperAppModel {
        let environment = ProcessInfo.processInfo.environment
        let requiresIsolatedState =
            environment["BEATDROPPER_NATIVE_SESSION_STRESS"] == "1" ||
            environment["BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS"] == "1" ||
            environment["BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION"] == "1"
        guard requiresIsolatedState else {
            return BeatDropperAppModel()
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperNativeSessionStress-State-\(UUID().uuidString)", isDirectory: true)
        BeatDropperApplicationDelegate.automationStateRootURL = rootURL
        return BeatDropperAppModel(
            store: NativeLibraryStore(fileURL: rootURL.appendingPathComponent("native-library.json")),
            settingsStore: NativeSettingsStore(fileURL: rootURL.appendingPathComponent("native-settings.json")),
            analysisStore: NativeTrackAnalysisStore(rootURL: rootURL.appendingPathComponent("track-analysis-cache")),
            mixPlanner: NativeMixPlannerBridge(timeoutSec: 1)
        )
    }

    var body: some Scene {
        WindowGroup("BeatDropper") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Set...") {
                    model.newSet()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Add Tracks...") {
                    model.addTracks()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.playlist.isEmpty)

                Button("Import Music Folder...") {
                    model.importFolder()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandMenu("Set") {
                Button("Move Selected Track Up") {
                    model.moveSelectedTrack(offset: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!model.canMoveSelectedTrackUp)

                Button("Move Selected Track Down") {
                    model.moveSelectedTrack(offset: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!model.canMoveSelectedTrackDown)

                Button("Remove Selected Track") {
                    model.removeSelectedTrack()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!model.canRemoveSelectedTrack)

                Button("Clear Set") {
                    model.clearPlaylist()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!model.canClearPlaylist)

                Divider()

                Button("Add Selected Library Track to Set") {
                    model.addSelectedLibraryTrackToPlaylist()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canAddSelectedLibraryTrackToPlaylist)

                Button("Rescan Library Folders") {
                    model.rescanLibraryFolders()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.hasLibrarySourceFolders)

                Button("Relink Selected Track...") {
                    model.relinkSelectedTrack()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!model.selectedTrackNeedsRelink)
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    model.playPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.playlist.isEmpty)

                Divider()

                Button(model.isAIMixEnabled ? "Turn Off AI Mix" : "Turn On AI Mix") {
                    model.setAIMixEnabled(!model.isAIMixEnabled)
                }
                .keyboardShortcut("m", modifiers: [.command])
                .disabled(!model.isAIMixEnabled && !model.canEnableAIMix)

                Button("Cancel AI Mix") {
                    model.cancelMixPlan()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canCancelMixPlan)

                Divider()

                Button("Previous Track") {
                    model.playPreviousTrack()
                }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .disabled(!model.hasPreviousTrack)

                Button("Next Track") {
                    model.playNextTrack()
                }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .disabled(!model.hasNextTrack)
            }

            CommandMenu("Workspace") {
                Button("Playing Workspace") {
                    model.workspaceMode = .playing
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Creative Workspace") {
                    model.workspaceMode = .creative
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button(
                    model.workspaceMode == .creative && model.isLibraryBrowserVisible
                        ? "Hide Library Browser"
                        : "Show Library Browser"
                ) {
                    if model.workspaceMode == .creative && model.isLibraryBrowserVisible {
                        model.isLibraryBrowserVisible = false
                    } else {
                        model.workspaceMode = .creative
                        model.isLibraryBrowserVisible = true
                    }
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Button("Save Current Set") {
                    model.saveCurrentSet()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!model.canSaveCurrentSet)

                Button("Load Selected Set") {
                    model.loadSelectedSavedSet()
                }
                .disabled(!model.canLoadSelectedSet)

                Divider()

                Button(
                    model.workspaceMode == .playing && model.isInspectorVisible
                        ? "Hide Inspector"
                        : "Show Inspector"
                ) {
                    if model.workspaceMode == .playing && model.isInspectorVisible {
                        model.isInspectorVisible = false
                    } else {
                        model.workspaceMode = .playing
                        model.isInspectorVisible = true
                    }
                }
                .keyboardShortcut("3", modifiers: [.command])
            }
        }

        Settings {
            MixSettingsView()
                .environmentObject(model)
        }
    }
}

@MainActor
final class BeatDropperApplicationDelegate: NSObject, NSApplicationDelegate {
    static var model: BeatDropperAppModel?
    static var automationStateRootURL: URL?
    private var fallbackWindow: NSWindow?
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        revealMainWindowSoon()
        openPendingFinderItemsIfNeeded()
        scheduleOpenImportStressIfNeeded()
        scheduleSessionStressIfNeeded()
        scheduleRealFolderValidationIfNeeded()
        schedulePlaybackStressIfNeeded()
        scheduleSmokeExitIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            revealMainWindowSoon()
        }
        return true
    }

    func application(_ application: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        if let model = Self.model {
            model.openFinderItemsAsSet(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
        revealMainWindowSoon()
    }

    private func openPendingFinderItemsIfNeeded() {
        guard !pendingOpenURLs.isEmpty,
              let model = Self.model
        else {
            return
        }

        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        model.openFinderItemsAsSet(urls)
    }

    private func revealMainWindowSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
            if let visibleWindow = NSApp.windows.first(where: { $0.isVisible }) {
                visibleWindow.makeKeyAndOrderFront(nil)
                return
            }
            self.showFallbackWindow()
        }
    }

    private func showFallbackWindow() {
        guard let model = Self.model else {
            return
        }

        if fallbackWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "BeatDropper"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(
                rootView: ContentView()
                    .environmentObject(model)
            )
            fallbackWindow = window
        }

        fallbackWindow?.makeKeyAndOrderFront(nil)
    }

    private func scheduleSmokeExitIfNeeded() {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_SMOKE"] == "1" else {
            return
        }

        let rawDelay = ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_SMOKE_DELAY_MS"]
            .flatMap(Double.init) ?? 1_000
        let delaySec = max(0.2, rawDelay / 1_000)
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) {
            let visibleWindowCount = NSApp.windows.filter(\.isVisible).count
            let keyWindowTitle = NSApp.keyWindow?.title ?? ""
            let message = "BEATDROPPER_NATIVE_SMOKE_READY visibleWindows=\(visibleWindowCount) keyWindow=\"\(keyWindowTitle)\"\n"
            FileHandle.standardOutput.write(Data(message.utf8))
            NSApp.terminate(nil)
        }
    }

    private func schedulePlaybackStressIfNeeded() {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_PLAYBACK_STRESS"] == "1" else {
            return
        }

        Task { @MainActor in
            do {
                try await runPlaybackStress()
                let message = "BEATDROPPER_NATIVE_PLAYBACK_STRESS_READY state=\(Self.model?.audioEngine.state.rawValue ?? "unknown")\n"
                FileHandle.standardOutput.write(Data(message.utf8))
                NSApp.terminate(nil)
            } catch {
                let message = "BEATDROPPER_NATIVE_PLAYBACK_STRESS_FAILED reason=\"\(error.localizedDescription)\"\n"
                FileHandle.standardError.write(Data(message.utf8))
                NSApp.terminate(nil)
            }
        }
    }

    private func scheduleOpenImportStressIfNeeded() {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS"] == "1" else {
            return
        }

        Task { @MainActor in
            do {
                let result = try await runOpenImportStress()
                let message = [
                    "BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS_READY",
                    "opened=\(result.openedCount)",
                    "library=\(result.libraryRecordCount)",
                    "sourceFolders=\(result.sourceFolderCount)",
                    "analyzed=\(result.analyzedCount)",
                    "state=\(Self.model?.audioEngine.state.rawValue ?? "unknown")"
                ].joined(separator: " ") + "\n"
                FileHandle.standardOutput.write(Data(message.utf8))
                NSApp.terminate(nil)
            } catch {
                let message = "BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS_FAILED reason=\"\(error.localizedDescription)\"\n"
                FileHandle.standardError.write(Data(message.utf8))
                NSApp.terminate(nil)
            }
        }
    }

    private func scheduleSessionStressIfNeeded() {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_SESSION_STRESS"] == "1" else {
            return
        }

        Task { @MainActor in
            do {
                let result = try await runSessionStress()
                let message = [
                    "BEATDROPPER_NATIVE_SESSION_STRESS_READY",
                    "imported=\(result.importedCount)",
                    "analyzed=\(result.analyzedCount)",
                    "maxRunning=\(result.maxRunningAnalysisCount)",
                    "planConfidence=\(String(format: "%.2f", result.planConfidence))",
                    "state=\(Self.model?.audioEngine.state.rawValue ?? "unknown")",
                    "transitions=\(result.transitionsCompleted)"
                ].joined(separator: " ") + "\n"
                FileHandle.standardOutput.write(Data(message.utf8))
                NSApp.terminate(nil)
            } catch {
                let message = "BEATDROPPER_NATIVE_SESSION_STRESS_FAILED reason=\"\(error.localizedDescription)\"\n"
                FileHandle.standardError.write(Data(message.utf8))
                NSApp.terminate(nil)
            }
        }
    }

    private func scheduleRealFolderValidationIfNeeded() {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION"] == "1" else {
            return
        }

        Task { @MainActor in
            do {
                let result = try await runRealFolderValidation()
                let message = [
                    "BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION_READY",
                    "imported=\(result.importedCount)",
                    "analyzed=\(result.analyzedCount)",
                    "sourceFolders=\(result.sourceFolderCount)",
                    "maxRunning=\(result.maxRunningAnalysisCount)",
                    "planConfidence=\(String(format: "%.2f", result.planConfidence))",
                    "planSource=\(result.planSource)",
                    "phraseAlignment=\(result.phraseAlignment)",
                    "tempoSync=\(result.tempoSyncEnabled ? "true" : "false")",
                    "evidenceCount=\(result.evidenceCount)",
                    "keyAvailable=\(result.keyAvailableCount)",
                    "keyStrong=\(result.keyStrongCount)",
                    "keyPartial=\(result.keyPartialCount)",
                    "keyFallback=\(result.keyFallbackCount)",
                    "keyLowConfidence=\(result.keyLowConfidenceCount)",
                    "keyUnavailable=\(result.keyUnavailableCount)",
                    "keyConfidenceAvg=\(String(format: "%.3f", result.keyConfidenceAverage))",
                    "keyConfidenceMin=\(String(format: "%.3f", result.keyConfidenceMin))",
                    "loudnessAvailable=\(result.loudnessAvailableCount)",
                    "loudnessStrong=\(result.loudnessStrongCount)",
                    "loudnessPartial=\(result.loudnessPartialCount)",
                    "loudnessFallback=\(result.loudnessFallbackCount)",
                    "loudnessLowConfidence=\(result.loudnessLowConfidenceCount)",
                    "headroomLow=\(result.headroomLowCount)",
                    "rmsAvgDb=\(String(format: "%.2f", result.rmsAverageDb))",
                    "rmsMinDb=\(String(format: "%.2f", result.rmsMinDb))",
                    "rmsMaxDb=\(String(format: "%.2f", result.rmsMaxDb))",
                    "lufsAvg=\(String(format: "%.2f", result.lufsAverage))",
                    "lufsMin=\(String(format: "%.2f", result.lufsMin))",
                    "lufsMax=\(String(format: "%.2f", result.lufsMax))",
                    "peakMaxDb=\(String(format: "%.2f", result.peakMaxDb))",
                    "truePeakMaxDb=\(String(format: "%.2f", result.truePeakMaxDb))",
                    "headroomMinDb=\(String(format: "%.2f", result.headroomMinDb))",
                    "loudnessRangeAvgLU=\(String(format: "%.2f", result.loudnessRangeAverageLU))",
                    "dynamicRangeAvgDb=\(String(format: "%.2f", result.dynamicRangeAverageDb))",
                    "stereoAvailable=\(result.stereoAvailableCount)",
                    "stereoTracks=\(result.stereoTrackCount)",
                    "channelCountMax=\(result.channelCountMax)",
                    "stereoWidthAvg=\(String(format: "%.3f", result.stereoWidthAverage))",
                    "phaseCorrelationAvg=\(String(format: "%.3f", result.phaseCorrelationAverage))",
                    "midSideBalanceAvg=\(String(format: "%.3f", result.midSideBalanceAverage))",
                    "state=\(Self.model?.audioEngine.state.rawValue ?? "unknown")"
                ].joined(separator: " ") + "\n"
                FileHandle.standardOutput.write(Data(message.utf8))
                NSApp.terminate(nil)
            } catch {
                let message = "BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION_FAILED reason=\"\(error.localizedDescription)\"\n"
                FileHandle.standardError.write(Data(message.utf8))
                NSApp.terminate(nil)
            }
        }
    }

    private func runOpenImportStress() async throws -> NativeOpenImportStressResult {
        guard let model = Self.model else {
            throw NativeOpenImportStressError.modelMissing
        }

        let fixture = try NativeOpenImportStressFixture.create()
        defer {
            try? FileManager.default.removeItem(at: fixture.rootURL)
            if let rootURL = Self.automationStateRootURL {
                try? FileManager.default.removeItem(at: rootURL)
            }
        }

        let openedCount = await model.openExternalItemsForAutomation(
            fixture.openURLs,
            sourceName: "Finder"
        )
        guard openedCount == fixture.expectedTrackCount,
              model.playlist.count == fixture.expectedTrackCount,
              model.libraryRecords.count == fixture.expectedTrackCount,
              model.librarySourceFolders.count == 1
        else {
            throw NativeOpenImportStressError.importFailed
        }

        let folderBackedCount = model.libraryRecords.filter { $0.sourceFolderPath != nil }.count
        let looseFileCount = model.libraryRecords.filter { $0.sourceFolderPath == nil }.count
        guard folderBackedCount == fixture.expectedFolderTrackCount,
              looseFileCount == fixture.expectedLooseTrackCount
        else {
            throw NativeOpenImportStressError.libraryShapeMismatch
        }

        try await waitUntil(
            timeoutSec: 18,
            failure: { NativeOpenImportStressError.analysisTimedOut }
        ) {
            model.queuedAnalysisTrackCount == 0 &&
                model.runningAnalysisTrackCount == 0 &&
                model.trackAnalysesById.count >= fixture.expectedTrackCount
        }

        guard model.audioEngine.state == .idle else {
            throw NativeOpenImportStressError.playbackStateChanged
        }

        return NativeOpenImportStressResult(
            openedCount: openedCount,
            libraryRecordCount: model.libraryRecords.count,
            sourceFolderCount: model.librarySourceFolders.count,
            analyzedCount: model.trackAnalysesById.count
        )
    }

    private func runSessionStress() async throws -> NativeSessionStressResult {
        guard let model = Self.model else {
            throw NativeSessionStressError.modelMissing
        }

        let configuration = NativeSessionStressConfiguration.current
        let fixture = try NativeSessionStressFixture.create(trackCount: configuration.trackCount)
        defer {
            try? FileManager.default.removeItem(at: fixture.folderURL)
            if let rootURL = Self.automationStateRootURL {
                try? FileManager.default.removeItem(at: rootURL)
            }
        }

        let importedCount = await model.importFolderForAutomation(fixture.folderURL)
        guard importedCount == fixture.expectedTrackCount,
              model.playlist.count == fixture.expectedTrackCount,
              model.libraryRecords.count == fixture.expectedTrackCount,
              model.librarySourceFolders.count == 1
        else {
            throw NativeSessionStressError.importFailed
        }
        model.updateFadeDuration(2)

        var maxRunningAnalysisCount = model.runningAnalysisTrackCount
        try await waitUntil(
            timeoutSec: configuration.analysisTimeoutSec,
            failure: { NativeSessionStressError.analysisTimedOut }
        ) {
            maxRunningAnalysisCount = max(maxRunningAnalysisCount, model.runningAnalysisTrackCount)
            return model.queuedAnalysisTrackCount == 0 &&
                model.runningAnalysisTrackCount == 0 &&
                model.trackAnalysesById.count >= fixture.expectedTrackCount
        }

        guard maxRunningAnalysisCount <= NativeAnalysisQueueState.recommendedConcurrency(
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        ) else {
            throw NativeSessionStressError.analysisQueueExceededLimit
        }

        guard model.playlist.count >= 2 else {
            throw NativeSessionStressError.importFailed
        }

        let transitionTargetCount = min(configuration.transitionCount, model.playlist.count - 1)
        guard transitionTargetCount > 0 else {
            throw NativeSessionStressError.importFailed
        }
        let first = model.playlist[0]
        try model.audioEngine.play(url: first.url, track: first.track)
        try await waitUntil(
            timeoutSec: 4,
            failure: {
                NativeSessionStressError.playDidNotAdvance(
                    playbackStressSnapshot(model.audioEngine, expectedTrackId: first.id)
                )
            }
        ) {
            model.audioEngine.state == .playing &&
                model.audioEngine.currentTrack?.id == first.id &&
                model.audioEngine.elapsedSec > 0
        }

        var minPlanConfidence = 1.0
        var completedTransitions = 0
        for transitionIndex in 0..<transitionTargetCount {
            let current = model.playlist[transitionIndex]
            let next = model.playlist[transitionIndex + 1]
            guard model.audioEngine.currentTrack?.id == current.id else {
                throw NativeSessionStressError.crossfadeDidNotComplete(
                    playbackStressSnapshot(model.audioEngine, expectedTrackId: current.id)
                )
            }

            let plan = try await requestSessionStressPlan(
                model: model,
                current: current,
                next: next
            )
            minPlanConfidence = min(minPlanConfidence, plan.confidence)

            let plannedDuration = plan.transitionEndSec - plan.transitionStartSec
            let stressDuration = min(0.65, max(0.25, plannedDuration))
            try model.audioEngine.crossfadeTo(
                url: next.url,
                track: next.track,
                durationSec: stressDuration,
                startOffsetSec: plan.nextTrackStartOffsetSec
            )
            try await waitUntil(
                timeoutSec: max(2.5, stressDuration + 2),
                failure: {
                    NativeSessionStressError.crossfadeDidNotComplete(
                        playbackStressSnapshot(model.audioEngine, expectedTrackId: next.id)
                    )
                }
            ) {
                model.audioEngine.state == .playing &&
                    model.audioEngine.currentTrack?.id == next.id
            }
            completedTransitions += 1
        }

        model.audioEngine.stop()
        guard model.audioEngine.state == .idle else {
            throw NativeSessionStressError.stopFailed
        }

        return NativeSessionStressResult(
            importedCount: importedCount,
            analyzedCount: model.trackAnalysesById.count,
            maxRunningAnalysisCount: maxRunningAnalysisCount,
            planConfidence: minPlanConfidence,
            transitionsCompleted: completedTransitions
        )
    }

    private func runRealFolderValidation() async throws -> NativeRealFolderValidationResult {
        guard let model = Self.model else {
            throw NativeRealFolderValidationError.modelMissing
        }
        guard let folderPath = ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_REAL_FOLDER_PATH"],
              !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw NativeRealFolderValidationError.folderPathMissing
        }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw NativeRealFolderValidationError.folderMissing
        }

        defer {
            if let rootURL = Self.automationStateRootURL {
                try? FileManager.default.removeItem(at: rootURL)
            }
        }

        let importedCount = await model.importFolderForAutomation(folderURL)
        guard importedCount >= 2,
              model.playlist.count >= 2,
              model.libraryRecords.count >= importedCount,
              model.librarySourceFolders.count == 1
        else {
            throw NativeRealFolderValidationError.importFailed
        }

        var maxRunningAnalysisCount = model.runningAnalysisTrackCount
        try await waitUntil(
            timeoutSec: configuredRealFolderAnalysisTimeoutSec() ?? max(30, TimeInterval(importedCount) * 6),
            failure: { NativeRealFolderValidationError.analysisTimedOut }
        ) {
            maxRunningAnalysisCount = max(maxRunningAnalysisCount, model.runningAnalysisTrackCount)
            return model.queuedAnalysisTrackCount == 0 &&
                model.runningAnalysisTrackCount == 0 &&
                model.trackAnalysesById.count >= importedCount
        }

        guard maxRunningAnalysisCount <= NativeAnalysisQueueState.recommendedConcurrency(
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        ) else {
            throw NativeRealFolderValidationError.analysisQueueExceededLimit
        }

        let current = model.playlist[0]
        let next = model.playlist[1]
        let plan = try await requestSessionStressPlan(
            model: model,
            current: current,
            next: next
        )

        guard plan.confidence > 0 else {
            throw NativeRealFolderValidationError.plannerFailed("confidence was not positive")
        }
        guard model.audioEngine.state == .idle else {
            throw NativeRealFolderValidationError.playbackStateChanged
        }

        let planSource = plan.evidence.first { $0.hasPrefix("source ") }?
            .replacingOccurrences(of: "source ", with: "") ?? "unknown"
        let evidenceSummary = realFolderEvidenceSummary(Array(model.trackAnalysesById.values))
        return NativeRealFolderValidationResult(
            importedCount: importedCount,
            analyzedCount: model.trackAnalysesById.count,
            sourceFolderCount: model.librarySourceFolders.count,
            maxRunningAnalysisCount: maxRunningAnalysisCount,
            planConfidence: plan.confidence,
            planSource: planSource,
            phraseAlignment: plan.phraseAlignment?.rawValue ?? "unknown",
            tempoSyncEnabled: plan.tempoSync.enabled,
            evidenceCount: plan.evidence.count,
            keyAvailableCount: evidenceSummary.keyAvailableCount,
            keyStrongCount: evidenceSummary.keyStrongCount,
            keyPartialCount: evidenceSummary.keyPartialCount,
            keyFallbackCount: evidenceSummary.keyFallbackCount,
            keyLowConfidenceCount: evidenceSummary.keyLowConfidenceCount,
            keyUnavailableCount: evidenceSummary.keyUnavailableCount,
            keyConfidenceAverage: evidenceSummary.keyConfidenceAverage,
            keyConfidenceMin: evidenceSummary.keyConfidenceMin,
            loudnessAvailableCount: evidenceSummary.loudnessAvailableCount,
            loudnessStrongCount: evidenceSummary.loudnessStrongCount,
            loudnessPartialCount: evidenceSummary.loudnessPartialCount,
            loudnessFallbackCount: evidenceSummary.loudnessFallbackCount,
            loudnessLowConfidenceCount: evidenceSummary.loudnessLowConfidenceCount,
            headroomLowCount: evidenceSummary.headroomLowCount,
            rmsAverageDb: evidenceSummary.rmsAverageDb,
            rmsMinDb: evidenceSummary.rmsMinDb,
            rmsMaxDb: evidenceSummary.rmsMaxDb,
            lufsAverage: evidenceSummary.lufsAverage,
            lufsMin: evidenceSummary.lufsMin,
            lufsMax: evidenceSummary.lufsMax,
            peakMaxDb: evidenceSummary.peakMaxDb,
            truePeakMaxDb: evidenceSummary.truePeakMaxDb,
            headroomMinDb: evidenceSummary.headroomMinDb,
            loudnessRangeAverageLU: evidenceSummary.loudnessRangeAverageLU,
            dynamicRangeAverageDb: evidenceSummary.dynamicRangeAverageDb,
            stereoAvailableCount: evidenceSummary.stereoAvailableCount,
            stereoTrackCount: evidenceSummary.stereoTrackCount,
            channelCountMax: evidenceSummary.channelCountMax,
            stereoWidthAverage: evidenceSummary.stereoWidthAverage,
            phaseCorrelationAverage: evidenceSummary.phaseCorrelationAverage,
            midSideBalanceAverage: evidenceSummary.midSideBalanceAverage
        )
    }

    private func realFolderEvidenceSummary(_ analyses: [TrackAnalysis]) -> NativeRealFolderEvidenceSummary {
        let keyConfidences = analyses.compactMap { $0.musicalKey?.confidence }
        let loudnessValues = analyses.compactMap(\.loudness)
        let loudnessConfidences = loudnessValues.map(\.confidence)
        let lufsValues = loudnessValues.compactMap(\.integratedLUFS)
        let truePeakValues = loudnessValues.compactMap(\.truePeakDb)
        let loudnessRangeValues = loudnessValues.compactMap(\.loudnessRangeLU)
        let stereoValues = analyses.compactMap(\.stereo)
        return NativeRealFolderEvidenceSummary(
            keyAvailableCount: keyConfidences.count,
            keyStrongCount: keyConfidences.filter { $0 >= 0.62 }.count,
            keyPartialCount: keyConfidences.filter { $0 >= 0.35 && $0 < 0.62 }.count,
            keyFallbackCount: analyses.count - keyConfidences.filter { $0 >= 0.35 }.count,
            keyLowConfidenceCount: analyses.filter { $0.analysisWarnings.contains(.keyLowConfidence) }.count,
            keyUnavailableCount: analyses.filter { $0.analysisWarnings.contains(.keyUnavailable) }.count,
            keyConfidenceAverage: average(keyConfidences),
            keyConfidenceMin: keyConfidences.min() ?? 0,
            loudnessAvailableCount: loudnessValues.count,
            loudnessStrongCount: loudnessConfidences.filter { $0 >= 0.68 }.count,
            loudnessPartialCount: loudnessConfidences.filter { $0 >= 0.45 && $0 < 0.68 }.count,
            loudnessFallbackCount: analyses.count - loudnessConfidences.filter { $0 >= 0.45 }.count,
            loudnessLowConfidenceCount: analyses.filter { $0.analysisWarnings.contains(.loudnessLowConfidence) }.count,
            headroomLowCount: analyses.filter { $0.analysisWarnings.contains(.headroomLow) }.count,
            rmsAverageDb: average(loudnessValues.map(\.integratedRMSDb)),
            rmsMinDb: loudnessValues.map(\.integratedRMSDb).min() ?? 0,
            rmsMaxDb: loudnessValues.map(\.integratedRMSDb).max() ?? 0,
            lufsAverage: average(lufsValues),
            lufsMin: lufsValues.min() ?? 0,
            lufsMax: lufsValues.max() ?? 0,
            peakMaxDb: loudnessValues.map(\.peakDb).max() ?? 0,
            truePeakMaxDb: truePeakValues.max() ?? 0,
            headroomMinDb: loudnessValues.map(\.headroomDb).min() ?? 0,
            loudnessRangeAverageLU: average(loudnessRangeValues),
            dynamicRangeAverageDb: average(loudnessValues.map(\.dynamicRangeDb)),
            stereoAvailableCount: stereoValues.count,
            stereoTrackCount: stereoValues.filter { $0.channelCount >= 2 }.count,
            channelCountMax: stereoValues.map(\.channelCount).max() ?? 0,
            stereoWidthAverage: average(stereoValues.map(\.stereoWidth)),
            phaseCorrelationAverage: average(stereoValues.map(\.phaseCorrelation)),
            midSideBalanceAverage: average(stereoValues.map(\.midSideBalance))
        )
    }

    private func configuredRealFolderAnalysisTimeoutSec() -> TimeInterval? {
        guard let rawValue = ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_REAL_FOLDER_ANALYSIS_TIMEOUT_SEC"],
              let value = Double(rawValue),
              value.isFinite,
              value >= 30
        else {
            return nil
        }
        return value
    }

    private func requestSessionStressPlan(
        model: BeatDropperAppModel,
        current: ImportedTrack,
        next: ImportedTrack
    ) async throws -> MixPlan {
        let currentElapsed = model.audioEngine.currentTrack?.id == current.id
            ? model.audioEngine.elapsedSec
            : 0
        let plannerSettings = PlannerSettingsSnapshot(
            fadeDurationSec: model.settings.fadeDurationSec,
            aiDjMode: model.settings.aiDjMode
        )
        let request = PlannerRequestBuilder.build(
            currentTrack: current.track,
            nextTrack: next.track,
            elapsedSec: currentElapsed,
            currentAnalysis: model.trackAnalysesById[current.id],
            nextAnalysis: model.trackAnalysesById[next.id],
            settings: plannerSettings
        )
        let validationContext = MixPlanValidationContext(
            currentPlaybackElapsedSec: request.currentPlayback.elapsedSec,
            currentTrackDurationSec: current.track.durationSec,
            nextTrackDurationSec: next.track.durationSec,
            maxFadeDurationSec: model.settings.fadeDurationSec
        )
        let planner = NativeMixPlannerBridge(timeoutSec: 1)
        let plannerResult = await planner.requestMixPlan(
            request: request,
            validationContext: validationContext
        )
        guard let plan = plannerResult.plan else {
            throw NativeSessionStressError.plannerFailed(plannerResult.reason ?? "no plan")
        }
        return plan
    }

    private func runPlaybackStress() async throws {
        guard let model = Self.model else {
            throw PlaybackStressError.modelMissing
        }

        let fixture = try PlaybackStressFixture.create()
        defer {
            try? FileManager.default.removeItem(at: fixture.folderURL)
        }

        try model.audioEngine.play(url: fixture.firstURL, track: fixture.firstTrack)
        try await waitUntil(
            timeoutSec: 4,
            failure: {
                PlaybackStressError.playDidNotAdvance(
                    playbackStressSnapshot(model.audioEngine, expectedTrackId: fixture.firstTrack.id)
                )
            }
        ) {
            model.audioEngine.state == .playing &&
                model.audioEngine.currentTrack?.id == fixture.firstTrack.id &&
                model.audioEngine.elapsedSec > 0
        }

        try model.audioEngine.crossfadeTo(
            url: fixture.secondURL,
            track: fixture.secondTrack,
            durationSec: 0.35,
            startOffsetSec: 0.05
        )
        try await waitUntil(
            timeoutSec: 3,
            failure: {
                PlaybackStressError.crossfadeDidNotComplete(
                    playbackStressSnapshot(model.audioEngine, expectedTrackId: fixture.secondTrack.id)
                )
            }
        ) {
            model.audioEngine.state == .playing &&
                model.audioEngine.currentTrack?.id == fixture.secondTrack.id
        }

        model.audioEngine.pause()
        guard model.audioEngine.state == .paused else {
            throw PlaybackStressError.pauseFailed
        }

        try await sleep(milliseconds: 120)
        try model.audioEngine.resume()
        try await waitUntil(
            timeoutSec: 3,
            failure: { PlaybackStressError.resumeFailed(playbackStressSnapshot(model.audioEngine)) }
        ) {
            model.audioEngine.state == .playing &&
                model.audioEngine.elapsedSec > 0
        }

        model.audioEngine.stop()
        guard model.audioEngine.state == .idle else {
            throw PlaybackStressError.stopFailed
        }
    }

    private func sleep(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func waitUntil(
        timeoutSec: TimeInterval,
        intervalMilliseconds: UInt64 = 100,
        failure: () -> Error,
        predicate: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if predicate() {
                return
            }
            try await sleep(milliseconds: intervalMilliseconds)
        }
        throw failure()
    }

    private func playbackStressSnapshot(_ engine: NativeAudioEngine, expectedTrackId: String? = nil) -> String {
        [
            "state=\(engine.state.rawValue)",
            "current=\(engine.currentTrack?.id ?? "--")",
            "expected=\(expectedTrackId ?? "--")",
            "queued=\(engine.queuedTrack?.id ?? "--")",
            "elapsed=\(String(format: "%.3f", engine.elapsedSec))",
            "remaining=\(String(format: "%.3f", engine.remainingSec))",
            "crossfade=\(String(format: "%.3f", engine.crossfadeProgress))"
        ].joined(separator: "; ")
    }
}

private struct NativeOpenImportStressResult {
    var openedCount: Int
    var libraryRecordCount: Int
    var sourceFolderCount: Int
    var analyzedCount: Int
}

private enum NativeOpenImportStressError: LocalizedError {
    case modelMissing
    case fixtureFailed
    case importFailed
    case analysisTimedOut
    case libraryShapeMismatch
    case playbackStateChanged

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "application model is missing"
        case .fixtureFailed:
            return "external import fixture could not be created"
        case .importFailed:
            return "external import did not populate the native library"
        case .analysisTimedOut:
            return "external import analysis queue did not finish before timeout"
        case .libraryShapeMismatch:
            return "external import did not preserve folder-backed and loose-file records"
        case .playbackStateChanged:
            return "external import changed playback state unexpectedly"
        }
    }
}

private struct NativeOpenImportStressFixture {
    var rootURL: URL
    var openURLs: [URL]
    var expectedFolderTrackCount: Int
    var expectedLooseTrackCount: Int

    var expectedTrackCount: Int {
        expectedFolderTrackCount + expectedLooseTrackCount
    }

    static func create() throws -> NativeOpenImportStressFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperNativeOpenImportStress-\(UUID().uuidString)", isDirectory: true)
        let folderURL = rootURL.appendingPathComponent("External Crate", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let firstFolderTrackURL = folderURL.appendingPathComponent("external-folder-a.wav")
        let secondFolderTrackURL = folderURL.appendingPathComponent("external-folder-b.wav")
        let looseTrackURL = rootURL.appendingPathComponent("external-loose.wav")
        let unsupportedURL = rootURL.appendingPathComponent("ignore-me.txt")

        try writePulseWave(url: firstFolderTrackURL, frequency: 220, bpm: 124, durationSec: 5)
        try writePulseWave(url: secondFolderTrackURL, frequency: 277, bpm: 126, durationSec: 5)
        try writePulseWave(url: looseTrackURL, frequency: 330, bpm: 128, durationSec: 5)
        try Data("not audio".utf8).write(to: unsupportedURL)

        return NativeOpenImportStressFixture(
            rootURL: rootURL,
            openURLs: [folderURL, looseTrackURL, unsupportedURL],
            expectedFolderTrackCount: 2,
            expectedLooseTrackCount: 1
        )
    }

    private static func writePulseWave(
        url: URL,
        frequency: Double,
        bpm: Double,
        durationSec: Double
    ) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount((sampleRate * durationSec).rounded())
              )
        else {
            throw NativeOpenImportStressError.fixtureFailed
        }

        buffer.frameLength = buffer.frameCapacity
        let frameCount = Int(buffer.frameLength)
        let beatInterval = 60.0 / bpm
        for channelIndex in 0..<Int(format.channelCount) {
            guard let channel = buffer.floatChannelData?[channelIndex] else {
                continue
            }
            for frameIndex in 0..<frameCount {
                let time = Double(frameIndex) / sampleRate
                let beatPhase = time.truncatingRemainder(dividingBy: beatInterval)
                let transient = beatPhase < 0.045 ? 0.42 * (1 - beatPhase / 0.045) : 0
                let tone = 0.14 * sin(2 * Double.pi * frequency * time)
                channel[frameIndex] = Float(tone + transient)
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

private struct NativeSessionStressResult {
    var importedCount: Int
    var analyzedCount: Int
    var maxRunningAnalysisCount: Int
    var planConfidence: Double
    var transitionsCompleted: Int
}

private struct NativeRealFolderValidationResult {
    var importedCount: Int
    var analyzedCount: Int
    var sourceFolderCount: Int
    var maxRunningAnalysisCount: Int
    var planConfidence: Double
    var planSource: String
    var phraseAlignment: String
    var tempoSyncEnabled: Bool
    var evidenceCount: Int
    var keyAvailableCount: Int
    var keyStrongCount: Int
    var keyPartialCount: Int
    var keyFallbackCount: Int
    var keyLowConfidenceCount: Int
    var keyUnavailableCount: Int
    var keyConfidenceAverage: Double
    var keyConfidenceMin: Double
    var loudnessAvailableCount: Int
    var loudnessStrongCount: Int
    var loudnessPartialCount: Int
    var loudnessFallbackCount: Int
    var loudnessLowConfidenceCount: Int
    var headroomLowCount: Int
    var rmsAverageDb: Double
    var rmsMinDb: Double
    var rmsMaxDb: Double
    var lufsAverage: Double
    var lufsMin: Double
    var lufsMax: Double
    var peakMaxDb: Double
    var truePeakMaxDb: Double
    var headroomMinDb: Double
    var loudnessRangeAverageLU: Double
    var dynamicRangeAverageDb: Double
    var stereoAvailableCount: Int
    var stereoTrackCount: Int
    var channelCountMax: Int
    var stereoWidthAverage: Double
    var phaseCorrelationAverage: Double
    var midSideBalanceAverage: Double
}

private struct NativeRealFolderEvidenceSummary {
    var keyAvailableCount: Int
    var keyStrongCount: Int
    var keyPartialCount: Int
    var keyFallbackCount: Int
    var keyLowConfidenceCount: Int
    var keyUnavailableCount: Int
    var keyConfidenceAverage: Double
    var keyConfidenceMin: Double
    var loudnessAvailableCount: Int
    var loudnessStrongCount: Int
    var loudnessPartialCount: Int
    var loudnessFallbackCount: Int
    var loudnessLowConfidenceCount: Int
    var headroomLowCount: Int
    var rmsAverageDb: Double
    var rmsMinDb: Double
    var rmsMaxDb: Double
    var lufsAverage: Double
    var lufsMin: Double
    var lufsMax: Double
    var peakMaxDb: Double
    var truePeakMaxDb: Double
    var headroomMinDb: Double
    var loudnessRangeAverageLU: Double
    var dynamicRangeAverageDb: Double
    var stereoAvailableCount: Int
    var stereoTrackCount: Int
    var channelCountMax: Int
    var stereoWidthAverage: Double
    var phaseCorrelationAverage: Double
    var midSideBalanceAverage: Double
}

private func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else {
        return 0
    }
    return values.reduce(0, +) / Double(values.count)
}

private struct NativeSessionStressConfiguration {
    var trackCount: Int
    var transitionCount: Int

    var analysisTimeoutSec: TimeInterval {
        max(18, TimeInterval(trackCount) * 4)
    }

    static var current: NativeSessionStressConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let trackCount = clampedInt(
            environment["BEATDROPPER_NATIVE_SESSION_STRESS_TRACKS"],
            defaultValue: 4,
            range: 4...24
        )
        let transitionCount = clampedInt(
            environment["BEATDROPPER_NATIVE_SESSION_STRESS_TRANSITIONS"],
            defaultValue: 1,
            range: 1...max(1, trackCount - 1)
        )
        return NativeSessionStressConfiguration(
            trackCount: trackCount,
            transitionCount: transitionCount
        )
    }

    private static func clampedInt(
        _ rawValue: String?,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard let rawValue,
              let value = Int(rawValue)
        else {
            return defaultValue
        }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

private enum NativeSessionStressError: LocalizedError {
    case modelMissing
    case importFailed
    case analysisTimedOut
    case analysisQueueExceededLimit
    case plannerFailed(String)
    case playDidNotAdvance(String)
    case crossfadeDidNotComplete(String)
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "application model is missing"
        case .importFailed:
            return "session fixture import did not populate the native library"
        case .analysisTimedOut:
            return "bounded analysis queue did not finish before timeout"
        case .analysisQueueExceededLimit:
            return "bounded analysis queue exceeded its concurrency limit"
        case .plannerFailed(let reason):
            return "planner did not return a usable plan: \(reason)"
        case .playDidNotAdvance(let detail):
            return "session playback did not start and advance: \(detail)"
        case .crossfadeDidNotComplete(let detail):
            return "session crossfade did not complete on the target deck: \(detail)"
        case .stopFailed:
            return "session stop did not return to idle state"
        }
    }
}

private enum NativeRealFolderValidationError: LocalizedError {
    case modelMissing
    case folderPathMissing
    case folderMissing
    case importFailed
    case analysisTimedOut
    case analysisQueueExceededLimit
    case plannerFailed(String)
    case playbackStateChanged

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "application model is missing"
        case .folderPathMissing:
            return "BEATDROPPER_NATIVE_REAL_FOLDER_PATH is missing"
        case .folderMissing:
            return "real-track validation folder does not exist or is not a directory"
        case .importFailed:
            return "real-track folder import did not produce at least two supported tracks"
        case .analysisTimedOut:
            return "real-track analysis queue did not finish before timeout"
        case .analysisQueueExceededLimit:
            return "real-track analysis queue exceeded its concurrency limit"
        case .plannerFailed(let reason):
            return "real-track planner did not return a usable plan: \(reason)"
        case .playbackStateChanged:
            return "real-track validation changed playback state unexpectedly"
        }
    }
}

private enum PlaybackStressError: LocalizedError {
    case modelMissing
    case playDidNotAdvance(String)
    case crossfadeDidNotComplete(String)
    case pauseFailed
    case resumeFailed(String)
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "application model is missing"
        case .playDidNotAdvance(let detail):
            return "playback did not start and advance: \(detail)"
        case .crossfadeDidNotComplete(let detail):
            return "crossfade did not complete on the target deck: \(detail)"
        case .pauseFailed:
            return "pause did not enter paused state"
        case .resumeFailed(let detail):
            return "resume did not return to playing state: \(detail)"
        case .stopFailed:
            return "stop did not return to idle state"
        }
    }
}

private struct PlaybackStressFixture {
    var folderURL: URL
    var firstURL: URL
    var secondURL: URL
    var firstTrack: Track
    var secondTrack: Track

    static func create() throws -> PlaybackStressFixture {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperNativePlaybackStress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let firstURL = folderURL.appendingPathComponent("stress-a.wav")
        let secondURL = folderURL.appendingPathComponent("stress-b.wav")
        try writeSineWave(url: firstURL, frequency: 220, durationSec: 1.6)
        try writeSineWave(url: secondURL, frequency: 330, durationSec: 1.6)

        return PlaybackStressFixture(
            folderURL: folderURL,
            firstURL: firstURL,
            secondURL: secondURL,
            firstTrack: Track(id: "native-stress-a", title: "Native Stress A", durationSec: 1.6, format: .wav, bpm: 120),
            secondTrack: Track(id: "native-stress-b", title: "Native Stress B", durationSec: 1.6, format: .wav, bpm: 124)
        )
    }

    private static func writeSineWave(url: URL, frequency: Double, durationSec: Double) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount((sampleRate * durationSec).rounded())
              )
        else {
            throw PlaybackStressError.playDidNotAdvance("fixture buffer allocation failed")
        }

        buffer.frameLength = buffer.frameCapacity
        let frameCount = Int(buffer.frameLength)
        let amplitude: Float = 0.18
        for channelIndex in 0..<Int(format.channelCount) {
            guard let channel = buffer.floatChannelData?[channelIndex] else {
                continue
            }
            for frameIndex in 0..<frameCount {
                let phase = 2 * Double.pi * frequency * Double(frameIndex) / sampleRate
                channel[frameIndex] = amplitude * Float(sin(phase))
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

private struct NativeSessionStressFixture {
    var folderURL: URL
    var expectedTrackCount: Int

    static func create(trackCount: Int = 4) throws -> NativeSessionStressFixture {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperNativeSessionStress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let labels = ["warmup", "lift", "peak", "roll", "release", "reset"]
        let specs: [(name: String, frequency: Double, bpm: Double)] = (0..<trackCount).map { index in
            let number = index + 1
            let label = labels[index % labels.count]
            let frequency = 196 * pow(2, Double(index % 9) / 12)
            let bpm = 122 + Double(index % 6) * 1.5
            return (
                name: String(format: "session-%02d-%@.wav", number, label),
                frequency: frequency,
                bpm: bpm
            )
        }
        for spec in specs {
            try writePulseWave(
                url: folderURL.appendingPathComponent(spec.name),
                frequency: spec.frequency,
                bpm: spec.bpm,
                durationSec: 8
            )
        }

        return NativeSessionStressFixture(
            folderURL: folderURL,
            expectedTrackCount: specs.count
        )
    }

    private static func writePulseWave(
        url: URL,
        frequency: Double,
        bpm: Double,
        durationSec: Double
    ) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount((sampleRate * durationSec).rounded())
              )
        else {
            throw NativeSessionStressError.importFailed
        }

        buffer.frameLength = buffer.frameCapacity
        let frameCount = Int(buffer.frameLength)
        let beatInterval = 60.0 / bpm
        for channelIndex in 0..<Int(format.channelCount) {
            guard let channel = buffer.floatChannelData?[channelIndex] else {
                continue
            }
            for frameIndex in 0..<frameCount {
                let time = Double(frameIndex) / sampleRate
                let beatPhase = time.truncatingRemainder(dividingBy: beatInterval)
                let pulse = beatPhase < 0.055 ? 0.26 * (1 - beatPhase / 0.055) : 0
                let phraseLift = time > durationSec * 0.5 ? 0.035 : 0
                let tone = sin(2 * Double.pi * frequency * time) * (0.08 + phraseLift)
                let overtone = sin(2 * Double.pi * frequency * 2 * time) * 0.025
                channel[frameIndex] = Float(min(0.42, max(-0.42, tone + overtone + pulse)))
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
