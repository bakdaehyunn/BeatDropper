import AppKit
import BeatDropperTestSupport
import Foundation

@main
@MainActor
struct BeatDropperNativePlaybackStressApp {
    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do {
            let result = try await NativePlaybackStress.run()
            print([
                "BEATDROPPER_NATIVE_PLAYBACK_STRESS_READY",
                "state=Idle",
                "transitions=\(result.transitionsCompleted)",
                "incomingPlayhead=\(result.incomingPlayheadAdvanced ? "true" : "false")",
                "pauseResume=\(result.crossfadePauseResumePassed ? "true" : "false")",
                "recovery=\(result.deviceRecoveryPassed ? "true" : "false")"
            ].joined(separator: " "))
        } catch {
            FileHandle.standardError.write(Data("BEATDROPPER_NATIVE_PLAYBACK_STRESS_FAILED reason=\"\(error.localizedDescription)\"\n".utf8))
            exit(1)
        }
    }
}
