import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Combine
import BeatDropperApplication
import Foundation
import Testing
@testable import BeatDropperNative

@MainActor
struct BeatDropperAppModelPlaybackTests {
    @Test
    func forwardsAuthoritativePlaybackSessionUpdates() {
        let audio = FakeAudioPlayback()
        let model = makeModel(audio: audio)
        let current = Track(id: "current", title: "Current", durationSec: 120, format: .wav, bpm: 120)
        let queued = Track(id: "queued", title: "Queued", durationSec: 100, format: .wav, bpm: 124)

        audio.update(
            PlaybackSessionState(
                mode: .crossfading,
                currentTrack: current,
                queuedTrack: queued,
                currentElapsedSec: 64,
                queuedElapsedSec: 8,
                transitionProgress: 0.35
            )
        )

        #expect(model.playing.session.mode == .crossfading)
        #expect(model.playing.session.currentTrack?.id == current.id)
        #expect(model.playing.session.queuedTrack?.id == queued.id)
        #expect(model.playing.session.currentElapsedSec == 64)
        #expect(model.playing.session.queuedElapsedSec == 8)
        #expect(model.playing.session.transitionProgress == 0.35)
        #expect(model.playing.currentDisplayTrack?.id == current.id)
        #expect(model.playing.nextDisplayTrack?.id == queued.id)
    }

    @Test
    func transportCommandsUseInjectedAudioBoundary() {
        let audio = FakeAudioPlayback()
        let model = makeModel(audio: audio)
        let imported = importedTrack(id: "track")
        model.libraryActions.playlist = [imported]
        model.libraryActions.selectedTrackID = imported.id

        model.playingActions.playPause()

        #expect(audio.playedTrackIDs == [imported.id])

        audio.update(PlaybackSessionState(mode: .playing, currentTrack: imported.track))
        model.playingActions.playPause()
        #expect(audio.pauseCount == 1)

        audio.update(PlaybackSessionState(mode: .paused, currentTrack: imported.track))
        model.playingActions.playPause()
        #expect(audio.resumeCount == 1)
    }

    @Test
    func plannerScheduleUsesInjectedSchedulerAndSessionState() {
        let audio = FakeAudioPlayback()
        let scheduler = FakeAppScheduler()
        let model = makeModel(audio: audio, scheduler: scheduler)
        let current = importedTrack(id: "current")
        let queued = importedTrack(id: "queued")
        model.libraryActions.playlist = [current, queued]
        model.libraryActions.selectedTrackID = current.id
        model.planningActions.currentMixPlan = mixPlan(current: current.track, queued: queued.track)
        model.planningActions.currentMixPlanPair = PlannedMixPair(currentTrackId: current.id, nextTrackId: queued.id)
        audio.update(PlaybackSessionState(mode: .playing, currentTrack: current.track, currentElapsedSec: 10))

        model.planningActions.startMixPlanSchedulerIfNeeded()

        #expect(scheduler.intervals == [0.2])
        #expect(scheduler.activeScheduleCount == 1)

        model.planningActions.stopMixPlanScheduler()
        #expect(scheduler.cancelCount == 1)
        #expect(scheduler.activeScheduleCount == 0)
    }

    @Test
    func manualNextCoordinatesPlayingLibraryAndPlanningFeatures() {
        let audio = FakeAudioPlayback()
        let scheduler = FakeAppScheduler()
        let model = makeModel(audio: audio, scheduler: scheduler)
        let current = importedTrack(id: "current")
        let queued = importedTrack(id: "queued")
        model.libraryActions.playlist = [current, queued]
        model.libraryActions.selectedTrackID = current.id
        audio.update(PlaybackSessionState(mode: .playing, currentTrack: current.track, currentElapsedSec: 12))

        model.playingActions.playNextTrack()

        #expect(model.playing.session.mode == .crossfading)
        #expect(model.playing.session.queuedTrack?.id == queued.id)
        #expect(model.playing.session.activeTransitionPlan != nil)
        #expect(model.library.selectedTrackID == queued.id)
        #expect(model.mixPlanning.currentPlan == nil)
        #expect(!model.mixPlanning.isManualTransitionScheduled)
        #expect(scheduler.cancelCount == 1)
        #expect(scheduler.activeScheduleCount == 0)
        #expect(model.shell.notice.hasPrefix("Next queued on bar"))
    }

