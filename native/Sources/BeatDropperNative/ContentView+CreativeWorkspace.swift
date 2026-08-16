import BeatDropperCore
import SwiftUI

extension ContentView {
    var creativeWorkspace: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                creativeTrackMonitor
                Divider()
                creativePreviewTransportBar
            }
                .frame(height: 304)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.32), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .zIndex(1)
            creativeCollectionArea
                .frame(minHeight: 0, maxHeight: .infinity)
                .zIndex(0)
        }
        .accessibilityLabel("Creative workspace")
    }

    var creativeCollectionArea: some View {
        HStack(spacing: 16) {
            playlistPane
                .frame(minWidth: 420, idealWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.32), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .layoutPriority(2)

            if model.isLibraryBrowserVisible {
                libraryPane
                    .frame(minWidth: 270, idealWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator.opacity(0.32), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
    }

    var creativeTrackMonitor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let track = model.creativePreparationTrack {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Track Prep", systemImage: "waveform.badge.magnifyingglass")
                            .font(.title3.weight(.semibold))
                        Text(track.track.title)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 14) {
                            metric("BPM", model.creativeEffectiveBPM.map { String(Int($0.rounded())) } ?? "--")
                            metric("Length", formatDuration(track.track.durationSec))
                            metric("Quality", model.creativePreparationAnalysis.map { "\(Int(($0.analysisConfidence * 100).rounded()))%" } ?? "--")
                            metric("Grid", model.creativePreparationAnalysis.map { "\(Int(($0.analysisQuality.beatGrid * 100).rounded()))%" } ?? "--")
                            metric("Position", formatDuration(model.creativePlaybackPositionSec))
                        }
                    }

                    Spacer(minLength: 8)

                    creativeBPMControls
                        .frame(width: 330)
                }

                creativeWaveform(track: track)

                creativeCueControls
            } else {
                ContentUnavailableView("No Track", systemImage: "waveform")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityLabel("Creative track monitor")
        .onAppear {
            syncCreativeBPMDraft()
        }
        .onChange(of: model.creativePreparationTrackID) { _, _ in
            syncCreativeBPMDraft()
        }
        .onChange(of: model.creativeTrackPreparation.bpmOverride) { _, _ in
            syncCreativeBPMDraft()
        }
    }

    var creativePreviewTransportBar: some View {
        HStack(spacing: 12) {
            Label("Preview", systemImage: "playpause")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                centeredIconButton(
                    systemImage: "gobackward.5",
                    help: "Preview five seconds earlier",
                    accessibilityLabel: "Preview five seconds earlier"
                ) {
                    model.seekCreativePreview(by: -5)
                }
                .disabled(!model.canPreviewCreativeTrack)

                centeredIconButton(
                    systemImage: model.isCreativePreviewPlaying ? "pause.fill" : "play.fill",
                    help: model.isCreativePreviewPlaying ? "Pause preview" : "Play preview",
                    accessibilityLabel: model.isCreativePreviewPlaying ? "Pause preview" : "Play preview"
                ) {
                    model.toggleCreativePreviewPlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.canPreviewCreativeTrack)

                centeredIconButton(
                    systemImage: "goforward.5",
                    help: "Preview five seconds later",
                    accessibilityLabel: "Preview five seconds later"
                ) {
                    model.seekCreativePreview(by: 5)
                }
                .disabled(!model.canPreviewCreativeTrack)

                centeredIconButton(
                    systemImage: "stop.fill",
                    help: "Stop preview",
                    accessibilityLabel: "Stop preview"
                ) {
                    model.stopCreativePreview()
                }
                .disabled(!model.isCreativePreviewTrackLoaded)
            }
            .frame(width: 190, alignment: .center)

            Text(formatDuration(model.creativePlaybackPositionSec))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.24), lineWidth: 1)
        )
        .accessibilityLabel("Preview transport controls")
    }

    var creativeBPMControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Beat Grid", systemImage: "metronome")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("BPM", text: $creativeBPMDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .accessibilityLabel("Prep BPM")

                Button("Set", systemImage: "checkmark") {
                    if let bpm = parsedCreativeBPMDraft {
                        model.setCreativeBPMOverride(bpm)
                        syncCreativeBPMDraft()
                    }
                }
                .disabled(!isCreativeBPMDraftValid)
                .help("Set prep BPM")

                Button("Tap", systemImage: "metronome") {
                    model.tapBPMForCreativeTrack()
                }
                .help("Tap along to estimate a prep BPM")

                if model.bpmTapEstimate != nil {
                    Button("Use Tap", systemImage: "arrow.down.circle") {
                        model.applyTappedBPMToCreativeTrack()
                        syncCreativeBPMDraft()
                    }
                    .help("Use tapped BPM as prep BPM")
                }

                if model.creativeTrackPreparation.bpmOverride != nil {
                    centeredIconButton(
                        systemImage: "xmark.circle",
                        help: "Clear prep BPM",
                        accessibilityLabel: "Clear prep BPM"
                    ) {
                        model.clearCreativeBPMOverride()
                    }
                }
            }
            .controlSize(.small)

            HStack(spacing: 12) {
                metric("Tap", model.bpmTapEstimate.map { String(format: "%.1f", $0) } ?? "--")
                metric("Count", model.bpmTapCount > 0 ? String(model.bpmTapCount) : "--")
                metric("Prep", model.creativeTrackPreparation.bpmOverride.map { String(format: "%.1f", $0) } ?? "--")
            }
        }
    }

    func creativeWaveform(track: ImportedTrack) -> some View {
        let analysis = model.creativePreparationAnalysis
        let preparation = model.creativeTrackPreparation
        let points = waveformRenderPoints(for: analysis)
        let durationSec = max(0, track.track.durationSec)

        return GeometryReader { proxy in
            Canvas { context, size in
                drawWaveformBackground(in: context, size: size)

                if points.isEmpty {
                    drawWaveformPlaceholder(
                        in: context,
                        size: size,
                        label: analysis == nil ? "DSP --" : "--"
                    )
                } else {
                    drawBarMarkers(analysis?.barGrid ?? [], durationSec: durationSec, in: context, size: size)
                    drawPhraseMarkers(analysis?.phraseMarkers ?? [], durationSec: durationSec, in: context, size: size)
                    drawTransientMarkers(analysis?.transientMarkers ?? [], durationSec: durationSec, in: context, size: size)
                    drawWaveformPoints(points, in: context, size: size, isNextDeck: false)
                }

                drawPreparationCueMarkers(preparation.hotCues, durationSec: durationSec, in: context, size: size)
                drawWaveformCursor(
                    timeSec: model.creativePlaybackPositionSec,
                    durationSec: durationSec,
                    label: "PLAY",
                    color: .white,
                    in: context,
                    size: size
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard proxy.size.width > 0, durationSec > 0 else {
                            return
                        }
                        let ratio = min(1, max(0, value.location.x / proxy.size.width))
                        model.previewCreativeTrack(at: Double(ratio) * durationSec)
                    }
            )
        }
        .frame(height: 98)
        .accessibilityLabel("Creative waveform editor")
        .accessibilityValue("\(preparation.hotCues.count) hot cues")
    }

    var creativeCueControls: some View {
        HStack(spacing: 8) {
            Picker("Cue", selection: $creativeCueKind) {
                ForEach(TrackPreparationCueKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Button("Add Cue", systemImage: "mappin.and.ellipse") {
                model.addCreativeHotCue(kind: creativeCueKind)
            }
            .help("Add a prep hot cue at the current preview position")

            Divider()
                .frame(height: 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.creativeTrackPreparation.hotCues) { cue in
                        Button("\(cue.label) \(formatDuration(cue.timeSec))") {
                            model.previewCreativeTrack(at: cue.timeSec)
                        }
                        .controlSize(.small)
                        .help("Preview \(cue.label)")

                        centeredIconButton(
                            systemImage: "xmark.circle",
                            help: "Remove \(cue.label)",
                            accessibilityLabel: "Remove \(cue.label) cue"
                        ) {
                            model.removeCreativeHotCue(cue)
                        }
                    }
                }
            }
        }
        .controlSize(.small)
    }

    var parsedCreativeBPMDraft: Double? {
        let normalized = creativeBPMDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let bpm = Double(normalized), bpm.isFinite else {
            return nil
        }
        return bpm
    }

    var isCreativeBPMDraftValid: Bool {
        guard let bpm = parsedCreativeBPMDraft else {
            return false
        }
        return (40...260).contains(bpm)
    }

    func syncCreativeBPMDraft() {
        if let bpm = model.creativeTrackPreparation.bpmOverride ?? model.creativeEffectiveBPM {
            creativeBPMDraft = String(format: "%.1f", bpm)
        } else {
            creativeBPMDraft = ""
        }
    }
}
