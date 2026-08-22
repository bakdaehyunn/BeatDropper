import BeatDropperApplication
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
            outputLevelMeter("MASTER", playing.session.outputMeter)
                .frame(width: 132)
        }
    }

    var persistentTransportCompactLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                transportNowPlayingSummary
                Spacer(minLength: 8)
                aiMixTransportToggle
                outputLevelMeter("MASTER", playing.session.outputMeter)
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
            Text(playing.session.currentTrack?.title ?? "No track loaded")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(playing.session.mode.rawValue) · \(transportDetail)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current track")
    }

    var transportProgress: some View {
        let durationSec = max(0, playing.session.currentTrack?.durationSec ?? 0)
        let elapsedSec = min(durationSec, max(0, playing.session.currentElapsedSec))

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
                model.playingActions.playPreviousTrack()
            }
            .disabled(!library.hasPreviousTrack)

            transportPlayPauseButton

            centeredIconButton(
                systemImage: "forward.end",
                help: "Crossfade to next track",
                accessibilityLabel: "Crossfade to next track"
            ) {
                model.playingActions.playNextTrack()
            }
            .disabled(!library.hasNextTrack)
        }
    }

    @ViewBuilder
    var transportPlayPauseButton: some View {
        if navigation.workspaceMode == .playing {
            transportPlayPauseButtonBase
                .keyboardShortcut(.space, modifiers: [])
        } else {
            transportPlayPauseButtonBase
        }
    }

    var transportPlayPauseButtonBase: some View {
        centeredIconButton(
            systemImage: playing.isPlaybackActive ? "pause.fill" : "play.fill",
            help: playing.isPlaybackActive ? "Pause playback" : "Start playback",
            accessibilityLabel: playing.isPlaybackActive ? "Pause playback" : "Start playback"
        ) {
            model.playingActions.playPause()
        }
        .disabled(!playing.canUseTransport(in: library))
    }

    var aiMixTransportToggle: some View {
        Toggle(
            isOn: Binding(
                get: { planning.isEnabled },
                set: { model.planningActions.setAIMixEnabled($0) }
            )
        ) {
            Text("AI Mix")
        }
        .toggleStyle(AIMixSwitchToggleStyle())
        .disabled(!planning.isEnabled && !planning.canEnable(in: library))
        .help(planning.isEnabled ? "Turn off AI mix automation" : "Analyze this playlist and keep AI mix planning active")
        .accessibilityLabel(planning.isEnabled ? "Turn off AI mix" : "Turn on AI mix")
    }

    var transportDetail: String {
        if let recoveryNotice = playing.session.recoveryNotice {
            return recoveryNotice
        }
        if playing.session.mode == .crossfading {
            return "\(shell.notice) · \(Int((playing.session.transitionProgress * 100).rounded()))%"
        }
        return shell.notice
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