    @Test
    func cancelPlanningOwnsSchedulerCancellationAndStateReset() {
        let audio = FakeAudioPlayback()
        let scheduler = FakeAppScheduler()
        let model = makeModel(audio: audio, scheduler: scheduler)
        let current = importedTrack(id: "current")
        let queued = importedTrack(id: "queued")
        model.libraryActions.playlist = [current, queued]
        model.libraryActions.selectedTrackID = current.id
        model.mixPlanning.isEnabled = true
        model.planningActions.currentMixPlan = mixPlan(current: current.track, queued: queued.track)
        model.planningActions.currentMixPlanPair = PlannedMixPair(currentTrackId: current.id, nextTrackId: queued.id)
        audio.update(PlaybackSessionState(mode: .playing, currentTrack: current.track, currentElapsedSec: 10))
        model.planningActions.startMixPlanSchedulerIfNeeded()

        model.planningActions.cancelMixPlan()

        #expect(!model.mixPlanning.isEnabled)
        #expect(model.mixPlanning.currentPlan == nil)
        #expect(model.mixPlanning.currentPair == nil)
        #expect(model.mixPlanning.schedule == nil)
        #expect(scheduler.cancelCount == 1)
        #expect(scheduler.activeScheduleCount == 0)
    }

    @Test
    func settingsRestoreAndUpdatesSanitizePersistAndInvalidatePlanning() {
        let audio = FakeAudioPlayback()
        let repository = RecordingSettingsRepository(
            loaded: PlayerSettings(fadeDurationSec: 12, masterGain: 0.7, aiDjMode: .balanced)
        )
        let model = makeModel(audio: audio, settingsStore: repository)
        let current = importedTrack(id: "current")
        let queued = importedTrack(id: "queued")
        model.planningActions.currentMixPlan = mixPlan(current: current.track, queued: queued.track)

        #expect(model.shell.settings.fadeDurationSec == 12)
        #expect(model.shell.settings.masterGain == 0.7)
        #expect(audio.masterGains.last == 0.7)

        model.settingsActions.updateFadeDuration(500)
        #expect(model.shell.settings.fadeDurationSec == 20)
        #expect(model.mixPlanning.currentPlan == nil)
        #expect(repository.saved.last?.fadeDurationSec == 20)

        model.planningActions.currentMixPlan = mixPlan(current: current.track, queued: queued.track)
        model.settingsActions.updateMasterGain(-2)
        #expect(model.shell.settings.masterGain == 0)
        #expect(model.mixPlanning.currentPlan != nil)
        #expect(audio.masterGains.last == 0)
    }

    @Test
    func settingsFailuresUseDefaultsAndSurfaceSaveErrors() {
        let audio = FakeAudioPlayback()
        let repository = RecordingSettingsRepository(loaded: nil, loadError: TestFailure.load, saveError: TestFailure.save)
        let model = makeModel(audio: audio, settingsStore: repository)

        #expect(model.shell.settings == .defaults)
        #expect(audio.masterGains.last == PlayerSettings.defaults.masterGain)

        model.settingsActions.updateMasterGain(0.4)
        #expect(model.shell.settings.masterGain == 0.4)
        #expect(model.shell.notice.contains("Could not save settings"))
    }

