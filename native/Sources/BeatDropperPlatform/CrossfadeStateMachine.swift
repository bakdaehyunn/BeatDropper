import BeatDropperDomain
import BeatDropperDSP
import Foundation

/// Owns crossfade timing and pause/resume bookkeeping. Audio gain/DSP mutation
/// remains an explicit callback into the engine façade on the main actor.
@MainActor
final class CrossfadeStateMachine {
    private let now: () -> Date
    private var timer: Timer?
    private var startedAt: Date?

    var durationSec: TimeInterval = 0
    var targetSlot: DeckSlot?
    var completion: (() -> Void)?
    var stateBeforePause: PlaybackSessionMode = .idle
    var pausedProgress: Double?

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func begin(targetSlot: DeckSlot, durationSec: TimeInterval, completion: @escaping () -> Void) {
        self.durationSec = max(0.1, durationSec)
        self.targetSlot = targetSlot
        self.completion = completion
        pausedProgress = nil
    }

    func start(from progress: Double, tick: @escaping @MainActor () -> Void) {
        stopTimer()
        let safeProgress = CrossfadeMath.clampedProgress(progress)
        startedAt = now().addingTimeInterval(-safeProgress * max(0.1, durationSec))
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func progress() -> Double? {
        guard let startedAt, durationSec > 0 else { return nil }
        return CrossfadeMath.clampedProgress(now().timeIntervalSince(startedAt) / durationSec)
    }

    func pause(from state: PlaybackSessionMode, progress: Double) {
        stateBeforePause = state
        pausedProgress = state == .crossfading ? CrossfadeMath.clampedProgress(progress) : nil
        stopTimer()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        stopTimer()
        startedAt = nil
        durationSec = 0
        targetSlot = nil
        completion = nil
        pausedProgress = nil
        stateBeforePause = .idle
    }

    func takeCompletion() -> (() -> Void)? {
        let action = completion
        completion = nil
        return action
    }
}
