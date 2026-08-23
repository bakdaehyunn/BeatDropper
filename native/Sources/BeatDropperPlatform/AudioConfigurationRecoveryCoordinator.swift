import AVFoundation
import Foundation

/// Owns configuration-change observation and re-entrancy suppression. The
/// engine façade supplies the actual snapshot/restore transaction.
@MainActor
final class AudioConfigurationRecoveryCoordinator {
    private let now: () -> Date
    private var observer: NSObjectProtocol?
    private var isRecovering = false
    private var suppressUntil = Date.distantPast

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    func observe(engine: AVAudioEngine, recover: @escaping @MainActor () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { _ in
            Task { @MainActor in recover() }
        }
    }

    func beginIfAllowed(isIdle: Bool) -> Bool {
        guard !isIdle, !isRecovering, now() >= suppressUntil else { return false }
        isRecovering = true
        suppressUntil = now().addingTimeInterval(5)
        return true
    }

    func finish() {
        isRecovering = false
    }
}
