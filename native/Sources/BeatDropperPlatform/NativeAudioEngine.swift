import AVFoundation
import BeatDropperDomain
import BeatDropperDSP
import Combine
import Foundation

@MainActor
public final class NativeAudioEngine: ObservableObject {
    public typealias PlaybackState = PlaybackSessionMode

    @Published public private(set) var session = PlaybackSessionState()

    public var sessionPublisher: AnyPublisher<PlaybackSessionState, Never> {
        $session.eraseToAnyPublisher()
    }

    public var state: PlaybackState {
        get { session.mode }
        set { session.mode = newValue }
    }

    public var currentTrack: Track? {
        get { session.currentTrack }
        set { session.currentTrack = newValue }
    }

    public var queuedTrack: Track? {
        get { session.queuedTrack }
        set { session.queuedTrack = newValue }
    }

    public var crossfadeProgress: Double {
        get { session.transitionProgress }
        set { session.transitionProgress = CrossfadeMath.clampedProgress(newValue) }
    }

    public var elapsedSec: Double {
        get { session.currentElapsedSec }
        set { session.currentElapsedSec = newValue }
    }

    public var nextDeckElapsedSec: Double {
        get { session.queuedElapsedSec }
        set { session.queuedElapsedSec = newValue }
    }

    public var activeTransitionPlan: MixPlan? {
        get { session.activeTransitionPlan }
        set { session.activeTransitionPlan = newValue }
    }

    public var remainingSec: Double {
        get { session.currentRemainingSec }
        set { session.currentRemainingSec = newValue }
    }

    public var outputMeter: AudioLevelMeter {
        get { session.outputMeter }
        set { session.outputMeter = newValue }
    }

    public var recoveryNotice: String? {
        get { session.recoveryNotice }
        set { session.recoveryNotice = newValue }
    }

    private let graph = NativeAudioGraph()
    private let deckScheduler = DeckScheduler()
    private let meterPublisher = AudioMeterPublisher()
    private let positionPublisher = PlaybackPositionPublisher()
    private let crossfade = CrossfadeStateMachine()
    private let configurationRecovery = AudioConfigurationRecoveryCoordinator()
    private lazy var dspApplicator = PlaybackDSPApplicator(graph: graph)

    private var engine: AVAudioEngine { graph.engine }
    private var deckA: Deck { graph.deckA }
    private var deckB: Deck { graph.deckB }
    private var activeSlot: DeckSlot {
        get { graph.activeSlot }
        set { graph.activeSlot = newValue }
    }
    private var masterDSPSettings: PlaybackMasterDSPSettings { dspApplicator.masterSettings }
    private var fadeDurationSec: TimeInterval {
        get { crossfade.durationSec }
        set { crossfade.durationSec = newValue }
    }
    private var fadeTargetSlot: DeckSlot? {
        get { crossfade.targetSlot }
        set { crossfade.targetSlot = newValue }
    }
    private var fadeCompletion: (() -> Void)? {
        get { crossfade.completion }
        set { crossfade.completion = newValue }
    }
    private var stateBeforePause: PlaybackState {
        get { crossfade.stateBeforePause }
        set { crossfade.stateBeforePause = newValue }
    }
    private var pausedCrossfadeProgress: Double? {
        get { crossfade.pausedProgress }
        set { crossfade.pausedProgress = newValue }
    }

    public init() {
        configureMasterDSP(.neutral)
        installAudioMeterTaps()
        observeEngineConfigurationChanges()
    }

    public var isPlaybackActive: Bool {
        session.isPlaybackActive
    }

    public var currentDeckMeter: AudioLevelMeter {
        session.currentDeckMeter
    }

    public var nextDeckMeter: AudioLevelMeter {
        session.queuedDeckMeter
    }

    public func prepareSession(currentTrack: Track?, queuedTrack: Track?) {
        session.apply(.prepared(currentTrack: currentTrack, queuedTrack: queuedTrack))
    }

