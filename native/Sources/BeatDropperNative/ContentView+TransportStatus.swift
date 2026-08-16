import BeatDropperCore
import SwiftUI

extension ContentView {
    var playbackControlBar: some View {
        ViewThatFits(in: .horizontal) {
            persistentTransportWideLayout
            persistentTransportCompactLayout
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityLabel("Persistent playback transport")
    }

    var persistentTransportWideLayout: some View {
        HStack(spacing: 16) {
            transportNowPlayingSummary
                .frame(minWidth: 170, idealWidth: 220, maxWidth: 260, alignment: .leading)
            transportProgress
                .frame(minWidth: 180, maxWidth: .infinity)
            transportButtons
                .fixedSize()
            aiMixTransportToggle
                .fixedSize()
            outputLevelMeter("MASTER", model.audioEngine.outputMeter)
                .frame(width: 132)
        }
    }

    var persistentTransportCompactLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                transportNowPlayingSummary
                Spacer(minLength: 8)
                aiMixTransportToggle
                outputLevelMeter("MASTER", model.audioEngine.outputMeter)
                    .frame(width: 112)
            }
            HStack(spacing: 14) {
                transportProgress
                transportButtons
                    .fixedSize()
            }
        }
    }

    var transportNowPlayingSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.audioEngine.currentTrack?.title ?? model.selectedTrack?.track.title ?? "No track loaded")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(model.audioEngine.state.rawValue) · \(transportDetail)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current track")
    }

    var transportProgress: some View {
        let durationSec = max(0, model.audioEngine.currentTrack?.durationSec ?? 0)
        let elapsedSec = min(durationSec, max(0, model.audioEngine.elapsedSec))

        return VStack(spacing: 3) {
            ProgressView(value: durationSec > 0 ? elapsedSec / durationSec : 0)
                .progressViewStyle(.linear)
                .tint(.accentColor)
            HStack {
                Text(formatDuration(elapsedSec))
                Spacer()
                Text(durationSec > 0 ? formatDuration(durationSec) : "--:--")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playback progress")
        .accessibilityValue(durationSec > 0 ? "\(formatDuration(elapsedSec)) of \(formatDuration(durationSec))" : "No track loaded")
    }

    var transportButtons: some View {
        HStack(spacing: 8) {
            centeredIconButton(
                systemImage: "backward.end",
                help: "Crossfade to previous track",
                accessibilityLabel: "Crossfade to previous track"
            ) {
                model.playPreviousTrack()
            }
            .disabled(!model.hasPreviousTrack)

            transportPlayPauseButton

            centeredIconButton(
                systemImage: "forward.end",
                help: "Crossfade to next track",
                accessibilityLabel: "Crossfade to next track"
            ) {
                model.playNextTrack()
            }
            .disabled(!model.hasNextTrack)
        }
    }

    @ViewBuilder
    var transportPlayPauseButton: some View {
        if model.workspaceMode == .playing {
            transportPlayPauseButtonBase
                .keyboardShortcut(.space, modifiers: [])
        } else {
            transportPlayPauseButtonBase
        }
    }

    var transportPlayPauseButtonBase: some View {
        centeredIconButton(
            systemImage: model.isPlaybackActive ? "pause.fill" : "play.fill",
            help: model.isPlaybackActive ? "Pause playback" : "Start playback",
            accessibilityLabel: model.isPlaybackActive ? "Pause playback" : "Start playback"
        ) {
            model.playPause()
        }
        .disabled(!model.canUseTransportPlayPause)
    }

    var aiMixTransportToggle: some View {
        Toggle(
            isOn: Binding(
                get: { model.isAIMixEnabled },
                set: { model.setAIMixEnabled($0) }
            )
        ) {
            Text("AI Mix")
        }
        .toggleStyle(AIMixSwitchToggleStyle())
        .disabled(!model.isAIMixEnabled && !model.canEnableAIMix)
        .help(model.isAIMixEnabled ? "Turn off AI mix automation" : "Analyze this playlist and keep AI mix planning active")
        .accessibilityLabel(model.isAIMixEnabled ? "Turn off AI mix" : "Turn on AI mix")
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
