import AVFoundation
import Foundation

/// Owns configuration-change observation and re-entrancy suppression. The
/// engine façade supplies the actual snapshot/restore transaction.
@MainActor
final class AudioConfigurationRecoveryCoordinator {
    private var observer: NSObjectProtocol?
    private var isRecovering = false
    private var suppressUntil = Date.distantPast

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
        guard !isIdle, !isRecovering, Date() >= suppressUntil else { return false }
        isRecovering = true
        suppressUntil = Date().addingTimeInterval(5)
        return true
    }

    func finish() {
        isRecovering = false
    }
}
