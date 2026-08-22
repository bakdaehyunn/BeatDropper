import AVFoundation
import BeatDropperDomain
import BeatDropperDSP
import Darwin
import Foundation

/// macOS 14-compatible lock-free storage for values shared by an audio tap and
/// the main-actor publication timer. The value is transferred as IEEE-754 bits.
private final class RealtimeAtomicDouble: @unchecked Sendable {
    private var bits: Int64

    init(_ value: Double) {
        bits = Int64(bitPattern: value.bitPattern)
    }

    func load() -> Double {
        Double(bitPattern: UInt64(bitPattern: OSAtomicAdd64Barrier(0, &bits)))
    }

    func store(_ value: Double) {
        let next = Int64(bitPattern: value.bitPattern)
        var current = OSAtomicAdd64Barrier(0, &bits)
        while !OSAtomicCompareAndSwap64Barrier(current, next, &bits) {
            current = OSAtomicAdd64Barrier(0, &bits)
        }
    }
}

/// Publishes the latest measurement through atomics so the audio tap never
/// synchronously enters the main actor or allocates notification payloads.
final class AudioMeterTapBridge {
    private let peak = RealtimeAtomicDouble(AudioLevelMeter.silence.peak)
    private let rms = RealtimeAtomicDouble(AudioLevelMeter.silence.rms)

    var latest: AudioLevelMeter {
        let peakValue = peak.load()
        let rmsValue = rms.load()
        return AudioLevelMeter(
            rms: rmsValue,
            peak: peakValue,
            rmsDb: decibels(rmsValue),
            peakDb: decibels(peakValue),
            clipped: peakValue >= 1
        )
    }

    func makeTap() -> AVAudioNodeTapBlock {
        { [peak, rms] buffer, _ in
            let meter = Self.outputMeter(for: buffer)
            peak.store(meter.peak)
            rms.store(meter.rms)
        }
    }

    /// Measures buffers without building an intermediate sample array. This is
    /// called on the real-time render thread and performs no allocation or I/O.
    nonisolated private static func outputMeter(for buffer: AVAudioPCMBuffer) -> AudioLevelMeter {
        guard let channels = buffer.floatChannelData else { return .silence }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return .silence }

        var peak = 0.0
        var squareSum = 0.0
        var validCount = 0
        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for frameIndex in 0..<frameLength {
                let value = Double(channel[frameIndex])
                guard value.isFinite else { continue }
                peak = max(peak, abs(value))
                squareSum += value * value
                validCount += 1
            }
        }
        guard validCount > 0 else { return .silence }
        let rmsLinear = sqrt(squareSum / Double(validCount))
        let peakDb = decibels(peak)
        let rmsDb = decibels(rmsLinear)
        return AudioLevelMeter(
            rms: normalized(rmsDb),
            peak: normalized(peakDb),
            rmsDb: rmsDb,
            peakDb: peakDb,
            clipped: peak >= 0.98
        )
    }

    nonisolated private static func decibels(_ amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return LevelMeterMath.dbFloor }
        return min(LevelMeterMath.dbCeiling, max(LevelMeterMath.dbFloor, 20 * log10(amplitude)))
    }

    nonisolated private static func normalized(_ decibels: Double) -> Double {
        min(1, max(0, (decibels - LevelMeterMath.dbFloor) /
            (LevelMeterMath.dbCeiling - LevelMeterMath.dbFloor)))
    }

    private func decibels(_ amplitude: Double) -> Double {
        max(-60, 20 * log10(max(amplitude, 0.000_001)))
    }
}

/// Owns tap bridges and main-actor meter smoothing/publication. Render-thread
/// taps only update atomics; session mutation remains on the UI sampling timer.
@MainActor
final class AudioMeterPublisher {
    private let masterBridge = AudioMeterTapBridge()
    private let deckABridge = AudioMeterTapBridge()
    private let deckBBridge = AudioMeterTapBridge()
    private var deckAMeter: AudioLevelMeter = .silence
    private var deckBMeter: AudioLevelMeter = .silence

    func install(on graph: NativeAudioGraph) {
        graph.deckA.mixer.installTap(onBus: 0, bufferSize: 2_048, format: nil, block: deckABridge.makeTap())
        graph.deckB.mixer.installTap(onBus: 0, bufferSize: 2_048, format: nil, block: deckBBridge.makeTap())
        graph.engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: nil,
            block: masterBridge.makeTap()
        )
    }

    func publishLatest(
        session: inout PlaybackSessionState,
        activeSlot: DeckSlot,
        shouldPublish: Bool
    ) {
        guard shouldPublish else {
            silence(session: &session, activeSlot: activeSlot)
            return
        }
        session.outputMeter = LevelMeterMath.smooth(previous: session.outputMeter, current: masterBridge.latest)
        deckAMeter = LevelMeterMath.smooth(previous: deckAMeter, current: deckABridge.latest)
        deckBMeter = LevelMeterMath.smooth(previous: deckBMeter, current: deckBBridge.latest)
        syncSessionMeters(session: &session, activeSlot: activeSlot)
    }

    func silence(session: inout PlaybackSessionState, activeSlot: DeckSlot) {
        session.outputMeter = .silence
        deckAMeter = .silence
        deckBMeter = .silence
        syncSessionMeters(session: &session, activeSlot: activeSlot)
    }

    func silence(slot: DeckSlot, session: inout PlaybackSessionState, activeSlot: DeckSlot) {
        switch slot {
        case .a: deckAMeter = .silence
        case .b: deckBMeter = .silence
        }
        syncSessionMeters(session: &session, activeSlot: activeSlot)
    }

    private func syncSessionMeters(session: inout PlaybackSessionState, activeSlot: DeckSlot) {
        session.currentDeckMeter = meter(for: activeSlot)
        session.queuedDeckMeter = meter(for: activeSlot.other)
    }

    private func meter(for slot: DeckSlot) -> AudioLevelMeter {
        switch slot {
        case .a: deckAMeter
        case .b: deckBMeter
        }
    }
}
