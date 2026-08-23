import AVFoundation
import BeatDropperDomain
import BeatDropperDSP
import Foundation
import Testing
@testable import BeatDropperPlatform

@MainActor
struct PlatformPlaybackComponentTests {
    @Test
    func crossfadeProgressUsesInjectedClockAndClamps() {
        var now = Date(timeIntervalSince1970: 1_000)
        let stateMachine = CrossfadeStateMachine(now: { now })

        stateMachine.begin(targetSlot: .b, durationSec: 8) {}
        stateMachine.start(from: 0.25) {}
        #expect(abs((stateMachine.progress() ?? -1) - 0.25) < 0.000_001)

        now = now.addingTimeInterval(2)
        #expect(abs((stateMachine.progress() ?? -1) - 0.5) < 0.000_001)

        now = now.addingTimeInterval(20)
        #expect(stateMachine.progress() == 1)
        stateMachine.reset()
        #expect(stateMachine.progress() == nil)
    }

    @Test
    func crossfadePauseAndCompletionBookkeepingIsOneShot() {
        let stateMachine = CrossfadeStateMachine()
        var completions = 0
        stateMachine.begin(targetSlot: .b, durationSec: 0) { completions += 1 }
        #expect(stateMachine.durationSec == 0.1)
        #expect(stateMachine.targetSlot == .b)

        stateMachine.pause(from: .crossfading, progress: 1.5)
        #expect(stateMachine.stateBeforePause == .crossfading)
        #expect(stateMachine.pausedProgress == 1)

        stateMachine.takeCompletion()?()
        stateMachine.takeCompletion()?()
        #expect(completions == 1)

        stateMachine.pause(from: .playing, progress: 0.4)
        #expect(stateMachine.pausedProgress == nil)
    }

    @Test
    func configurationRecoverySuppressesIdleReentrantAndRapidRetries() {
        var now = Date(timeIntervalSince1970: 2_000)
        let recovery = AudioConfigurationRecoveryCoordinator(now: { now })

        #expect(!recovery.beginIfAllowed(isIdle: true))
        #expect(recovery.beginIfAllowed(isIdle: false))
        #expect(!recovery.beginIfAllowed(isIdle: false))

        recovery.finish()
        #expect(!recovery.beginIfAllowed(isIdle: false))
        now = now.addingTimeInterval(5)
        #expect(recovery.beginIfAllowed(isIdle: false))
    }

    @Test
    func positionPublisherPublishesImmediatelyAndCanRestart() {
        let publisher = PlaybackPositionPublisher()
        var publicationCount = 0

        publisher.start { publicationCount += 1 }
        #expect(publicationCount == 1)
        publisher.start { publicationCount += 1 }
        #expect(publicationCount == 2)
        publisher.stop()
    }

    @Test
    func deckSchedulerPreparesOffsetAndSchedulesOnlyOnce() throws {
        let fixtureURL = try makeAudioFixture(durationSec: 1)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let graph = NativeAudioGraph()
        let deck = graph.deckA
        let track = Track(id: "fixture", title: "Fixture", durationSec: 1, format: .wav, bpm: 120)
        let scheduler = DeckScheduler()

        try scheduler.prepare(deck: deck, url: fixtureURL, track: track, volume: 0.4, startOffsetSec: 0.25)
        #expect(deck.track?.id == track.id)
        #expect(deck.url == fixtureURL)
        #expect(abs(deck.lastKnownPositionSec - 0.25) < 0.000_001)
        #expect(deck.startFrame > 0)
        #expect(abs(deck.mixer.outputVolume - 0.4) < 0.000_001)

        scheduler.scheduleIfNeeded(deck)
        #expect(deck.scheduled)
        let startFrame = deck.startFrame
        scheduler.scheduleIfNeeded(deck)
        #expect(deck.startFrame == startFrame)
    }

    @Test
    func deckClearAndDSPResetRestoreNeutralState() {
        let deck = Deck(slot: .b)
        deck.url = URL(fileURLWithPath: "/tmp/track.wav")
        deck.track = Track(id: "track", title: "Track", durationSec: 10, format: .wav)
        deck.startFrame = 42
        deck.lastKnownPositionSec = 3
        deck.appliedDSPSettings.gainDb = 4
        deck.targetDSPSettings.lowEQDb = -6
        deck.timePitch.rate = 1.1

        deck.clearFile()
        deck.resetDSP()

        #expect(deck.url == nil)
        #expect(deck.track == nil)
        #expect(deck.startFrame == 0)
        #expect(deck.lastKnownPositionSec == 0)
        #expect(deck.appliedDSPSettings == .neutral)
        #expect(deck.targetDSPSettings == .neutral)
        #expect(deck.timePitch.rate == 1)
        #expect(deck.filterBand.bypass)
    }