    public func setMasterGain(_ gain: Double) {
        let clamped = min(1, max(0, gain.isFinite ? gain : PlayerSettings.defaults.masterGain))
        graph.setMasterGain(clamped)
    }

    public func loadPrimary(url: URL, track: Track) throws {
        stop()
        try prepare(deck: activeDeck, url: url, track: track, volume: 1)
        session.apply(.primaryLoaded(track))
        publishPosition()
    }

    public func play(url: URL, track: Track) throws {
        if currentTrack?.id != track.id || activeDeck.file == nil {
            try loadPrimary(url: url, track: track)
        }
        try play()
    }

    public func playPreview(url: URL, track: Track, startOffsetSec: TimeInterval) throws {
        stop()
        try prepare(deck: activeDeck, url: url, track: track, volume: 1, startOffsetSec: startOffsetSec)
        session.apply(.primaryLoaded(track))
        try play()
    }

    public func play() throws {
        guard activeDeck.file != nil else {
            return
        }

        session.recoveryStatus = .ready
        try startEngineIfNeeded()
        scheduleIfNeeded(activeDeck)
        activeDeck.node.play()
        activeDeck.mixer.outputVolume = 1

        session.apply(.started)
        startPositionTimer()
    }

    public func resume() throws {
        guard state == .paused else {
            return
        }

        try startEngineIfNeeded()
        if deckA.scheduled {
            deckA.node.play()
        }
        if deckB.scheduled {
            deckB.node.play()
        }

        if stateBeforePause == .crossfading {
            session.apply(.resumed(transitionActive: true))
            let startProgress = pausedCrossfadeProgress ?? crossfadeProgress
            startFadeTimer(from: startProgress)
            pausedCrossfadeProgress = nil
        } else {
            session.apply(.resumed(transitionActive: false))
        }
        startPositionTimer()
    }

    public func crossfadeTo(
        url: URL,
        track: Track,
        durationSec: TimeInterval,
        startOffsetSec: TimeInterval = 0,
        plan: MixPlan? = nil,
        currentAnalysis: TrackAnalysis? = nil,
        nextAnalysis: TrackAnalysis? = nil,
        completion: @escaping () -> Void = {}
    ) throws {
        guard currentTrack?.id != track.id else {
            completion()
            return
        }

        guard isPlaybackActive, activeDeck.file != nil else {
            try play(url: url, track: track)
            completion()
            return
        }

        cancelFadeKeepingCurrentDeck()
        let targetDeck = inactiveDeck
        try prepare(deck: targetDeck, url: url, track: track, volume: 0, startOffsetSec: startOffsetSec)
        activeDeck.targetDSPSettings = PlaybackDSPResolver.deckSettings(
            plan: plan,
            role: .outgoing,
            analysis: currentAnalysis
        )
        targetDeck.targetDSPSettings = PlaybackDSPResolver.deckSettings(
            plan: plan,
            role: .incoming,
            analysis: nextAnalysis
        )
        activeDeck.transitionStartDSPSettings = activeDeck.appliedDSPSettings
        targetDeck.transitionStartDSPSettings = targetDeck.targetDSPSettings
        configure(deck: targetDeck, settings: targetDeck.targetDSPSettings, filterProgress: 0, immediate: true)
        configureMasterDSP(PlaybackDSPResolver.masterSettings(plan: plan))
        try startEngineIfNeeded()
        scheduleIfNeeded(activeDeck)
        scheduleIfNeeded(targetDeck)

        if !activeDeck.node.isPlaying {
            activeDeck.node.play()
        }
        targetDeck.node.play()

        session.apply(.transitionStarted(queuedTrack: track, plan: plan))
        crossfade.begin(targetSlot: targetDeck.slot, durationSec: durationSec, completion: completion)
        applyCrossfadeGains(progress: 0)
        startFadeTimer(from: 0)
        startPositionTimer()
    }

