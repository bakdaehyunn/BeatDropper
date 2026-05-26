import AVFoundation
import BeatDropperCore
import Foundation

private let outputMeterNotificationName = Notification.Name("BeatDropperNativeOutputMeter")
private enum AudioMeterTarget {
    static let master = "master"
    static let deckA = "deck-a"
    static let deckB = "deck-b"
}

@MainActor
final class NativeAudioEngine: ObservableObject {
    enum PlaybackState: String {
        case idle = "Idle"
        case playing = "Playing"
        case paused = "Paused"
        case crossfading = "Crossfading"
    }

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTrack: Track?
    @Published private(set) var queuedTrack: Track?
    @Published private(set) var crossfadeProgress: Double = 0
    @Published private(set) var elapsedSec: Double = 0
    @Published private(set) var remainingSec: Double = 0
    @Published private(set) var outputMeter: AudioLevelMeter = .silence
    @Published private(set) var deckAMeter: AudioLevelMeter = .silence
    @Published private(set) var deckBMeter: AudioLevelMeter = .silence
    @Published private(set) var recoveryNotice: String?

    private let engine = AVAudioEngine()
    private let masterMeterTapBridge = AudioMeterTapBridge(target: AudioMeterTarget.master)
    private let deckAMeterTapBridge = AudioMeterTapBridge(target: AudioMeterTarget.deckA)
    private let deckBMeterTapBridge = AudioMeterTapBridge(target: AudioMeterTarget.deckB)
    private let deckA = Deck(slot: .a)
    private let deckB = Deck(slot: .b)
    private var activeSlot: DeckSlot = .a
    private var fadeTimer: Timer?
    private var fadeStartedAt: Date?
    private var fadeDurationSec: TimeInterval = 0
    private var fadeTargetSlot: DeckSlot?
    private var fadeCompletion: (() -> Void)?
    private var stateBeforePause: PlaybackState = .idle
    private var pausedCrossfadeProgress: Double?
    private var positionTimer: Timer?
    private var outputMeterObserver: NSObjectProtocol?
    private var engineConfigurationObserver: NSObjectProtocol?

    init() {
        engine.attach(deckA.node)
        engine.attach(deckB.node)
        engine.connect(deckA.node, to: engine.mainMixerNode, format: nil)
        engine.connect(deckB.node, to: engine.mainMixerNode, format: nil)
        deckA.node.volume = 1
        deckB.node.volume = 0
        observeOutputMeter()
        installAudioMeterTaps()
        observeEngineConfigurationChanges()
    }

    var isPlaybackActive: Bool {
        state == .playing || state == .crossfading
    }

    var currentDeckMeter: AudioLevelMeter {
        meter(for: activeSlot)
    }

    var nextDeckMeter: AudioLevelMeter {
        meter(for: activeSlot.other)
    }

    func setMasterGain(_ gain: Double) {
        let clamped = min(1, max(0, gain.isFinite ? gain : PlayerSettings.defaults.masterGain))
        engine.mainMixerNode.outputVolume = Float(clamped)
    }

    func loadPrimary(url: URL, track: Track) throws {
        stop()
        try prepare(deck: activeDeck, url: url, track: track, volume: 1)
        currentTrack = track
        queuedTrack = nil
        publishPosition()
    }

    func play(url: URL, track: Track) throws {
        if currentTrack?.id != track.id || activeDeck.file == nil {
            try loadPrimary(url: url, track: track)
        }
        try play()
    }

    func playPreview(url: URL, track: Track, startOffsetSec: TimeInterval) throws {
        stop()
        try prepare(deck: activeDeck, url: url, track: track, volume: 1, startOffsetSec: startOffsetSec)
        currentTrack = track
        queuedTrack = nil
        try play()
    }

    func play() throws {
        guard activeDeck.file != nil else {
            return
        }

        recoveryNotice = nil
        try startEngineIfNeeded()
        scheduleIfNeeded(activeDeck)
        activeDeck.node.play()
        activeDeck.node.volume = 1

        state = .playing
        startPositionTimer()
    }

