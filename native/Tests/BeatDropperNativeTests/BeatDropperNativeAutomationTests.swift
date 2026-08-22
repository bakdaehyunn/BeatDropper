import AVFoundation
import BeatDropperApplication
import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Combine
import Foundation
import Testing
@testable import BeatDropperNative

@Suite(.serialized)
@MainActor
struct BeatDropperNativeAutomationTests {
    @Test
    func openImportStress() async throws {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS"] == "1" else { return }
        let (model, rootURL) = makeModel(audioPlayback: NativeAudioEngine())
        let result = try await NativeAutomationHarness(model: model, stateRootURL: rootURL).runOpenImportStress()
        print([
            "BEATDROPPER_NATIVE_OPEN_IMPORT_STRESS_READY",
            "opened=\(result.openedCount)",
            "library=\(result.libraryRecordCount)",
            "sourceFolders=\(result.sourceFolderCount)",
            "analyzed=\(result.analyzedCount)",
            "state=\(model.playing.session.mode.rawValue)"
        ].joined(separator: " "))
    }

    @Test
    func sessionStress() async throws {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_SESSION_STRESS"] == "1" else { return }
        let (model, rootURL) = makeModel(audioPlayback: SessionStressAudioPlayback())
        let result = try await NativeAutomationHarness(model: model, stateRootURL: rootURL).runSessionStress()
        print([
            "BEATDROPPER_NATIVE_SESSION_STRESS_READY",
            "imported=\(result.importedCount)",
            "analyzed=\(result.analyzedCount)",
            "maxRunning=\(result.maxRunningAnalysisCount)",
            "planConfidence=\(String(format: "%.2f", result.planConfidence))",
            "state=\(model.playing.session.mode.rawValue)",
            "transitions=\(result.transitionsCompleted)"
        ].joined(separator: " "))
    }

    @Test
    func realFolderValidation() async throws {
        guard ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION"] == "1" else { return }
        let (model, rootURL) = makeModel(audioPlayback: NativeAudioEngine())
        let result = try await NativeAutomationHarness(model: model, stateRootURL: rootURL).runRealFolderValidation()
        print([
            "BEATDROPPER_NATIVE_REAL_FOLDER_VALIDATION_READY",
            "imported=\(result.importedCount)",
            "analyzed=\(result.analyzedCount)",
            "sourceFolders=\(result.sourceFolderCount)",
            "maxRunning=\(result.maxRunningAnalysisCount)",
            "planConfidence=\(String(format: "%.2f", result.planConfidence))",
            "planSource=\(result.planSource)",
            "phrase=\(result.phraseAlignment)",
            "tempoSync=\(result.tempoSyncEnabled ? "true" : "false")",
            "evidence=\(result.evidenceCount)",
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
            "rmsAvgDb=\(String(format: "%.3f", result.rmsAverageDb))",
            "rmsMinDb=\(String(format: "%.3f", result.rmsMinDb))",
            "rmsMaxDb=\(String(format: "%.3f", result.rmsMaxDb))",
            "lufsAvg=\(String(format: "%.3f", result.lufsAverage))",
            "lufsMin=\(String(format: "%.3f", result.lufsMin))",
            "lufsMax=\(String(format: "%.3f", result.lufsMax))",
            "peakMaxDb=\(String(format: "%.3f", result.peakMaxDb))",
            "truePeakMaxDb=\(String(format: "%.3f", result.truePeakMaxDb))",
            "headroomMinDb=\(String(format: "%.3f", result.headroomMinDb))",
            "loudnessRangeAvgLU=\(String(format: "%.3f", result.loudnessRangeAverageLU))",
            "dynamicRangeAvgDb=\(String(format: "%.3f", result.dynamicRangeAverageDb))",
            "stereoAvailable=\(result.stereoAvailableCount)",
            "stereoTracks=\(result.stereoTrackCount)",
            "channelCountMax=\(result.channelCountMax)",
            "stereoWidthAvg=\(String(format: "%.3f", result.stereoWidthAverage))",
            "phaseCorrelationAvg=\(String(format: "%.3f", result.phaseCorrelationAverage))",
            "midSideBalanceAvg=\(String(format: "%.3f", result.midSideBalanceAverage))",
            "state=\(model.playing.session.mode.rawValue)"
        ].joined(separator: " "))
    }