    public func pause() {
        guard isPlaybackActive else {
            return
        }

        crossfade.pause(from: state, progress: crossfadeProgress)
        deckA.node.pause()
        deckB.node.pause()
        session.apply(.paused)
        stopPositionTimer()
        publishPosition()
        silenceMeters()
    }

    public func stop() {
        crossfade.stopTimer()
        stopPositionTimer()
        fadeCompletion = nil
        fadeTargetSlot = nil
        pausedCrossfadeProgress = nil
        deckA.stopAndClearSchedule()
        deckB.stopAndClearSchedule()
        activeDeck.mixer.outputVolume = 1
        inactiveDeck.mixer.outputVolume = 0
        activeDeck.resetDSP()
        inactiveDeck.resetDSP()
        configureMasterDSP(.neutral)
        silenceMeters()
        session.apply(.stopped)
    }

    public func simulateConfigurationChangeRecoveryForAutomation() {
        // Automation validates the state-preservation contract without forcing a
        // synthetic AVAudioEngine reset, which can block indefinitely when the
        // packaged process is running against a headless/default test device.
        // Real AVAudioEngineConfigurationChange notifications still execute the
        // full graph snapshot, reset, reschedule, and resume path above.
        session.apply(.recoveryStarted)
        session.apply(.recoverySucceeded("Audio engine recovered after device change"))
    }

    private var activeDeck: Deck {
        graph.activeDeck
    }

    private var inactiveDeck: Deck {
        graph.inactiveDeck
    }

    private func deck(for slot: DeckSlot) -> Deck {
        graph.deck(for: slot)
    }

    private func prepare(deck: Deck, url: URL, track: Track, volume: Float, startOffsetSec: TimeInterval = 0) throws {
        try deckScheduler.prepare(
            deck: deck,
            url: url,
            track: track,
            volume: volume,
            startOffsetSec: startOffsetSec
        )
    }

    private func startEngineIfNeeded() throws {
        try graph.startIfNeeded()
    }

    private func observeEngineConfigurationChanges() {
        configurationRecovery.observe(engine: engine) { [weak self] in
            self?.recoverAfterEngineConfigurationChange()
        }
    }

    private func recoverAfterEngineConfigurationChange() {
        guard configurationRecovery.beginIfAllowed(isIdle: state == .idle) else {
            return
        }
        session.apply(.recoveryStarted)
        defer { configurationRecovery.finish() }

        let snapshot = PlaybackRecoverySnapshot(
            state: state,
            activeSlot: activeSlot,
            active: DeckRecoverySnapshot(deck: activeDeck),
            inactive: DeckRecoverySnapshot(deck: inactiveDeck),
            crossfadeProgress: crossfadeProgress,
            fadeDurationSec: fadeDurationSec,
            fadeTargetSlot: fadeTargetSlot,
            stateBeforePause: stateBeforePause,
            pausedCrossfadeProgress: pausedCrossfadeProgress,
            masterDSPSettings: masterDSPSettings
        )

        crossfade.stopTimer()
        stopPositionTimer()
        deckA.stopAndClearSchedule()
        deckB.stopAndClearSchedule()
        engine.stop()
        engine.reset()

        do {
            try restoreAfterConfigurationChange(snapshot)
            session.apply(.recoverySucceeded("Audio engine recovered after device change"))
        } catch {
            stop()
            session.apply(.recoveryFailed("Audio recovery failed: \(error.localizedDescription)"))
        }
    }

