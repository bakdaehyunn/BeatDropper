import BeatDropperCore
import SwiftUI

extension ContentView {
    var playbackControlBar: some View {
        HStack(spacing: 12) {
            Label("Transport", systemImage: "playpause")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if model.workspaceMode == .playing, !model.playlist.isEmpty {
                    Toggle(
                        isOn: Binding(
                            get: { model.isAIMixEnabled },
                            set: { model.setAIMixEnabled($0) }
                        )
                    ) {
                        Text("AI Mix")
                    }
                    .toggleStyle(AIMixSwitchToggleStyle())
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(!model.isAIMixEnabled && !model.canEnableAIMix)
                    .help(model.isAIMixEnabled ? "Turn off AI mix automation" : "Analyze this playlist and keep AI mix planning active")
                    .accessibilityLabel(model.isAIMixEnabled ? "Turn off AI mix" : "Turn on AI mix")
                }

                centeredIconButton(
                    systemImage: "backward.end",
                    help: "Crossfade to previous track",
                    accessibilityLabel: "Crossfade to previous track"
                ) {
                    model.playPreviousTrack()
                }
                .disabled(!model.hasPreviousTrack)

                centeredIconButton(
                    systemImage: model.isPlaybackActive ? "pause.fill" : "play.fill",
                    help: model.isPlaybackActive ? "Pause playback" : "Start playback",
                    accessibilityLabel: model.isPlaybackActive ? "Pause playback" : "Start playback"
                ) {
                    model.playPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.canUseTransportPlayPause)

                centeredIconButton(
                    systemImage: "forward.end",
                    help: "Crossfade to next track",
                    accessibilityLabel: "Crossfade to next track"
                ) {
                    model.playNextTrack()
                }
                .disabled(!model.hasNextTrack)
            }
            .frame(width: model.workspaceMode == .playing && !model.playlist.isEmpty ? 286 : 142, alignment: .center)

            transportPositionText
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.24), lineWidth: 1)
        )
        .accessibilityLabel("Transport controls")
    }

    @ViewBuilder
    var transportPositionText: some View {
        if model.audioEngine.currentTrack != nil {
            Text(formatDuration(model.audioEngine.elapsedSec))
        } else if let countdown = model.scheduledMixCountdownSec {
            Text("Mix in \(formatDuration(countdown))")
        } else {
            Text("")
        }
    }

    var statusBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.audioEngine.state.rawValue)
                    .font(.headline)
                Text(transportDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            outputLevelMeter("MASTER", model.audioEngine.outputMeter)
                .frame(width: 150)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.24), lineWidth: 1)
        )
        .accessibilityLabel("Playback status")
    }

    var shouldShowStatusBar: Bool {
        shouldShowMixMonitor ||
            model.audioEngine.isPlaybackActive ||
            model.audioEngine.state == .paused
    }

    var shouldShowMixMonitor: Bool {
        model.workspaceMode == .playing && hasPlayableSurface
    }

    var hasPlayableSurface: Bool {
        !model.playlist.isEmpty ||
            model.currentMixPlan != nil ||
            model.isPlanningMix ||
            model.audioEngine.currentTrack != nil ||
            model.audioEngine.queuedTrack != nil ||
            model.audioEngine.isPlaybackActive ||
            model.audioEngine.state == .paused
    }

    var transportDetail: String {
        if let recoveryNotice = model.audioEngine.recoveryNotice {
            return recoveryNotice
        }
        if model.audioEngine.state == .crossfading {
            return "\(model.notice) · \(Int((model.audioEngine.crossfadeProgress * 100).rounded()))%"
        }
        return model.notice
    }

    func outputLevelMeter(_ label: String, _ meter: AudioLevelMeter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(meter.clipped ? "CLIP" : "\(Int(meter.peakDb.rounded())) dB")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(meter.clipped ? .red : .secondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor).opacity(0.28))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(meter.clipped ? Color.red : Color.accentColor)
                        .frame(width: max(2, proxy.size.width * meter.rms))
                    Rectangle()
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: 2)
                        .offset(x: max(0, min(proxy.size.width - 2, proxy.size.width * meter.peak)))
                }
            }
            .frame(height: 7)
        }
        .frame(height: 32)
        .accessibilityLabel("\(label.capitalized) output level")
        .accessibilityValue(meter.clipped ? "clipping" : "\(Int(meter.peakDb.rounded())) decibels")
    }
}
