import Foundation
import SwiftUI

final class DroppedFileURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        let current = urls
        lock.unlock()
        return current
    }
}

struct WaveformRenderPoint: Identifiable {
    var id: Int
    var timeSec: Double
    var peak: Double
    var rms: Double
    var low: Double
    var mid: Double
    var high: Double
}

struct AIMixSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                    .labelStyle(.titleOnly)
                    .font(.callout.weight(.semibold))
                    .frame(width: 45, alignment: .leading)
                    .lineLimit(1)

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.green : Color(nsColor: .separatorColor).opacity(0.34))
                    Capsule()
                        .stroke(Color(nsColor: .separatorColor).opacity(configuration.isOn ? 0.18 : 0.36), lineWidth: 1)
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.24), radius: 2, x: 0, y: 1)
                        .padding(2.5)
                }
                .frame(width: 40, height: 22)
                .opacity(isEnabled ? 1 : 0.45)
            }
            .padding(.leading, 9)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(
                Color(nsColor: .textBackgroundColor).opacity(isEnabled ? 0.3 : 0.16),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(0.22),
                        lineWidth: 1
                    )
            )
            .opacity(isEnabled ? 1 : 0.55)
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
    }
}

struct CenteredIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var width: CGFloat = 42
    var height: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.42))
            .frame(width: width, height: height, alignment: .center)
            .background(
                Color(nsColor: .controlColor)
                    .opacity(configuration.isPressed ? 0.72 : 0.46),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

enum AppLayoutMetrics {
    static let minimumWindowWidth: CGFloat = 760
    static let minimumWindowHeight: CGFloat = 520
    static let minimumContentWidth: CGFloat = 980
    static let minimumContentHeight: CGFloat = 680
}