    func resume() throws {
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
            state = .crossfading
            let startProgress = pausedCrossfadeProgress ?? crossfadeProgress
            startFadeTimer(from: startProgress)
            pausedCrossfadeProgress = nil
        } else {
            state = .playing
        }
        startPositionTimer()
    }

    func crossfadeTo(
        url: URL,
        track: Track,
        durationSec: TimeInterval,
        startOffsetSec: TimeInterval = 0,
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
        try startEngineIfNeeded()
        scheduleIfNeeded(activeDeck)
        scheduleIfNeeded(targetDeck)

        if !activeDeck.node.isPlaying {
            activeDeck.node.play()
        }
        targetDeck.node.play()

        recoveryNotice = nil
        queuedTrack = track
        fadeDurationSec = max(0.1, durationSec)
        fadeStartedAt = Date()
        fadeTargetSlot = targetDeck.slot
        fadeCompletion = completion
        crossfadeProgress = 0
        state = .crossfading
        applyCrossfadeGains(progress: 0)
        startFadeTimer(from: 0)
        startPositionTimer()
    }

    func pause() {
        guard isPlaybackActive else {
            return
        }

        stateBeforePause = state
        pausedCrossfadeProgress = state == .crossfading ? crossfadeProgress : nil
        fadeTimer?.invalidate()
        fadeTimer = nil
        deckA.node.pause()
        deckB.node.pause()
        state = .paused
        stopPositionTimer()
        publishPosition()
        silenceMeters()
    }

    func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        stopPositionTimer()
        fadeCompletion = nil
        fadeTargetSlot = nil
        pausedCrossfadeProgress = nil
        deckA.stopAndClearSchedule()
        deckB.stopAndClearSchedule()
        activeDeck.node.volume = 1
        inactiveDeck.node.volume = 0
        queuedTrack = nil
        crossfadeProgress = 0
        elapsedSec = 0
        remainingSec = 0
        silenceMeters()
        recoveryNotice = nil
        state = .idle
    }

    private var activeDeck: Deck {
        deck(for: activeSlot)
    }

    private var inactiveDeck: Deck {
        deck(for: activeSlot.other)
    }

    private func deck(for slot: DeckSlot) -> Deck {
        switch slot {
        case .a:
            return deckA
        case .b:
            return deckB
        }
    }

    private func meter(for slot: DeckSlot) -> AudioLevelMeter {
        switch slot {
        case .a:
            return deckAMeter
        case .b:
            return deckBMeter
        }
    }

    private func prepare(deck: Deck, url: URL, track: Track, volume: Float, startOffsetSec: TimeInterval = 0) throws {
        deck.stopAndClearSchedule()
        deck.file = try AVAudioFile(forReading: url)
        deck.url = url
        deck.track = track
        let safeStartOffset = PlaybackPositionMath.clampedElapsed(startOffsetSec, durationSec: track.durationSec)
        deck.startFrame = frameOffset(for: deck.file, startOffsetSec: safeStartOffset)
        deck.lastKnownPositionSec = safeStartOffset
        deck.node.volume = volume
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func observeEngineConfigurationChanges() {
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recoverAfterEngineConfigurationChange()
            }
        }
    }

    private func observeOutputMeter() {
        outputMeterObserver = NotificationCenter.default.addObserver(
            forName: outputMeterNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let target = notification.userInfo?["target"] as? String,
                  let meter = notification.userInfo?["meter"] as? AudioLevelMeter
            else {
                return
            }
            Task { @MainActor in
                self?.publishMeter(meter, target: target)
            }
        }
    }

    private func recoverAfterEngineConfigurationChange() {
        guard state != .idle else {
            return
        }

        let snapshot = PlaybackRecoverySnapshot(
            state: state,
            activeSlot: activeSlot,
            active: DeckRecoverySnapshot(deck: activeDeck),
            inactive: DeckRecoverySnapshot(deck: inactiveDeck),
            crossfadeProgress: crossfadeProgress,
            fadeDurationSec: fadeDurationSec,
            fadeTargetSlot: fadeTargetSlot,
            stateBeforePause: stateBeforePause,
            pausedCrossfadeProgress: pausedCrossfadeProgress
        )

        fadeTimer?.invalidate()
        fadeTimer = nil
        stopPositionTimer()
        deckA.stopAndClearSchedule()
        deckB.stopAndClearSchedule()
        engine.stop()
        engine.reset()

        do {
            try restoreAfterConfigurationChange(snapshot)
            recoveryNotice = "Audio engine recovered after device change"
        } catch {
            stop()
            recoveryNotice = "Audio recovery failed: \(error.localizedDescription)"
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
        currentTrack = activeTrack

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
            queuedTrack = targetTrack
            fadeTargetSlot = targetSlot
            fadeDurationSec = max(0.1, snapshot.fadeDurationSec)
            let safeProgress = CrossfadeMath.clampedProgress(snapshot.crossfadeProgress)
            crossfadeProgress = safeProgress
            applyCrossfadeGains(progress: safeProgress)
        } else {
            inactiveDeck.stopAndClearSchedule()
            inactiveDeck.clearFile()
            inactiveDeck.node.volume = 0
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
        guard let file = deck.file, !deck.scheduled else {
            return
        }

        if deck.startFrame > 0 {
            let remainingFrames = AVAudioFrameCount(max(0, file.length - deck.startFrame))
            if remainingFrames > 0 {
                deck.node.scheduleSegment(
                    file,
                    startingFrame: deck.startFrame,
                    frameCount: remainingFrames,
                    at: nil
                )
            } else {
                deck.node.scheduleFile(file, at: nil)
            }
        } else {
            deck.node.scheduleFile(file, at: nil)
        }
        deck.scheduled = true
    }

    private func frameOffset(for file: AVAudioFile?, startOffsetSec: TimeInterval) -> AVAudioFramePosition {
        guard let file, startOffsetSec.isFinite, startOffsetSec > 0 else {
            return 0
        }
        let frame = AVAudioFramePosition((startOffsetSec * file.processingFormat.sampleRate).rounded())
        return min(max(0, frame), max(0, file.length - 1))
    }

    private func startFadeTimer(from progress: Double) {
        fadeTimer?.invalidate()
        let safeProgress = CrossfadeMath.clampedProgress(progress)
        fadeStartedAt = Date().addingTimeInterval(-safeProgress * max(0.1, fadeDurationSec))

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceCrossfade()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func advanceCrossfade() {
        guard
            state == .crossfading,
            let fadeStartedAt,
            fadeDurationSec > 0
        else {
            return
        }

        let progress = CrossfadeMath.clampedProgress(Date().timeIntervalSince(fadeStartedAt) / fadeDurationSec)
        applyCrossfadeGains(progress: progress)

        if progress >= 1 {
            finishCrossfade()
        }
    }

    private func applyCrossfadeGains(progress: Double) {
        let safeProgress = CrossfadeMath.clampedProgress(progress)
        let gains = CrossfadeMath.equalPowerGains(progress: safeProgress)
        activeDeck.node.volume = Float(gains.outgoing)
        inactiveDeck.node.volume = Float(gains.incoming)
        crossfadeProgress = safeProgress
    }

    private func finishCrossfade() {
        fadeTimer?.invalidate()
        fadeTimer = nil

        guard let fadeTargetSlot else {
            return
        }

        let oldDeck = deck(for: fadeTargetSlot.other)
        let newDeck = deck(for: fadeTargetSlot)
        oldDeck.stopAndClearSchedule()
        oldDeck.clearFile()
        oldDeck.node.volume = 0
        newDeck.node.volume = 1

        activeSlot = fadeTargetSlot
        currentTrack = newDeck.track
        queuedTrack = nil
        crossfadeProgress = 0
        state = .playing
        self.fadeTargetSlot = nil
        silenceMeter(for: fadeTargetSlot.other)
        publishPosition()

        let completion = fadeCompletion
        fadeCompletion = nil
        completion?()
    }

    private func cancelFadeKeepingCurrentDeck() {
        guard state == .crossfading else {
            return
        }

        fadeTimer?.invalidate()
        fadeTimer = nil
        fadeCompletion = nil
        fadeTargetSlot = nil
        queuedTrack = nil
        crossfadeProgress = 0
        activeDeck.node.volume = 1
        inactiveDeck.stopAndClearSchedule()
        inactiveDeck.clearFile()
        inactiveDeck.node.volume = 0
        state = .playing
        silenceMeter(for: activeSlot.other)
        publishPosition()
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishPosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
        publishPosition()
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func publishPosition() {
        let position = PlaybackPositionMath.clampedElapsed(
            activeDeck.positionSec(),
            durationSec: currentTrack?.durationSec
        )
        activeDeck.lastKnownPositionSec = position
        elapsedSec = position
        if let currentTrack {
            remainingSec = PlaybackPositionMath.remaining(
                elapsedSec: position,
                durationSec: currentTrack.durationSec
            )
        } else {
            remainingSec = 0
        }
    }

    private func installAudioMeterTaps() {
        deckA.node.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: nil,
            block: deckAMeterTapBridge.makeTap()
        )
        deckB.node.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: nil,
            block: deckBMeterTapBridge.makeTap()
        )
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: nil,
            block: masterMeterTapBridge.makeTap()
        )
    }

    private func publishMeter(_ meter: AudioLevelMeter, target: String) {
        guard isPlaybackActive || state == .paused else {
            silenceMeters()
            return
        }

        switch target {
        case AudioMeterTarget.master:
            outputMeter = LevelMeterMath.smooth(previous: outputMeter, current: meter)
        case AudioMeterTarget.deckA:
            deckAMeter = LevelMeterMath.smooth(previous: deckAMeter, current: meter)
        case AudioMeterTarget.deckB:
            deckBMeter = LevelMeterMath.smooth(previous: deckBMeter, current: meter)
        default:
            break
        }
    }

    private func silenceMeters() {
        outputMeter = .silence
        deckAMeter = .silence
        deckBMeter = .silence
    }

    private func silenceMeter(for slot: DeckSlot) {
        switch slot {
        case .a:
            deckAMeter = .silence
        case .b:
            deckBMeter = .silence
        }
    }

    private nonisolated static func outputMeter(for buffer: AVAudioPCMBuffer) -> AudioLevelMeter {
        guard let floatChannelData = buffer.floatChannelData else {
            return .silence
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else {
            return .silence
        }

        var samples: [Float] = []
        samples.reserveCapacity(channelCount * frameLength)
        for channelIndex in 0..<channelCount {
            let channel = floatChannelData[channelIndex]
            for frameIndex in 0..<frameLength {
                samples.append(channel[frameIndex])
            }
        }

        return LevelMeterMath.measure(samples: samples)
    }

    private final class AudioMeterTapBridge {
        private let target: String

        init(target: String) {
            self.target = target
        }

        func makeTap() -> AVAudioNodeTapBlock {
            { [target] buffer, _ in
                let meter = NativeAudioEngine.outputMeter(for: buffer)
                NotificationCenter.default.post(
                    name: outputMeterNotificationName,
                    object: nil,
                    userInfo: [
                        "target": target,
                        "meter": meter
                    ]
                )
            }
        }
    }
}