    @Test
    func creativePreviewClampsPositionAndBPMPreparationPersists() {
        let audio = FakeAudioPlayback()
        let clock = MutableAppClock(now: Date(timeIntervalSince1970: 3_000))
        let store = RecordingLibraryRepository()
        let model = makeModel(audio: audio, store: store, clock: clock)
        let imported = importedTrack(id: "creative")
        install(imported, in: model)

        model.creativeActions.previewCreativeTrack(at: 999)
        #expect(audio.previewRequests.last?.trackID == imported.id)
        #expect(audio.previewRequests.last?.offset == imported.track.durationSec)

        model.creativeActions.tapBPMForCreativeTrack()
        clock.now = clock.now.addingTimeInterval(0.5)
        model.creativeActions.tapBPMForCreativeTrack()
        #expect(model.creative.bpmTapEstimate == 120)
        model.creativeActions.applyTappedBPMToCreativeTrack()
        #expect(model.library.preparation(forTrackID: imported.id).bpmOverride == 120)

        audio.update(PlaybackSessionState(mode: .paused, currentTrack: imported.track, currentElapsedSec: 45))
        model.creativeActions.addCreativeHotCue(kind: .drop)
        #expect(model.library.preparation(forTrackID: imported.id).hotCues.last?.timeSec == 45)
        #expect(store.savedStates.last?.trackRecords.first?.preparation.hotCues.count == 1)
    }

    @Test
    func clearPlaylistStopsPlaybackClearsPlanningAndPersistsEmptySet() {
        let audio = FakeAudioPlayback()
        let store = RecordingLibraryRepository()
        let model = makeModel(audio: audio, store: store)
        let current = importedTrack(id: "current")
        let queued = importedTrack(id: "queued")
        install([current, queued], in: model)
        model.planningActions.currentMixPlan = mixPlan(current: current.track, queued: queued.track)
        model.planningActions.currentMixPlanPair = PlannedMixPair(currentTrackId: current.id, nextTrackId: queued.id)

        model.libraryActions.clearPlaylist()

        #expect(audio.stopCount == 1)
        #expect(model.library.playlist.isEmpty)
        #expect(model.library.selectedTrackID == nil)
        #expect(model.mixPlanning.currentPlan == nil)
        #expect(store.savedStates.last?.currentPlaylistTrackIds.isEmpty == true)
        #expect(model.shell.notice == "Cleared playlist")
    }

    @Test
    func externalOpenWorkflowImportsReconcilesPersistsAndPreparesPlaybackState() async {
        let audio = FakeAudioPlayback()
        let store = RecordingLibraryRepository()
        let sourceURL = URL(fileURLWithPath: "/tmp/workflow.wav")
        let imported = ImportedTrack(
            track: Track(id: "workflow", title: "Workflow", durationSec: 90, format: .wav, bpm: 122),
            url: sourceURL,
            sourceFolderPath: nil,
            fileFingerprint: nil,
            missing: false,
            missingAt: nil
        )
        let importer = StubTrackImporter(
            selection: NativeOpenImportSelection(audioFileURLs: [sourceURL], folderURLs: [], unsupportedURLs: []),
            importedTracks: [imported]
        )
        let model = makeModel(
            audio: audio,
            store: store,
            trackImporter: importer,
            trackAnalyzer: FailingTrackAnalyzer()
        )

        let openedCount = await model.libraryActions.openExternalItems([sourceURL], sourceName: "test")

        #expect(openedCount == 1)
        #expect(model.library.playlist.map(\.id) == [imported.id])
        #expect(model.library.records.map(\.id) == [imported.id])
        #expect(model.library.selectedTrackID == imported.id)
        #expect(model.playing.session.currentTrack?.id == imported.id)
        #expect(store.savedStates.last?.currentPlaylistTrackIds == [imported.id])
        #expect(model.shell.notice == "Opened 1 tracks from test")
    }

