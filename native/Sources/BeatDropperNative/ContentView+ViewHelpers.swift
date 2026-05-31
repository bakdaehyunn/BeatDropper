import BeatDropperCore
import SwiftUI

extension ContentView {
    func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    func centeredIconButton(
        systemImage: String,
        help: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .buttonStyle(CenteredIconButtonStyle())
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }

    func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--"
        }
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    func progress(_ elapsedSec: Double, durationSec: Double) -> Double {
        guard elapsedSec.isFinite, durationSec.isFinite, durationSec > 0 else {
            return 0
        }
        return min(1, max(0, elapsedSec / durationSec))
    }
}