private struct PlaybackRecoverySnapshot {
    var state: NativeAudioEngine.PlaybackState
    var activeSlot: DeckSlot
    var active: DeckRecoverySnapshot
    var inactive: DeckRecoverySnapshot
    var crossfadeProgress: Double
    var fadeDurationSec: TimeInterval
    var fadeTargetSlot: DeckSlot?
    var stateBeforePause: NativeAudioEngine.PlaybackState
    var pausedCrossfadeProgress: Double?
}

private struct DeckRecoverySnapshot {
    var url: URL?
    var track: Track?
    var positionSec: TimeInterval
    var volume: Float

    init(deck: Deck) {
        self.url = deck.url
        self.track = deck.track
        self.positionSec = deck.positionSec()
        self.volume = deck.node.volume
    }
}

private enum DeckSlot {
    case a
    case b

    var other: DeckSlot {
        switch self {
        case .a:
            return .b
        case .b:
            return .a
        }
    }
}

private final class Deck {
    let slot: DeckSlot
    let node = AVAudioPlayerNode()
    var file: AVAudioFile?
    var url: URL?
    var track: Track?
    var startFrame: AVAudioFramePosition = 0
    var lastKnownPositionSec: Double = 0
    var scheduled = false

    init(slot: DeckSlot) {
        self.slot = slot
    }

    func stopAndClearSchedule() {
        node.stop()
        scheduled = false
    }

    func clearFile() {
        file = nil
        url = nil
        track = nil
        startFrame = 0
        lastKnownPositionSec = 0
    }

    func positionSec() -> Double {
        guard let file else {
            return 0
        }

        let baseOffset = Double(startFrame) / file.processingFormat.sampleRate
        guard
            node.isPlaying,
            let nodeTime = node.lastRenderTime,
            let playerTime = node.playerTime(forNodeTime: nodeTime)
        else {
            return lastKnownPositionSec
        }

        lastKnownPositionSec = baseOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
        return lastKnownPositionSec
    }
}
