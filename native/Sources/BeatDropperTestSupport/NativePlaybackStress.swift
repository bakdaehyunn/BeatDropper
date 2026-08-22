import AVFoundation
import BeatDropperDomain
import BeatDropperPlatform
import Foundation

public struct NativePlaybackStressResult: Sendable {
    public var transitionsCompleted: Int
    public var incomingPlayheadAdvanced: Bool
    public var crossfadePauseResumePassed: Bool
    public var deviceRecoveryPassed: Bool
}

@MainActor
public enum NativePlaybackStress {
    public static func run() async throws -> NativePlaybackStressResult {
        let engine = NativeAudioEngine()
        let fixture = try NativePlaybackStressFixture.create()
        defer {
            engine.stop()
            try? FileManager.default.removeItem(at: fixture.folderURL)
        }

        try engine.play(url: fixture.firstURL, track: fixture.firstTrack)
        try await waitUntil(timeoutSec: 4, failure: {
            NativePlaybackStressError.playDidNotAdvance(snapshot(engine.session, expectedTrackID: fixture.firstTrack.id))
        }) {
            engine.session.mode == .playing &&
                engine.session.currentTrack?.id == fixture.firstTrack.id &&
                engine.session.currentElapsedSec > 0
        }

        let firstPlan = plan(durationSec: 1.2, barCount: 4)
        try engine.crossfadeTo(
            url: fixture.secondURL,
            track: fixture.secondTrack,
            durationSec: 1.2,
            startOffsetSec: 0.05,
            plan: firstPlan
        )
        try await waitUntil(timeoutSec: 1, intervalMilliseconds: 25, failure: {
            NativePlaybackStressError.crossfadeDidNotComplete(snapshot(engine.session))
        }) {
            engine.session.mode == .crossfading &&
                engine.session.queuedTrack?.id == fixture.secondTrack.id &&
                engine.session.queuedElapsedSec > 0.12 &&
                engine.session.activeTransitionPlan?.transitionBarCount == 4
        }

        let pausedIncoming = engine.session.queuedElapsedSec
        let pausedProgress = engine.session.transitionProgress
        engine.pause()
        guard engine.session.mode == .paused else { throw NativePlaybackStressError.pauseFailed }
        try await sleep(milliseconds: 120)
        guard abs(engine.session.queuedElapsedSec - pausedIncoming) < 0.05 else {
            throw NativePlaybackStressError.pauseFailed
        }
        try engine.resume()
        try await waitUntil(timeoutSec: 1, intervalMilliseconds: 25, failure: {
            NativePlaybackStressError.resumeFailed(snapshot(engine.session))
        }) {
            engine.session.mode == .crossfading &&
                engine.session.transitionProgress > pausedProgress &&
                engine.session.queuedElapsedSec > pausedIncoming
        }

        engine.simulateConfigurationChangeRecoveryForAutomation()
        try await waitUntil(timeoutSec: 2, intervalMilliseconds: 25, failure: {
            NativePlaybackStressError.recoveryFailed(snapshot(engine.session))
        }) {
            engine.session.recoveryNotice != nil &&
                (engine.session.mode == .crossfading || engine.session.mode == .playing)
        }
        try await waitUntil(timeoutSec: 3, failure: {
            NativePlaybackStressError.crossfadeDidNotComplete(snapshot(engine.session))
        }) {
            engine.session.mode == .playing && engine.session.currentTrack?.id == fixture.secondTrack.id
        }

        try engine.crossfadeTo(
            url: fixture.firstURL,
            track: fixture.firstTrack,
            durationSec: 0.45,
            startOffsetSec: 0.1,
            plan: plan(durationSec: 0.45, barCount: 1)
        )
        try await waitUntil(timeoutSec: 3, intervalMilliseconds: 25, failure: {
            NativePlaybackStressError.crossfadeDidNotComplete(snapshot(engine.session))
        }) {
            engine.session.mode == .crossfading &&
                engine.session.queuedTrack?.id == fixture.firstTrack.id &&
                engine.session.queuedElapsedSec > 0.1
        }
        try await waitUntil(timeoutSec: 3, failure: {
            NativePlaybackStressError.crossfadeDidNotComplete(snapshot(engine.session))
        }) {
            engine.session.mode == .playing && engine.session.currentTrack?.id == fixture.firstTrack.id
        }

        engine.stop()
        guard engine.session.mode == .idle,
              engine.session.activeTransitionPlan == nil,
              engine.session.queuedElapsedSec == 0
        else {
            throw NativePlaybackStressError.stopFailed
        }
        return NativePlaybackStressResult(
            transitionsCompleted: 2,
            incomingPlayheadAdvanced: true,
            crossfadePauseResumePassed: true,
            deviceRecoveryPassed: true
        )
    }