    @Test
    func dspApplicatorAppliesDeckRampFilterAndMasterProtection() {
        let graph = NativeAudioGraph()
        let applicator = PlaybackDSPApplicator(graph: graph)
        let target = PlaybackDeckDSPSettings(
            gainDb: -4,
            lowEQDb: -6,
            midEQDb: 2,
            highEQDb: 1,
            filterMode: .highPass,
            filterStartHz: 20,
            filterEndHz: 2_000,
            playbackRate: 1.05
        )

        applicator.configure(deck: graph.deckA, settings: target, filterProgress: 0.5, immediate: true)
        #expect(graph.deckA.appliedDSPSettings == target)
        #expect(graph.deckA.eq.globalGain == -4)
        #expect(graph.deckA.lowBand.gain == -6)
        #expect(!graph.deckA.filterBand.bypass)
        #expect(graph.deckA.filterBand.filterType == .highPass)
        #expect(abs(graph.deckA.timePitch.rate - 1.05) < 0.000_001)

        let master = PlaybackMasterDSPSettings(softLimitEnabled: true, ceilingDb: -2)
        applicator.configureMaster(master)
        #expect(applicator.masterSettings == master)
        #expect(!graph.peakLimiter.auAudioUnit.shouldBypassEffect)
        #expect(graph.masterOutputMixer.outputVolume < 1)

        applicator.configureMaster(.neutral)
        #expect(graph.peakLimiter.auAudioUnit.shouldBypassEffect)
        #expect(graph.masterOutputMixer.outputVolume == 1)
    }

    @Test
    func meterPublisherSilencesAllSessionMetersAndMapsActiveDeck() {
        let publisher = AudioMeterPublisher()
        var session = PlaybackSessionState(
            outputMeter: AudioLevelMeter(rms: 0.4, peak: 0.7, rmsDb: -12, peakDb: -3, clipped: false),
            currentDeckMeter: AudioLevelMeter(rms: 0.3, peak: 0.6, rmsDb: -15, peakDb: -4, clipped: false),
            queuedDeckMeter: AudioLevelMeter(rms: 0.2, peak: 0.5, rmsDb: -18, peakDb: -6, clipped: false)
        )

        publisher.silence(session: &session, activeSlot: .b)

        #expect(session.outputMeter == .silence)
        #expect(session.currentDeckMeter == .silence)
        #expect(session.queuedDeckMeter == .silence)
        publisher.publishLatest(session: &session, activeSlot: .a, shouldPublish: false)
        #expect(session.outputMeter == .silence)
    }

    @Test
    func audioMeterTapBridgeMeasuresBuffersThroughRealtimeSafeBoundary() throws {
        let bridge = AudioMeterTapBridge()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let samples = try #require(buffer.floatChannelData?[0])
        samples[0] = 0
        samples[1] = 0.5
        samples[2] = -1
        samples[3] = 0.25

        bridge.makeTap()(buffer, AVAudioTime(sampleTime: 0, atRate: 44_100))
        let meter = bridge.latest

        #expect(meter.peak == 1)
        #expect(meter.rms > 0)
        #expect(meter.clipped)
        #expect(meter.peakDb == 0)
    }

    @Test
    func nativeAudioEnginePublishesPreparedStoppedAndRecoveryStateWithoutStartingHardware() {
        let engine = NativeAudioEngine()
        let current = Track(id: "current", title: "Current", durationSec: 120, format: .wav)
        let queued = Track(id: "queued", title: "Queued", durationSec: 100, format: .wav)

        engine.prepareSession(currentTrack: current, queuedTrack: queued)
        #expect(engine.session.currentTrack?.id == current.id)
        #expect(engine.session.queuedTrack?.id == queued.id)
        #expect(engine.state == .idle)

        engine.crossfadeProgress = 2
        #expect(engine.crossfadeProgress == 1)
        engine.setMasterGain(.nan)
        engine.simulateConfigurationChangeRecoveryForAutomation()
        #expect(engine.session.recoveryStatus == .recovered("Audio engine recovered after device change"))

        engine.stop()
        #expect(engine.session == PlaybackSessionState())
    }

    private func makeAudioFixture(durationSec: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beatdropper-platform-test-\(UUID().uuidString).wav")
        let sampleRate: UInt32 = 44_100
        let channelCount: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let frameCount = UInt32(Double(sampleRate) * durationSec)
        let bytesPerFrame = UInt32(channelCount * bitsPerSample / 8)
        let audioByteCount = frameCount * bytesPerFrame
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(UInt32(36) + audioByteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channelCount, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * bytesPerFrame, to: &data)
        appendLittleEndian(UInt16(bytesPerFrame), to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(audioByteCount, to: &data)
        data.append(Data(count: Int(audioByteCount)))
        try data.write(to: url)
        return url
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
