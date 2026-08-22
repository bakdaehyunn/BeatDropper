import Testing
@testable import BeatDropperDomain

struct PlaybackSessionStateTests {
    @Test
    func preparedTracksAreAuthoritativeBeforePlaybackStarts() {
        var session = PlaybackSessionState()
        session.apply(.prepared(currentTrack: track("a"), queuedTrack: track("b")))

        #expect(session.mode == .idle)
        #expect(session.currentTrack?.id == "a")
        #expect(session.queuedTrack?.id == "b")
        #expect(session.currentRemainingSec == 120)
    }

    @Test
    func preparationCannotOverwriteAnActiveTransition() {
        var session = PlaybackSessionState(mode: .playing, currentTrack: track("a"))
        session.apply(.transitionStarted(queuedTrack: track("b"), plan: plan(source: "active")))
        session.apply(.prepared(currentTrack: track("c"), queuedTrack: track("d")))

        #expect(session.currentTrack?.id == "a")
        #expect(session.queuedTrack?.id == "b")
        #expect(session.activeTransitionPlan?.evidence == ["active"])
    }

    @Test
    func sanitizesPositionsAndTransitionProgress() {
        let current = Track(id: "current", title: "Current", durationSec: 120, format: .wav, bpm: 120)
        let queued = Track(id: "queued", title: "Queued", durationSec: 90, format: .wav, bpm: 124)

        let session = PlaybackSessionState(
            mode: .crossfading,
            currentTrack: current,
            queuedTrack: queued,
            currentElapsedSec: 200,
            queuedElapsedSec: -5,
            currentRemainingSec: -.infinity,
            transitionProgress: 2
        )

        #expect(session.currentElapsedSec == 120)
        #expect(session.queuedElapsedSec == 0)
        #expect(session.currentRemainingSec == 0)
        #expect(session.transitionProgress == 1)
        #expect(session.isPlaybackActive)
        #expect(session.isTransitionActive)
    }

    @Test
    func transitionRequiresCrossfadeAndQueuedTrack() {
        let current = Track(id: "current", title: "Current", durationSec: 120, format: .wav, bpm: 120)
        let playing = PlaybackSessionState(mode: .playing, currentTrack: current)
        let crossfadingWithoutQueue = PlaybackSessionState(mode: .crossfading, currentTrack: current)

        #expect(playing.isPlaybackActive)
        #expect(!playing.isTransitionActive)
        #expect(!crossfadingWithoutQueue.isTransitionActive)
    }

    @Test
    func normalNextTrackTransitionPromotesIncomingDeck() {
        var session = PlaybackSessionState(mode: .playing, currentTrack: track("a"))
        session.apply(.transitionStarted(queuedTrack: track("b"), plan: plan(source: "normal")))
        session.apply(.positionUpdated(current: 60, incoming: 4, remaining: 60, transitionProgress: 0.5))
        session.apply(.transitionCompleted)

        #expect(session.currentTrack?.id == "b")
        #expect(session.queuedTrack == nil)
        #expect(session.currentElapsedSec == 4)
        #expect(session.mode == .playing)
        #expect(session.activeTransitionPlan == nil)
    }

    @Test
    func incomingPlayheadProgressesIndependently() {
        var session = PlaybackSessionState(mode: .playing, currentTrack: track("a"))
        session.apply(.transitionStarted(queuedTrack: track("b"), plan: plan(source: "incoming")))
        session.apply(.positionUpdated(current: 32, incoming: 8, remaining: 88, transitionProgress: 0.25))

        #expect(session.currentElapsedSec == 32)
        #expect(session.queuedElapsedSec == 8)
        #expect(session.transitionProgress == 0.25)
    }

    @Test
    func pauseAndResumePreserveCrossfadeState() {
        var session = PlaybackSessionState(mode: .playing, currentTrack: track("a"))
        session.apply(.transitionStarted(queuedTrack: track("b"), plan: plan(source: "pause")))
        session.apply(.positionUpdated(current: 48, incoming: 2, remaining: 72, transitionProgress: 0.4))
        session.apply(.paused)
        #expect(session.mode == .paused)
        #expect(session.transitionProgress == 0.4)

        session.apply(.resumed(transitionActive: true))
        #expect(session.mode == .crossfading)
        #expect(session.queuedTrack?.id == "b")
        #expect(session.transitionProgress == 0.4)
    }

    @Test
    func deviceConfigurationRecoveryHasExplicitStatus() {
        var session = PlaybackSessionState(mode: .playing, currentTrack: track("a"))
        session.apply(.recoveryStarted)
        #expect(session.recoveryStatus == .recovering)
        session.apply(.recoverySucceeded("recovered"))
        #expect(session.recoveryStatus == .recovered("recovered"))
        #expect(session.recoveryNotice == "recovered")
    }

    @Test
    func manualBeatAlignedNextRetainsPlanAsAuthoritativeTransition() {
        var session = PlaybackSessionState(mode: .playing, currentTrack: track("a"))
        let manualPlan = plan(source: "manual beat-aligned next")
        session.apply(.transitionStarted(queuedTrack: track("b"), plan: manualPlan))

        #expect(session.activeTransitionPlan == manualPlan)
        #expect(session.mode == .crossfading)
    }

    @Test
    func aiAndFallbackPlansUseTheSameTransitionStateMachine() {
        for source in ["ai planner", "local fallback"] {
            var session = PlaybackSessionState(mode: .playing, currentTrack: track("a"))
            let selectedPlan = plan(source: source)
            session.apply(.transitionStarted(queuedTrack: track("b"), plan: selectedPlan))
            #expect(session.activeTransitionPlan?.evidence == [source])
            session.apply(.transitionCompleted)
            #expect(session.currentTrack?.id == "b")
        }
    }

    private func track(_ id: String) -> Track {
        Track(id: id, title: id, durationSec: 120, format: .wav, bpm: 120)
    }

    private func plan(source: String) -> MixPlan {
        MixPlan(
            transitionStartSec: 32,
            transitionEndSec: 48,
            nextTrackStartOffsetSec: 0,
            style: .smoothBlend,
            confidence: 0.9,
            reasoningSummary: source,
            tempoSync: MixTempoSyncPlan(enabled: true, targetRate: 1),
            evidence: [source],
            transitionBarCount: 8,
            transitionTimingSource: .beatGrid
        )
    }
}