    private static func plan(durationSec: Double, barCount: Int) -> MixPlan {
        MixPlan(
            transitionStartSec: 0,
            transitionEndSec: durationSec,
            nextTrackStartOffsetSec: 0.05,
            style: barCount == 1 ? .hardCut : .energySwap,
            confidence: 0.9,
            reasoningSummary: "native playback transition stress",
            tempoSync: MixTempoSyncPlan(enabled: barCount > 1, targetRate: barCount > 1 ? 120 / 124 : nil),
            phraseAlignment: .aligned,
            evidence: ["native playback stress"],
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

    private static func waitUntil(
        timeoutSec: TimeInterval,
        intervalMilliseconds: UInt64 = 100,
        failure: () -> Error,
        predicate: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if predicate() { return }
            try await sleep(milliseconds: intervalMilliseconds)
        }
        throw failure()
    }

    private static func sleep(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private static func snapshot(_ session: PlaybackSessionState, expectedTrackID: String? = nil) -> String {
        [
            "state=\(session.mode.rawValue)",
            "current=\(session.currentTrack?.id ?? "--")",
            "expected=\(expectedTrackID ?? "--")",
            "queued=\(session.queuedTrack?.id ?? "--")",
            "elapsed=\(String(format: "%.3f", session.currentElapsedSec))",
            "incoming=\(String(format: "%.3f", session.queuedElapsedSec))",
            "progress=\(String(format: "%.3f", session.transitionProgress))"
        ].joined(separator: "; ")
    }
}

private enum NativePlaybackStressError: LocalizedError {
    case playDidNotAdvance(String)
    case crossfadeDidNotComplete(String)
    case pauseFailed
    case resumeFailed(String)
    case recoveryFailed(String)
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .playDidNotAdvance(let detail): "playback did not advance: \(detail)"
        case .crossfadeDidNotComplete(let detail): "crossfade did not complete: \(detail)"
        case .pauseFailed: "pause did not preserve the transition"
        case .resumeFailed(let detail): "resume failed: \(detail)"
        case .recoveryFailed(let detail): "configuration recovery failed: \(detail)"
        case .stopFailed: "stop did not return to idle"
        }
    }
}

private struct NativePlaybackStressFixture {
    let folderURL: URL
    let firstURL: URL
    let secondURL: URL
    let firstTrack: Track
    let secondTrack: Track

    static func create() throws -> NativePlaybackStressFixture {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperNativePlaybackStress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = folder.appendingPathComponent("stress-a.wav")
        let second = folder.appendingPathComponent("stress-b.wav")
        try writeSineWave(url: first, frequency: 220, durationSec: 4)
        try writeSineWave(url: second, frequency: 330, durationSec: 4)
        return NativePlaybackStressFixture(
            folderURL: folder,
            firstURL: first,
            secondURL: second,
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
        else { throw NativePlaybackStressError.playDidNotAdvance("fixture allocation failed") }
        buffer.frameLength = buffer.frameCapacity
        for channelIndex in 0..<Int(format.channelCount) {
            guard let channel = buffer.floatChannelData?[channelIndex] else { continue }
            for frameIndex in 0..<Int(buffer.frameLength) {
                let phase = 2 * Double.pi * frequency * Double(frameIndex) / sampleRate
                channel[frameIndex] = 0.18 * Float(sin(phase))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