    private func restoreAfterConfigurationChange(_ snapshot: PlaybackRecoverySnapshot) throws {
        activeSlot = snapshot.activeSlot
        guard let activeURL = snapshot.active.url,
              let activeTrack = snapshot.active.track
        else {
            stop()
            return
        }

        try prepare(
            deck: activeDeck,
            url: activeURL,
            track: activeTrack,
            volume: snapshot.active.volume,
            startOffsetSec: snapshot.active.positionSec
        )
        activeDeck.appliedDSPSettings = snapshot.active.appliedDSPSettings
        activeDeck.targetDSPSettings = snapshot.active.targetDSPSettings
        activeDeck.transitionStartDSPSettings = snapshot.active.transitionStartDSPSettings
        configure(
            deck: activeDeck,
            settings: snapshot.active.appliedDSPSettings,
            filterProgress: snapshot.crossfadeProgress,
            immediate: true
        )
        currentTrack = activeTrack
        configureMasterDSP(snapshot.masterDSPSettings)

        let shouldRestoreCrossfadeDeck = snapshot.state == .crossfading ||
            snapshot.stateBeforePause == .crossfading ||
            snapshot.fadeTargetSlot != nil
        if shouldRestoreCrossfadeDeck,
           let targetSlot = snapshot.fadeTargetSlot,
           let targetURL = snapshot.inactive.url,
           let targetTrack = snapshot.inactive.track {
            try prepare(
                deck: deck(for: targetSlot),
                url: targetURL,
                track: targetTrack,
                volume: snapshot.inactive.volume,
                startOffsetSec: snapshot.inactive.positionSec
            )
            let restoredTargetDeck = deck(for: targetSlot)
            restoredTargetDeck.appliedDSPSettings = snapshot.inactive.appliedDSPSettings
            restoredTargetDeck.targetDSPSettings = snapshot.inactive.targetDSPSettings
            restoredTargetDeck.transitionStartDSPSettings = snapshot.inactive.transitionStartDSPSettings
            configure(
                deck: restoredTargetDeck,
                settings: snapshot.inactive.appliedDSPSettings,
                filterProgress: snapshot.crossfadeProgress,
                immediate: true
            )
            queuedTrack = targetTrack
            fadeTargetSlot = targetSlot
            fadeDurationSec = max(0.1, snapshot.fadeDurationSec)
            let safeProgress = CrossfadeMath.clampedProgress(snapshot.crossfadeProgress)
            crossfadeProgress = safeProgress
            applyCrossfadeGains(progress: safeProgress)
        } else {
            inactiveDeck.stopAndClearSchedule()
            inactiveDeck.clearFile()
            inactiveDeck.mixer.outputVolume = 0
            queuedTrack = nil
            fadeTargetSlot = nil
            crossfadeProgress = 0
        }

        if snapshot.state == .paused {
            state = .paused
            stateBeforePause = snapshot.stateBeforePause
            pausedCrossfadeProgress = snapshot.pausedCrossfadeProgress
            publishPosition()
            return
        }

        try startEngineIfNeeded()
        scheduleIfNeeded(activeDeck)
        activeDeck.node.play()

        if snapshot.state == .crossfading, let targetSlot = fadeTargetSlot {
            let targetDeck = deck(for: targetSlot)
            scheduleIfNeeded(targetDeck)
            targetDeck.node.play()
            state = .crossfading
            startFadeTimer(from: snapshot.crossfadeProgress)
        } else {
            state = .playing
        }
        startPositionTimer()
    }

    private func scheduleIfNeeded(_ deck: Deck) {
        deckScheduler.scheduleIfNeeded(deck)
    }

    private func startFadeTimer(from progress: Double) {
        crossfade.start(from: progress) { [weak self] in self?.advanceCrossfade() }
    }

    private func advanceCrossfade() {
        guard
            state == .crossfading,
            let progress = crossfade.progress()
        else {
            return
        }
        applyCrossfadeGains(progress: progress)

        if progress >= 1 {
            finishCrossfade()
        }
    }

    private func applyCrossfadeGains(progress: Double) {
        let safeProgress = CrossfadeMath.clampedProgress(progress)
        let gains = CrossfadeMath.equalPowerGains(progress: safeProgress)
        configure(deck: activeDeck, settings: activeDeck.targetDSPSettings, filterProgress: safeProgress, immediate: false)
        configure(deck: inactiveDeck, settings: inactiveDeck.targetDSPSettings, filterProgress: safeProgress, immediate: false)
        activeDeck.mixer.outputVolume = Float(gains.outgoing)
        inactiveDeck.mixer.outputVolume = Float(gains.incoming)
        crossfadeProgress = safeProgress
    }

