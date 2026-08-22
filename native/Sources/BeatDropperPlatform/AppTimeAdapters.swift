import BeatDropperApplication
import Foundation

public struct SystemAppClock: AppClock {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public final class RunLoopAppScheduler: AppScheduling {
    public init() {}

    public func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any AppSchedule {
        RunLoopTimerSchedule(interval: interval, action: action)
    }
}

@MainActor
private final class RunLoopTimerSchedule: AppSchedule {
    private var timer: Timer?

    init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
