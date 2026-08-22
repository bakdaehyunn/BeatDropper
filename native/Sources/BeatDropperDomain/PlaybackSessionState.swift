import Foundation

public enum PlaybackSessionMode: String, Codable, Hashable, Sendable {
    case idle = "Idle"
    case playing = "Playing"
    case paused = "Paused"
    case crossfading = "Crossfading"
}

public enum PlaybackRecoveryStatus: Equatable, Sendable {
    case ready
    case recovering
    case recovered(String)
    case failed(String)

    public var notice: String? {
        switch self {
        case .ready, .recovering: nil
        case .recovered(let message), .failed(let message): message
        }
    }
}

public struct PlaybackSessionState: Equatable, Sendable {
    public var mode: PlaybackSessionMode
    public var currentTrack: Track?
    public var queuedTrack: Track?
    public var currentElapsedSec: Double
    public var queuedElapsedSec: Double
    public var currentRemainingSec: Double
    public var activeTransitionPlan: MixPlan?
    public var transitionProgress: Double
    public var outputMeter: AudioLevelMeter
    public var currentDeckMeter: AudioLevelMeter
    public var queuedDeckMeter: AudioLevelMeter
    public var recoveryStatus: PlaybackRecoveryStatus

    public var recoveryNotice: String? {
        get { recoveryStatus.notice }
        set { recoveryStatus = newValue.map(PlaybackRecoveryStatus.recovered) ?? .ready }
    }

    public init(
        mode: PlaybackSessionMode = .idle,
        currentTrack: Track? = nil,
        queuedTrack: Track? = nil,
        currentElapsedSec: Double = 0,
        queuedElapsedSec: Double = 0,
        currentRemainingSec: Double = 0,
        activeTransitionPlan: MixPlan? = nil,
        transitionProgress: Double = 0,
        outputMeter: AudioLevelMeter = .silence,
        currentDeckMeter: AudioLevelMeter = .silence,
        queuedDeckMeter: AudioLevelMeter = .silence,
        recoveryNotice: String? = nil
    ) {
        self.mode = mode
        self.currentTrack = currentTrack
        self.queuedTrack = queuedTrack
        self.currentElapsedSec = Self.clampedElapsed(
            currentElapsedSec,
            durationSec: currentTrack?.durationSec
        )
        self.queuedElapsedSec = Self.clampedElapsed(
            queuedElapsedSec,
            durationSec: queuedTrack?.durationSec
        )
        self.currentRemainingSec = max(0, currentRemainingSec.isFinite ? currentRemainingSec : 0)
        self.activeTransitionPlan = activeTransitionPlan
        self.transitionProgress = min(1, max(0, transitionProgress.isFinite ? transitionProgress : 0))
        self.outputMeter = outputMeter
        self.currentDeckMeter = currentDeckMeter
        self.queuedDeckMeter = queuedDeckMeter
        self.recoveryStatus = recoveryNotice.map(PlaybackRecoveryStatus.recovered) ?? .ready
    }

    public var isPlaybackActive: Bool {
        mode == .playing || mode == .crossfading
    }

    public var isTransitionActive: Bool {
        mode == .crossfading && queuedTrack != nil
    }

    private static func clampedElapsed(_ elapsedSec: Double, durationSec: Double?) -> Double {
        let lowerBounded = max(0, elapsedSec.isFinite ? elapsedSec : 0)
        guard let durationSec, durationSec.isFinite, durationSec > 0 else {
            return lowerBounded
        }
        return min(durationSec, lowerBounded)
    }
}

public enum PlaybackSessionEvent: Sendable {
    case prepared(currentTrack: Track?, queuedTrack: Track?)
    case primaryLoaded(Track)
    case started
    case transitionStarted(queuedTrack: Track, plan: MixPlan?)
    case positionUpdated(current: Double, incoming: Double, remaining: Double, transitionProgress: Double)
    case paused
    case resumed(transitionActive: Bool)
    case transitionCompleted
    case stopped
    case recoveryStarted
    case recoverySucceeded(String)
    case recoveryFailed(String)
}

public extension PlaybackSessionState {
    mutating func apply(_ event: PlaybackSessionEvent) {
        switch event {
        case .prepared(let current, let queued):
            if mode == .idle {
                currentTrack = current
                currentElapsedSec = 0
                currentRemainingSec = max(0, current?.durationSec ?? 0)
            }
            if mode != .crossfading {
                queuedTrack = queued
                queuedElapsedSec = 0
                activeTransitionPlan = nil
                transitionProgress = 0
            }
        case .primaryLoaded(let track):
            currentTrack = track
            queuedTrack = nil
            currentElapsedSec = 0
            queuedElapsedSec = 0
            currentRemainingSec = max(0, track.durationSec)
            activeTransitionPlan = nil
            transitionProgress = 0
        case .started:
            mode = .playing
            recoveryStatus = .ready
        case .transitionStarted(let queued, let plan):
            queuedTrack = queued
            queuedElapsedSec = max(0, plan?.nextTrackStartOffsetSec ?? 0)
            activeTransitionPlan = plan
            transitionProgress = 0
            mode = .crossfading
            recoveryStatus = .ready
        case .positionUpdated(let current, let incoming, let remaining, let progress):
            currentElapsedSec = Self.clampedElapsed(current, durationSec: currentTrack?.durationSec)
            queuedElapsedSec = Self.clampedElapsed(incoming, durationSec: queuedTrack?.durationSec)
            currentRemainingSec = max(0, remaining.isFinite ? remaining : 0)
            transitionProgress = min(1, max(0, progress.isFinite ? progress : 0))
        case .paused:
            if isPlaybackActive { mode = .paused }
        case .resumed(let transitionActive):
            mode = transitionActive && queuedTrack != nil ? .crossfading : .playing
        case .transitionCompleted:
            if let queuedTrack { currentTrack = queuedTrack }
            queuedTrack = nil
            currentElapsedSec = queuedElapsedSec
            queuedElapsedSec = 0
            activeTransitionPlan = nil
            transitionProgress = 0
            mode = currentTrack == nil ? .idle : .playing
        case .stopped:
            self = PlaybackSessionState()
        case .recoveryStarted:
            recoveryStatus = .recovering
        case .recoverySucceeded(let message):
            recoveryStatus = .recovered(message)
        case .recoveryFailed(let message):
            recoveryStatus = .failed(message)
        }
    }
}