    private func makeModel(audioPlayback: any AudioPlayback) -> (BeatDropperAppModel, URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperNativeAutomation-State-\(UUID().uuidString)", isDirectory: true)
        let model = BeatDropperAppModel(
            audioPlayback: audioPlayback,
            store: NativeLibraryStore(fileURL: rootURL.appendingPathComponent("native-library.json")),
            settingsStore: NativeSettingsStore(fileURL: rootURL.appendingPathComponent("native-settings.json")),
            analysisStore: NativeTrackAnalysisStore(rootURL: rootURL.appendingPathComponent("track-analysis-cache")),
            mixReviewArtifactStore: MixReviewArtifactStore(fileURL: rootURL.appendingPathComponent("mix-review.json")),
            mixPlanner: NativeMixPlannerBridge(timeoutSec: 1)
        )
        return (model, rootURL)
    }
}

@MainActor
private struct NativeAutomationHarness {
    let model: BeatDropperAppModel
    let stateRootURL: URL

    func runOpenImportStress() async throws -> NativeOpenImportStressResult {
        let model = model

        let fixture = try NativeOpenImportStressFixture.create()
        defer {
            try? FileManager.default.removeItem(at: fixture.rootURL)
            try? FileManager.default.removeItem(at: stateRootURL)
        }

        let openedCount = await model.libraryActions.openExternalItems(
            fixture.openURLs,
            sourceName: "Finder"
        )
        guard openedCount == fixture.expectedTrackCount,
              model.library.playlist.count == fixture.expectedTrackCount,
              model.library.records.count == fixture.expectedTrackCount,
              model.library.sourceFolders.count == 1
        else {
            throw NativeOpenImportStressError.importFailed
        }

        let folderBackedCount = model.library.records.filter { $0.sourceFolderPath != nil }.count
        let looseFileCount = model.library.records.filter { $0.sourceFolderPath == nil }.count
        guard folderBackedCount == fixture.expectedFolderTrackCount,
              looseFileCount == fixture.expectedLooseTrackCount
        else {
            throw NativeOpenImportStressError.libraryShapeMismatch
        }

        try await waitUntil(
            timeoutSec: 18,
            failure: { NativeOpenImportStressError.analysisTimedOut }
        ) {
            model.library.queuedAnalysisTrackCount == 0 &&
                model.library.runningAnalysisTrackCount == 0 &&
                model.library.analysesByTrackID.count >= fixture.expectedTrackCount
        }

        guard model.playing.session.mode == .idle else {
            throw NativeOpenImportStressError.playbackStateChanged
        }

        return NativeOpenImportStressResult(
            openedCount: openedCount,
            libraryRecordCount: model.library.records.count,
            sourceFolderCount: model.library.sourceFolders.count,
            analyzedCount: model.library.analysesByTrackID.count
        )
    }