    @Test
    func plannerSuccessPublishesPlanReviewAndPairThroughFeatureState() async {
        let audio = FakeAudioPlayback()
        let current = importedTrack(id: "current")
        let queued = importedTrack(id: "queued")
        let plan = mixPlan(current: current.track, queued: queued.track)
        let planner = StubMixPlanner(plan: plan, source: "local-fallback", reason: "test fallback")
        let model = makeModel(audio: audio, mixPlanner: planner)
        install([current, queued], in: model)

        model.planningActions.requestMixPlanForNextTrack()
        await waitUntil { !model.mixPlanning.isPlanning }

        #expect(model.mixPlanning.currentPlan == plan)
        #expect(model.mixPlanning.currentPair == PlannedMixPair(currentTrackId: current.id, nextTrackId: queued.id))
        #expect(model.mixPlanning.currentReview?.source == "local-fallback")
        #expect(model.mixReview.recentEvents.count == 1)
        #expect(model.shell.notice.contains("Local fallback mix plan ready"))
    }

    @Test
    func plannerNoResultClearsPreviousStateAndSurfacesReason() async {
        let audio = FakeAudioPlayback()
        let current = importedTrack(id: "current")
        let queued = importedTrack(id: "queued")
        let planner = StubMixPlanner(plan: nil, source: "test", reason: "planner unavailable")
        let model = makeModel(audio: audio, mixPlanner: planner)
        install([current, queued], in: model)
        model.planningActions.currentMixPlan = mixPlan(current: current.track, queued: queued.track)

        model.planningActions.requestMixPlanForNextTrack()
        await waitUntil { !model.mixPlanning.isPlanning }

        #expect(model.mixPlanning.currentPlan == nil)
        #expect(model.mixPlanning.currentPair == nil)
        #expect(model.mixPlanning.status == "planner unavailable")
        #expect(model.shell.notice == "planner unavailable")
    }

    @Test
    func mixReviewRestoreAndAnnotationUpdatePersistThroughRepositoryBoundary() {
        let artifactID = UUID()
        let artifact = PersistedMixReviewArtifact(
            id: artifactID.uuidString,
            importedAt: "2024-01-01T00:00:00Z",
            fileName: "review.md",
            format: "Markdown",
            content: "# BeatDropper Mix Review\n",
            reviewCount: 1
        )
        let repository = RecordingMixReviewRepository(loaded: MixReviewArtifactState(artifacts: [artifact]))
        let model = makeModel(audio: FakeAudioPlayback(), mixReviewStore: repository)

        #expect(model.mixReview.importedArtifacts.map(\.id) == [artifactID])
        let oversizedAnnotation = String(repeating: "x", count: mixReviewArtifactAnnotationCharacterLimit + 100)
        model.reviewActions.updateImportedMixReviewArtifactAnnotation(
            for: artifactID,
            annotation: oversizedAnnotation
        )

        #expect(model.reviewActions.importedMixReviewArtifactAnnotation(for: artifactID).count == mixReviewArtifactAnnotationCharacterLimit)
        #expect(repository.savedStates.last?.artifacts.first?.reviewAnnotation.count == mixReviewArtifactAnnotationCharacterLimit)
    }

