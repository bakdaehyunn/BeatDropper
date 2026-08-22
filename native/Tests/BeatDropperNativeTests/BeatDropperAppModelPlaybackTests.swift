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

    private func makeModel(
        audio: FakeAudioPlayback,
        scheduler: FakeAppScheduler = FakeAppScheduler()
    ) -> BeatDropperAppModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("beatdropper-native-tests-\(UUID().uuidString)", isDirectory: true)
        return BeatDropperAppModel(
            audioPlayback: audio,
            store: NativeLibraryStore(fileURL: root.appendingPathComponent("library.json")),
            settingsStore: NativeSettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            analysisStore: NativeTrackAnalysisStore(rootURL: root.appendingPathComponent("analysis", isDirectory: true)),
            mixReviewArtifactStore: MixReviewArtifactStore(fileURL: root.appendingPathComponent("reviews.json")),
            mixPlanner: FakeMixPlanner(),
            trackImporter: NativeTrackImporter(),
            clock: FixedAppClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
            scheduler: scheduler
        )
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
    var pauseCount = 0
    var resumeCount = 0

    func update(_ session: PlaybackSessionState) {
        subject.send(session)
    }

    func setMasterGain(_ gain: Double) {}
    func prepareSession(currentTrack: Track?, queuedTrack: Track?) {
        var next = subject.value
        next.apply(.prepared(currentTrack: currentTrack, queuedTrack: queuedTrack))
        subject.send(next)
    }
    func loadPrimary(url: URL, track: Track) throws { subject.value.currentTrack = track }
    func play(url: URL, track: Track) throws { playedTrackIDs.append(track.id) }
    func playPreview(url: URL, track: Track, startOffsetSec: TimeInterval) throws { playedTrackIDs.append(track.id) }
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
    func stop() { subject.send(PlaybackSessionState()) }
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
