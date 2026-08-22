import Foundation

/// Owns the UI-rate position publication timer. It never runs on the audio
/// render callback and delegates sampling back to the main-actor engine façade.
@MainActor
final class PlaybackPositionPublisher {
    private var timer: Timer?

    func start(publish: @escaping @MainActor () -> Void) {
        stop()
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in publish() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        publish()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