    private func makeModel(
        audio: FakeAudioPlayback,
        scheduler: FakeAppScheduler = FakeAppScheduler(),
        store: (any LibraryRepository)? = nil,
        settingsStore: (any SettingsRepository)? = nil,
        mixReviewStore: (any MixReviewRepository)? = nil,
        mixPlanner: any MixPlanning = FakeMixPlanner(),
        clock: any AppClock = FixedAppClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
        trackImporter: any TrackImporting = NativeTrackImporter(),
        trackAnalyzer: any TrackAnalyzing = NativeTrackAnalysisService()
    ) -> BeatDropperAppModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("beatdropper-native-tests-\(UUID().uuidString)", isDirectory: true)
        return BeatDropperAppModel(
            audioPlayback: audio,
            store: store ?? NativeLibraryStore(fileURL: root.appendingPathComponent("library.json")),
            settingsStore: settingsStore ?? NativeSettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            analysisStore: NativeTrackAnalysisStore(rootURL: root.appendingPathComponent("analysis", isDirectory: true)),
            mixReviewArtifactStore: mixReviewStore ?? MixReviewArtifactStore(fileURL: root.appendingPathComponent("reviews.json")),
            mixPlanner: mixPlanner,
            trackImporter: trackImporter,
            trackAnalyzer: trackAnalyzer,
            clock: clock,
            scheduler: scheduler
        )
    }

    private func install(_ imported: ImportedTrack, in model: BeatDropperAppModel) {
        install([imported], in: model)
    }

    private func install(_ imported: [ImportedTrack], in model: BeatDropperAppModel) {
        let timestamp = "2024-01-01T00:00:00Z"
        model.libraryActions.libraryRecords = imported.map {
            NativeTrackRecord(
                track: $0.track,
                filePath: $0.url.path,
                addedAt: timestamp,
                updatedAt: timestamp
            )
        }
        model.libraryActions.playlist = imported
        model.libraryActions.selectedTrackID = imported.first?.id
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func importedTrack(id: String) -> ImportedTrack {
        ImportedTrack(
            track: Track(id: id, title: id.capitalized, durationSec: 120, format: .wav, bpm: 120),
            url: URL(fileURLWithPath: "/dev/null"),
            sourceFolderPath: nil,
            fileFingerprint: nil,
            missing: false,
            missingAt: nil
        )
    }

    private func mixPlan(current: Track, queued: Track) -> MixPlan {
        MixPlan(
            transitionStartSec: 96,
            transitionEndSec: 112,
            nextTrackStartOffsetSec: 0,
            style: .smoothBlend,
            confidence: 0.8,
            reasoningSummary: "test",
            tempoSync: MixTempoSyncPlan(enabled: true, targetRate: queued.bpm.map { current.bpm! / $0 }),
            candidateId: "test",
            phraseAlignment: .aligned,
            energyStrategy: .maintain
        )
    }
}

@MainActor
private final class FakeAudioPlayback: AudioPlayback {
    private let subject = CurrentValueSubject<PlaybackSessionState, Never>(PlaybackSessionState())
    var session: PlaybackSessionState { subject.value }
    var sessionPublisher: AnyPublisher<PlaybackSessionState, Never> { subject.eraseToAnyPublisher() }
    var playedTrackIDs: [String] = []
    var previewRequests: [(trackID: String, offset: TimeInterval)] = []
    var masterGains: [Double] = []
    var pauseCount = 0
    var resumeCount = 0
    var stopCount = 0

    func update(_ session: PlaybackSessionState) {
        subject.send(session)
    }

    func setMasterGain(_ gain: Double) { masterGains.append(gain) }
    func prepareSession(currentTrack: Track?, queuedTrack: Track?) {
        var next = subject.value
        next.apply(.prepared(currentTrack: currentTrack, queuedTrack: queuedTrack))
        subject.send(next)
    }
    func loadPrimary(url: URL, track: Track) throws { subject.value.currentTrack = track }
    func play(url: URL, track: Track) throws { playedTrackIDs.append(track.id) }
    func playPreview(url: URL, track: Track, startOffsetSec: TimeInterval) throws {
        playedTrackIDs.append(track.id)
        previewRequests.append((track.id, startOffsetSec))
    }
    func play() throws {}
    func resume() throws { resumeCount += 1 }
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
        var next = subject.value
        next.mode = .crossfading
        next.queuedTrack = track
        next.activeTransitionPlan = plan
        subject.send(next)
    }
    func pause() { pauseCount += 1 }
    func stop() {
        stopCount += 1
        subject.send(PlaybackSessionState())
    }
}

private struct FakeMixPlanner: MixPlanning {
    func requestMixPlan(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        timeoutSec: TimeInterval
    ) async -> NativeMixPlannerResult {
        NativeMixPlannerResult(
            plan: nil,
            source: "test",
            reason: "unused",
            request: request,
            response: nil,
            shadowFallbackPlan: nil,
            shadowFallbackReason: nil
        )
    }
}

private struct StubMixPlanner: MixPlanning {
    var plan: MixPlan?
    var source: String
    var reason: String?