    private func finishCrossfade() {
        crossfade.stopTimer()

        guard let fadeTargetSlot else {
            return
        }

        let oldDeck = deck(for: fadeTargetSlot.other)
        let newDeck = deck(for: fadeTargetSlot)
        oldDeck.stopAndClearSchedule()
        oldDeck.clearFile()
        oldDeck.mixer.outputVolume = 0
        newDeck.mixer.outputVolume = 1
        oldDeck.resetDSP()

        activeSlot = fadeTargetSlot
        session.apply(.transitionCompleted)
        self.fadeTargetSlot = nil
        silenceMeter(for: fadeTargetSlot.other)
        publishPosition()

        let completion = crossfade.takeCompletion()
        completion?()
    }

    private func cancelFadeKeepingCurrentDeck() {
        guard state == .crossfading else {
            return
        }

        crossfade.stopTimer()
        fadeCompletion = nil
        fadeTargetSlot = nil
        queuedTrack = nil
        activeTransitionPlan = nil
        nextDeckElapsedSec = 0
        crossfadeProgress = 0
        activeDeck.mixer.outputVolume = 1
        inactiveDeck.stopAndClearSchedule()
        inactiveDeck.clearFile()
        inactiveDeck.mixer.outputVolume = 0
        inactiveDeck.resetDSP()
        configureMasterDSP(.neutral)
        state = .playing
        silenceMeter(for: activeSlot.other)
        publishPosition()
    }

    private func startPositionTimer() {
        positionPublisher.start { [weak self] in self?.publishPosition() }
    }

    private func stopPositionTimer() {
        positionPublisher.stop()
    }

    private func publishPosition() {
        publishLatestMeters()
        let position = PlaybackPositionMath.clampedElapsed(
            activeDeck.positionSec(),
            durationSec: currentTrack?.durationSec
        )
        activeDeck.lastKnownPositionSec = position
        let remaining = PlaybackPositionMath.remaining(
            elapsedSec: position,
            durationSec: currentTrack?.durationSec
        )

        if let fadeTargetSlot, let queuedTrack {
            let nextDeck = deck(for: fadeTargetSlot)
            let nextPosition = PlaybackPositionMath.clampedElapsed(
                nextDeck.positionSec(),
                durationSec: queuedTrack.durationSec
            )
            nextDeck.lastKnownPositionSec = nextPosition
            session.apply(.positionUpdated(
                current: position,
                incoming: nextPosition,
                remaining: remaining,
                transitionProgress: crossfadeProgress
            ))
        } else {
            session.apply(.positionUpdated(
                current: position,
                incoming: 0,
                remaining: remaining,
                transitionProgress: crossfadeProgress
            ))
        }
    }

    private func installAudioMeterTaps() {
        meterPublisher.install(on: graph)
    }

    private func publishLatestMeters() {
        meterPublisher.publishLatest(
            session: &session,
            activeSlot: activeSlot,
            shouldPublish: isPlaybackActive || state == .paused
        )
    }

    private func silenceMeters() {
        meterPublisher.silence(session: &session, activeSlot: activeSlot)
    }

    private func silenceMeter(for slot: DeckSlot) {
        meterPublisher.silence(slot: slot, session: &session, activeSlot: activeSlot)
    }

    private func configure(
        deck: Deck,
        settings target: PlaybackDeckDSPSettings,
        filterProgress: Double,
        immediate: Bool
    ) {
        dspApplicator.configure(
            deck: deck,
            settings: target,
            filterProgress: filterProgress,
            immediate: immediate
        )
    }

    private func configureMasterDSP(_ settings: PlaybackMasterDSPSettings) {
        dspApplicator.configureMaster(settings)
    }

}