    func runSessionStress() async throws -> NativeSessionStressResult {
        let model = model

        let configuration = NativeSessionStressConfiguration.current
        let fixture = try NativeSessionStressFixture.create(trackCount: configuration.trackCount)
        defer {
            try? FileManager.default.removeItem(at: fixture.folderURL)
            try? FileManager.default.removeItem(at: stateRootURL)
        }

        let importedCount = await model.libraryActions.importFolder(at: fixture.folderURL)
        guard importedCount == fixture.expectedTrackCount,
              model.library.playlist.count == fixture.expectedTrackCount,
              model.library.records.count == fixture.expectedTrackCount,
              model.library.sourceFolders.count == 1
        else {
            throw NativeSessionStressError.importFailed
        }
        model.settingsActions.updateFadeDuration(2)

        var maxRunningAnalysisCount = model.library.runningAnalysisTrackCount
        try await waitUntil(
            timeoutSec: configuration.analysisTimeoutSec,
            failure: { NativeSessionStressError.analysisTimedOut }
        ) {
            maxRunningAnalysisCount = max(maxRunningAnalysisCount, model.library.runningAnalysisTrackCount)
            return model.library.queuedAnalysisTrackCount == 0 &&
                model.library.runningAnalysisTrackCount == 0 &&
                model.library.analysesByTrackID.count >= fixture.expectedTrackCount
        }

        guard maxRunningAnalysisCount <= NativeAnalysisQueueState.recommendedConcurrency(
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        ) else {
            throw NativeSessionStressError.analysisQueueExceededLimit
        }

        guard model.library.playlist.count >= 2 else {
            throw NativeSessionStressError.importFailed
        }

        let transitionTargetCount = min(configuration.transitionCount, model.library.playlist.count - 1)
        guard transitionTargetCount > 0 else {
            throw NativeSessionStressError.importFailed
        }
        let first = model.library.playlist[0]
        try model.playing.play(url: first.url, track: first.track)
        try await waitUntil(
            timeoutSec: 4,
            failure: {
                NativeSessionStressError.playDidNotAdvance(
                    playbackStressSnapshot(model.playing.session, expectedTrackId: first.id)
                )
            }
        ) {
            model.playing.session.mode == .playing &&
                model.playing.session.currentTrack?.id == first.id &&
                model.playing.session.currentElapsedSec > 0
        }

        var minPlanConfidence = 1.0
        var completedTransitions = 0
        for transitionIndex in 0..<transitionTargetCount {
            let current = model.library.playlist[transitionIndex]
            let next = model.library.playlist[transitionIndex + 1]
            guard model.playing.session.currentTrack?.id == current.id else {
                throw NativeSessionStressError.crossfadeDidNotComplete(
                    playbackStressSnapshot(model.playing.session, expectedTrackId: current.id)
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
            try model.playing.crossfadeTo(
                url: next.url,
                track: next.track,
                durationSec: stressDuration,
                startOffsetSec: plan.nextTrackStartOffsetSec,
                plan: plan,
                currentAnalysis: model.library.analysesByTrackID[current.id],
                nextAnalysis: model.library.analysesByTrackID[next.id]
            )
            try await waitUntil(
                timeoutSec: 1.5,
                intervalMilliseconds: 25,
                failure: {
                    NativeSessionStressError.crossfadeDidNotComplete(
                        playbackStressSnapshot(model.playing.session, expectedTrackId: next.id)
                    )
                }
            ) {
                model.playing.session.mode == .crossfading &&
                    model.playing.session.queuedTrack?.id == next.id &&
                    model.playing.session.queuedElapsedSec > plan.nextTrackStartOffsetSec &&
                    model.playing.session.activeTransitionPlan?.transitionTimingSource == plan.transitionTimingSource
            }
            try await waitUntil(
                timeoutSec: max(2.5, stressDuration + 2),
                failure: {
                    NativeSessionStressError.crossfadeDidNotComplete(
                        playbackStressSnapshot(model.playing.session, expectedTrackId: next.id)
                    )
                }
            ) {
                model.playing.session.mode == .playing &&
                    model.playing.session.currentTrack?.id == next.id
            }
            completedTransitions += 1
        }

        model.playing.stop()
        guard model.playing.session.mode == .idle else {
            throw NativeSessionStressError.stopFailed
        }

        return NativeSessionStressResult(
            importedCount: importedCount,
            analyzedCount: model.library.analysesByTrackID.count,
            maxRunningAnalysisCount: maxRunningAnalysisCount,
            planConfidence: minPlanConfidence,
            transitionsCompleted: completedTransitions
        )
    }

    func runRealFolderValidation() async throws -> NativeRealFolderValidationResult {
        let model = model
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
            try? FileManager.default.removeItem(at: stateRootURL)
        }

        let importedCount = await model.libraryActions.importFolder(at: folderURL)
        guard importedCount >= 2,
              model.library.playlist.count >= 2,
              model.library.records.count >= importedCount,
              model.library.sourceFolders.count == 1
        else {
            throw NativeRealFolderValidationError.importFailed
        }

        var maxRunningAnalysisCount = model.library.runningAnalysisTrackCount
        try await waitUntil(
            timeoutSec: configuredRealFolderAnalysisTimeoutSec() ?? max(30, TimeInterval(importedCount) * 6),
            failure: { NativeRealFolderValidationError.analysisTimedOut }
        ) {
            maxRunningAnalysisCount = max(maxRunningAnalysisCount, model.library.runningAnalysisTrackCount)
            return model.library.queuedAnalysisTrackCount == 0 &&
                model.library.runningAnalysisTrackCount == 0 &&
                model.library.analysesByTrackID.count >= importedCount
        }

        guard maxRunningAnalysisCount <= NativeAnalysisQueueState.recommendedConcurrency(
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        ) else {
            throw NativeRealFolderValidationError.analysisQueueExceededLimit
        }

        let current = model.library.playlist[0]
        let next = model.library.playlist[1]
        let plan = try await requestSessionStressPlan(
            model: model,
            current: current,
            next: next
        )

        guard plan.confidence > 0 else {
            throw NativeRealFolderValidationError.plannerFailed("confidence was not positive")
        }
        guard model.playing.session.mode == .idle else {
            throw NativeRealFolderValidationError.playbackStateChanged
        }

        let planSource = plan.evidence.first { $0.hasPrefix("source ") }?
            .replacingOccurrences(of: "source ", with: "") ?? "unknown"
        let evidenceSummary = realFolderEvidenceSummary(Array(model.library.analysesByTrackID.values))
        return NativeRealFolderValidationResult(
            importedCount: importedCount,
            analyzedCount: model.library.analysesByTrackID.count,
            sourceFolderCount: model.library.sourceFolders.count,
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

    func realFolderEvidenceSummary(_ analyses: [TrackAnalysis]) -> NativeRealFolderEvidenceSummary {
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

    func configuredRealFolderAnalysisTimeoutSec() -> TimeInterval? {
        guard let rawValue = ProcessInfo.processInfo.environment["BEATDROPPER_NATIVE_REAL_FOLDER_ANALYSIS_TIMEOUT_SEC"],
              let value = Double(rawValue),
              value.isFinite,
              value >= 30
        else {
            return nil
        }
        return value
    }

    func requestSessionStressPlan(
        model: BeatDropperAppModel,
        current: ImportedTrack,
        next: ImportedTrack
    ) async throws -> MixPlan {
        let currentElapsed = model.playing.session.currentTrack?.id == current.id
            ? model.playing.session.currentElapsedSec
            : 0
        let plannerSettings = PlannerSettingsSnapshot(
            fadeDurationSec: model.shell.settings.fadeDurationSec,
            aiDjMode: model.shell.settings.aiDjMode
        )
        let request = PlannerRequestBuilder.build(
            currentTrack: current.track,
            nextTrack: next.track,
            elapsedSec: currentElapsed,
            currentAnalysis: model.library.analysesByTrackID[current.id],
            nextAnalysis: model.library.analysesByTrackID[next.id],
            settings: plannerSettings
        )
        let validationContext = MixPlanValidationContext(
            currentPlaybackElapsedSec: request.currentPlayback.elapsedSec,
            currentTrackDurationSec: current.track.durationSec,
            nextTrackDurationSec: next.track.durationSec,
            maxFadeDurationSec: model.shell.settings.fadeDurationSec
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

    func runPlaybackStress() async throws -> PlaybackStressResult {
        let model = model

        let fixture = try PlaybackStressFixture.create()
        defer {
            try? FileManager.default.removeItem(at: fixture.folderURL)
        }

        playbackStressCheckpoint("fixture-ready")
        try model.playing.play(url: fixture.firstURL, track: fixture.firstTrack)
        try await waitUntil(
            timeoutSec: 4,
            failure: {
                PlaybackStressError.playDidNotAdvance(
                    playbackStressSnapshot(model.playing.session, expectedTrackId: fixture.firstTrack.id)
                )
            }
        ) {
            model.playing.session.mode == .playing &&
                model.playing.session.currentTrack?.id == fixture.firstTrack.id &&
                model.playing.session.currentElapsedSec > 0
        }
        playbackStressCheckpoint("primary-playing")

        let firstPlan = playbackStressPlan(durationSec: 1.2, barCount: 4)
        try model.playing.crossfadeTo(
            url: fixture.secondURL,
            track: fixture.secondTrack,
            durationSec: 1.2,
            startOffsetSec: 0.05,
            plan: firstPlan
        )
        try await waitUntil(
            timeoutSec: 1,
            intervalMilliseconds: 25,
            failure: {
                PlaybackStressError.crossfadeDidNotComplete(
                    playbackStressSnapshot(model.playing.session, expectedTrackId: fixture.secondTrack.id)
                )
            }
        ) {
                model.playing.session.mode == .crossfading &&
                model.playing.session.queuedTrack?.id == fixture.secondTrack.id &&
                model.playing.session.queuedElapsedSec > 0.12 &&
                model.playing.session.activeTransitionPlan?.transitionBarCount == 4
        }
        playbackStressCheckpoint("incoming-moving")

        let pausedIncomingPosition = model.playing.session.queuedElapsedSec
        let pausedProgress = model.playing.session.transitionProgress
        model.playing.pause()
        guard model.playing.session.mode == .paused,
              model.playing.session.activeTransitionPlan?.transitionTimingSource == .beatGrid
        else {
            throw PlaybackStressError.pauseFailed
        }
        try await sleep(milliseconds: 120)
        guard abs(model.playing.session.queuedElapsedSec - pausedIncomingPosition) < 0.05 else {
            throw PlaybackStressError.pauseFailed
        }
        try model.playing.resume()
        try await waitUntil(
            timeoutSec: 1,
            intervalMilliseconds: 25,
            failure: { PlaybackStressError.resumeFailed(playbackStressSnapshot(model.playing.session)) }
        ) {
            model.playing.session.mode == .crossfading &&
                model.playing.session.transitionProgress > pausedProgress &&
                model.playing.session.queuedElapsedSec > pausedIncomingPosition
        }
        playbackStressCheckpoint("crossfade-resumed")

        model.playing.simulateConfigurationRecoveryForTesting()
        try await waitUntil(
            timeoutSec: 2,
            intervalMilliseconds: 25,
            failure: { PlaybackStressError.recoveryFailed(playbackStressSnapshot(model.playing.session)) }
        ) {
            model.playing.session.recoveryNotice != nil &&
                (model.playing.session.mode == .crossfading || model.playing.session.mode == .playing)
        }
        if model.playing.session.mode == .crossfading,
           model.playing.session.activeTransitionPlan?.transitionBarCount != 4 {
            throw PlaybackStressError.recoveryFailed(playbackStressSnapshot(model.playing.session))
        }
        playbackStressCheckpoint("device-recovered")
        try await waitUntil(
            timeoutSec: 3,
            failure: {
                PlaybackStressError.crossfadeDidNotComplete(
                    playbackStressSnapshot(model.playing.session, expectedTrackId: fixture.secondTrack.id)
                )
            }
        ) {
            model.playing.session.mode == .playing &&
                model.playing.session.currentTrack?.id == fixture.secondTrack.id
        }
        playbackStressCheckpoint("first-transition-complete")

        let secondPlan = playbackStressPlan(durationSec: 0.45, barCount: 1)
        try model.playing.crossfadeTo(
            url: fixture.firstURL,
            track: fixture.firstTrack,
            durationSec: 0.45,
            startOffsetSec: 0.1,
            plan: secondPlan
        )
        try await waitUntil(
            timeoutSec: 3,
            intervalMilliseconds: 25,
            failure: { PlaybackStressError.crossfadeDidNotComplete(playbackStressSnapshot(model.playing.session)) }
        ) {
            model.playing.session.mode == .crossfading &&
                model.playing.session.queuedTrack?.id == fixture.firstTrack.id &&
                model.playing.session.queuedElapsedSec > 0.1
        }
        playbackStressCheckpoint("second-incoming-moving")
        try await waitUntil(
            timeoutSec: 3,
            failure: { PlaybackStressError.crossfadeDidNotComplete(playbackStressSnapshot(model.playing.session)) }
        ) {
            model.playing.session.mode == .playing &&
                model.playing.session.currentTrack?.id == fixture.firstTrack.id
        }
        playbackStressCheckpoint("second-transition-complete")

        model.playing.stop()
        guard model.playing.session.mode == .idle,
              model.playing.session.activeTransitionPlan == nil,
              model.playing.session.queuedElapsedSec == 0
        else {
            throw PlaybackStressError.stopFailed
        }
        return PlaybackStressResult(
            transitionsCompleted: 2,
            incomingPlayheadAdvanced: true,
            crossfadePauseResumePassed: true,
            deviceRecoveryPassed: true
        )
    }

    func playbackStressCheckpoint(_ checkpoint: String) {
        FileHandle.standardOutput.write(Data("BEATDROPPER_NATIVE_PLAYBACK_STRESS_STEP \(checkpoint)\n".utf8))
    }

    func playbackStressPlan(durationSec: Double, barCount: Int) -> MixPlan {
        MixPlan(
            transitionStartSec: 0,
            transitionEndSec: durationSec,
            nextTrackStartOffsetSec: 0.05,
            style: barCount == 1 ? .hardCut : .energySwap,
            confidence: 0.9,
            reasoningSummary: "packaged playback transition stress",
            tempoSync: MixTempoSyncPlan(enabled: barCount > 1, targetRate: barCount > 1 ? 120 / 124 : nil),
            phraseAlignment: .aligned,
            evidence: ["packaged playback stress"],
            mixControls: MixControlPlan(
                gain: MixGainPlan(outgoingTrimDb: -0.5, incomingTrimDb: -1),
                eq: MixThreeBandEQPlan(outgoingLowDb: -2, incomingLowDb: 1),
                filter: .conservativeDefaults,
                loudness: .conservativeDefaults,
                clipProtection: .conservativeDefaults,
                qualityNotes: ["exercise transition DSP"]
            ),
            transitionBarCount: barCount,
            transitionTimingSource: .beatGrid,
            synchronizedBPM: 120
        )
    }

    func sleep(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    func waitUntil(
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

    func playbackStressSnapshot(_ session: PlaybackSessionState, expectedTrackId: String? = nil) -> String {
        [
            "state=\(session.mode.rawValue)",
            "current=\(session.currentTrack?.id ?? "--")",
            "expected=\(expectedTrackId ?? "--")",
            "queued=\(session.queuedTrack?.id ?? "--")",
            "elapsed=\(String(format: "%.3f", session.currentElapsedSec))",
            "nextElapsed=\(String(format: "%.3f", session.queuedElapsedSec))",
            "remaining=\(String(format: "%.3f", session.currentRemainingSec))",
            "crossfade=\(String(format: "%.3f", session.transitionProgress))"
        ].joined(separator: "; ")
    }
}

private struct NativeOpenImportStressResult {
    var openedCount: Int
    var libraryRecordCount: Int
    var sourceFolderCount: Int
    var analyzedCount: Int
}

private struct PlaybackStressResult {
    var transitionsCompleted: Int
    var incomingPlayheadAdvanced: Bool
    var crossfadePauseResumePassed: Bool
    var deviceRecoveryPassed: Bool
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
    case recoveryFailed(String)
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
        case .recoveryFailed(let detail):
            return "audio-device recovery did not preserve the transition: \(detail)"
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
        try writeSineWave(url: firstURL, frequency: 220, durationSec: 4)
        try writeSineWave(url: secondURL, frequency: 330, durationSec: 4)

        return PlaybackStressFixture(
            folderURL: folderURL,
            firstURL: firstURL,
            secondURL: secondURL,
            firstTrack: Track(id: "native-stress-a", title: "Native Stress A", durationSec: 4, format: .wav, bpm: 120),
            secondTrack: Track(id: "native-stress-b", title: "Native Stress B", durationSec: 4, format: .wav, bpm: 124)
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

/// Deterministic playback adapter for the packaged session orchestration harness.
/// Real AVFoundation behavior is covered independently by playback stress.
@MainActor
private final class SessionStressAudioPlayback: AudioPlayback {
    @Published private(set) var session = PlaybackSessionState()
    var sessionPublisher: AnyPublisher<PlaybackSessionState, Never> { $session.eraseToAnyPublisher() }
    private var positionTimer: Timer?
    private var transitionTask: Task<Void, Never>?

    func setMasterGain(_ gain: Double) {}

    func prepareSession(currentTrack: Track?, queuedTrack: Track?) {
        session.apply(.prepared(currentTrack: currentTrack, queuedTrack: queuedTrack))
    }

    func loadPrimary(url: URL, track: Track) throws {
        session.apply(.primaryLoaded(track))
    }

    func play(url: URL, track: Track) throws {
        try loadPrimary(url: url, track: track)
        try play()
    }

    func playPreview(url: URL, track: Track, startOffsetSec: TimeInterval) throws {
        try play(url: url, track: track)
        publishPosition(current: startOffsetSec, incoming: 0, progress: 0)
    }

    func play() throws {
        session.apply(.started)
        startPositionTimer()
    }

    func resume() throws {
        session.apply(.resumed(transitionActive: session.queuedTrack != nil))
        startPositionTimer()
    }

    func crossfadeTo(
        url: URL,
        track: Track,
        durationSec: TimeInterval,
        startOffsetSec: TimeInterval,
        plan: MixPlan?,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?,
        completion: @escaping () -> Void
    ) throws {
        session.apply(.transitionStarted(queuedTrack: track, plan: plan))
        transitionTask?.cancel()
        let duration = max(0.05, durationSec)
        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration / 2))
            guard let self, !Task.isCancelled else { return }
            self.publishPosition(
                current: self.session.currentElapsedSec + duration / 2,
                incoming: startOffsetSec + duration / 2,
                progress: 0.5
            )
            try? await Task.sleep(for: .seconds(duration / 2))
            guard !Task.isCancelled else { return }
            self.session.apply(.transitionCompleted)
            completion()
        }
    }

    func pause() {
        session.apply(.paused)
        positionTimer?.invalidate()
        positionTimer = nil
    }

    func stop() {
        transitionTask?.cancel()
        transitionTask = nil
        positionTimer?.invalidate()
        positionTimer = nil
        session.apply(.stopped)
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.publishPosition(
                    current: self.session.currentElapsedSec + 0.05,
                    incoming: self.session.queuedElapsedSec,
                    progress: self.session.transitionProgress
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func publishPosition(current: Double, incoming: Double, progress: Double) {
        let remaining = max(0, (session.currentTrack?.durationSec ?? 0) - current)
        session.apply(.positionUpdated(
            current: current,
            incoming: incoming,
            remaining: remaining,
            transitionProgress: progress
        ))
    }
}