    func requestMixPlan(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        timeoutSec: TimeInterval
    ) async -> NativeMixPlannerResult {
        NativeMixPlannerResult(
            plan: plan,
            source: source,
            reason: reason,
            request: request,
            response: nil,
            shadowFallbackPlan: nil,
            shadowFallbackReason: nil
        )
    }
}

private final class MutableAppClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class RecordingSettingsRepository: SettingsRepository, @unchecked Sendable {
    let loaded: PlayerSettings?
    let loadError: Error?
    let saveError: Error?
    private(set) var saved: [PlayerSettings] = []

    init(loaded: PlayerSettings?, loadError: Error? = nil, saveError: Error? = nil) {
        self.loaded = loaded
        self.loadError = loadError
        self.saveError = saveError
    }

    func loadMigratingLegacyDesktopSettingsIfNeeded() throws -> PlayerSettings {
        if let loadError { throw loadError }
        return loaded ?? .defaults
    }

    func save(_ settings: PlayerSettings) throws {
        if let saveError { throw saveError }
        saved.append(settings)
    }
}

private final class RecordingLibraryRepository: LibraryRepository, @unchecked Sendable {
    private(set) var savedStates: [NativeLibraryState] = []

    func loadMigratingLegacyDesktopStateIfNeeded() throws -> NativeLibraryState {
        NativeLibraryState()
    }

    func save(_ state: NativeLibraryState) throws {
        savedStates.append(state)
    }
}

private final class RecordingMixReviewRepository: MixReviewRepository, @unchecked Sendable {
    let loaded: MixReviewArtifactState
    private(set) var savedStates: [MixReviewArtifactState] = []

    init(loaded: MixReviewArtifactState) {
        self.loaded = loaded
    }

    func load() throws -> MixReviewArtifactState {
        loaded
    }

    func save(_ state: MixReviewArtifactState) throws {
        savedStates.append(state)
    }
}

private final class StubTrackImporter: TrackImporting, @unchecked Sendable {
    let selection: NativeOpenImportSelection
    let importedTracks: [ImportedTrack]

    init(selection: NativeOpenImportSelection, importedTracks: [ImportedTrack]) {
        self.selection = selection
        self.importedTracks = importedTracks
    }

    @MainActor func openAudioFiles() -> [URL] { [] }
    @MainActor func openReplacementAudioFile() -> URL? { nil }
    @MainActor func openMusicFolder() -> URL? { nil }
    func importTracks(from urls: [URL]) async -> [ImportedTrack] { importedTracks }
    func importFolder(_ folderURL: URL) async -> [ImportedTrack] { importedTracks }
    func classifyOpenURLs(_ urls: [URL]) -> NativeOpenImportSelection { selection }
    func importTrack(from url: URL) async -> ImportedTrack? { importedTracks.first }
    func fileExists(at url: URL) -> Bool { true }
    func fileSize(at url: URL) -> Int64 { 1_024 }
}

private struct FailingTrackAnalyzer: TrackAnalyzing {
    func analyze(track: Track, url: URL) async throws -> TrackAnalysis {
        throw TestFailure.load
    }

    func currentFileRevision(for url: URL) throws -> TrackFileRevision {
        throw TestFailure.load
    }
}

private enum TestFailure: LocalizedError {
    case load
    case save

    var errorDescription: String? {
        switch self {
        case .load: "test load failure"
        case .save: "test save failure"
        }
    }
}

private struct FixedAppClock: AppClock {
    var now: Date
}

@MainActor
private final class FakeAppScheduler: AppScheduling {
    var intervals: [TimeInterval] = []
    var activeScheduleCount = 0
    var cancelCount = 0

    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any AppSchedule {
        intervals.append(interval)
        activeScheduleCount += 1
        return FakeSchedule(owner: self)
    }

    private func didCancel() {
        cancelCount += 1
        activeScheduleCount -= 1
    }

    private final class FakeSchedule: AppSchedule {
        weak var owner: FakeAppScheduler?
        var isCancelled = false

        init(owner: FakeAppScheduler) {
            self.owner = owner
        }

        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            owner?.didCancel()
        }
    }
}
