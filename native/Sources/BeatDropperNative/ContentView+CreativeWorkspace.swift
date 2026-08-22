import BeatDropperApplication
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

            if navigation.isLibraryBrowserVisible {
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
            if let track = creative.preparationTrack(in: library) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Track Prep", systemImage: "waveform.badge.magnifyingglass")
                            .font(.title3.weight(.semibold))
                        Text(track.track.title)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 14) {
                            metric("BPM", creative.effectiveBPM(in: library).map { String(Int($0.rounded())) } ?? "--")
                            metric("Length", formatDuration(track.track.durationSec))
                            metric("Quality", creative.preparationAnalysis(in: library).map { "\(Int(($0.analysisConfidence * 100).rounded()))%" } ?? "--")
                            metric("Grid", creative.preparationAnalysis(in: library).map { "\(Int(($0.analysisQuality.beatGrid * 100).rounded()))%" } ?? "--")
                            metric("Position", formatDuration(creative.playbackPosition(in: library, playing: playing)))
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
        .onChange(of: creative.preparationTrackID) { _, _ in
            syncCreativeBPMDraft()
        }
        .onChange(of: creative.trackPreparation(in: library).bpmOverride) { _, _ in
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
                    model.creativeActions.seekCreativePreview(by: -5)
                }
                .disabled(!creative.canPreview(in: library))

                centeredIconButton(
                    systemImage: creative.isPreviewPlaying(in: library, playing: playing) ? "pause.fill" : "play.fill",
                    help: creative.isPreviewPlaying(in: library, playing: playing) ? "Pause preview" : "Play preview",
                    accessibilityLabel: creative.isPreviewPlaying(in: library, playing: playing) ? "Pause preview" : "Play preview"
                ) {
                    model.creativeActions.toggleCreativePreviewPlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!creative.canPreview(in: library))

                centeredIconButton(
                    systemImage: "goforward.5",
                    help: "Preview five seconds later",
                    accessibilityLabel: "Preview five seconds later"
                ) {
                    model.creativeActions.seekCreativePreview(by: 5)
                }
                .disabled(!creative.canPreview(in: library))

                centeredIconButton(
                    systemImage: "stop.fill",
                    help: "Stop preview",
                    accessibilityLabel: "Stop preview"
                ) {
                    model.creativeActions.stopCreativePreview()
                }
                .disabled(!creative.isPreviewTrackLoaded(in: library, playing: playing))
            }
            .frame(width: 190, alignment: .center)

            Text(formatDuration(creative.playbackPosition(in: library, playing: playing)))
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
                        model.creativeActions.setCreativeBPMOverride(bpm)
                        syncCreativeBPMDraft()
                    }
                }
                .disabled(!isCreativeBPMDraftValid)
                .help("Set prep BPM")

                Button("Tap", systemImage: "metronome") {
                    model.creativeActions.tapBPMForCreativeTrack()
                }
                .help("Tap along to estimate a prep BPM")

                if creative.bpmTapEstimate != nil {
                    Button("Use Tap", systemImage: "arrow.down.circle") {
                        model.creativeActions.applyTappedBPMToCreativeTrack()
                        syncCreativeBPMDraft()
                    }
                    .help("Use tapped BPM as prep BPM")
                }

                if creative.trackPreparation(in: library).bpmOverride != nil {
                    centeredIconButton(
                        systemImage: "xmark.circle",
                        help: "Clear prep BPM",
                        accessibilityLabel: "Clear prep BPM"
                    ) {
                        model.creativeActions.clearCreativeBPMOverride()
                    }
                }
            }
            .controlSize(.small)

            HStack(spacing: 12) {
                metric("Tap", creative.bpmTapEstimate.map { String(format: "%.1f", $0) } ?? "--")
                metric("Count", creative.bpmTapCount > 0 ? String(creative.bpmTapCount) : "--")
                metric("Prep", creative.trackPreparation(in: library).bpmOverride.map { String(format: "%.1f", $0) } ?? "--")
            }
        }
    }

    func creativeWaveform(track: ImportedTrack) -> some View {
        let analysis = creative.preparationAnalysis(in: library)
        let preparation = creative.trackPreparation(in: library)
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
                    timeSec: creative.playbackPosition(in: library, playing: playing),
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
                        model.creativeActions.previewCreativeTrack(at: Double(ratio) * durationSec)
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
                model.creativeActions.addCreativeHotCue(kind: creativeCueKind)
            }
            .help("Add a prep hot cue at the current preview position")

            Divider()
                .frame(height: 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(creative.trackPreparation(in: library).hotCues) { cue in
                        Button("\(cue.label) \(formatDuration(cue.timeSec))") {
                            model.creativeActions.previewCreativeTrack(at: cue.timeSec)
                        }
                        .controlSize(.small)
                        .help("Preview \(cue.label)")

                        centeredIconButton(
                            systemImage: "xmark.circle",
                            help: "Remove \(cue.label)",
                            accessibilityLabel: "Remove \(cue.label) cue"
                        ) {
                            model.creativeActions.removeCreativeHotCue(cue)
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
        if let bpm = creative.trackPreparation(in: library).bpmOverride ?? creative.effectiveBPM(in: library) {
            creativeBPMDraft = String(format: "%.1f", bpm)
        } else {
            creativeBPMDraft = ""
        }
    }
}
