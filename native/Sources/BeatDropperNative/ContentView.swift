import BeatDropperCore
import SwiftUI
import UniformTypeIdentifiers

private final class DroppedFileURLAccumulator: @unchecked Sendable {
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

private struct WaveformRenderPoint: Identifiable {
    var id: Int
    var timeSec: Double
    var peak: Double
    var rms: Double
    var low: Double
    var mid: Double
    var high: Double
}

private struct AIMixSwitchToggleStyle: ToggleStyle {
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

private struct CenteredIconButtonStyle: ButtonStyle {
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

private enum AppLayoutMetrics {
    static let minimumWindowWidth: CGFloat = 760
    static let minimumWindowHeight: CGFloat = 520
    static let minimumContentWidth: CGFloat = 980
    static let minimumContentHeight: CGFloat = 680
}

struct ContentView: View {
    @EnvironmentObject private var model: BeatDropperAppModel
    @State private var isFileDropTargeted = false
    @State private var creativeCueKind: TrackPreparationCueKind = .drop
    @State private var creativeBPMDraft = ""

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                appShell
                    .frame(
                        width: max(proxy.size.width, AppLayoutMetrics.minimumContentWidth),
                        height: max(proxy.size.height, AppLayoutMetrics.minimumContentHeight),
                        alignment: .top
                    )
            }
        }
        .frame(
            minWidth: AppLayoutMetrics.minimumWindowWidth,
            minHeight: AppLayoutMetrics.minimumWindowHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isFileDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
            loadDroppedFileURLs(from: providers)
        }
        .accessibilityLabel("BeatDropper DJ workspace")
    }

    private var appShell: some View {
        VStack(spacing: 0) {
            toolbar
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(4)
            Divider()
            ZStack(alignment: .trailing) {
                mainStage

                if shouldShowInspectorDrawer {
                    inspectorDrawer
                        .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: AppLayoutMetrics.minimumContentWidth,
            minHeight: AppLayoutMetrics.minimumContentHeight
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var mainStage: some View {
        VStack(spacing: 8) {
            if shouldShowMixMonitor {
                mixMonitor
                    .frame(height: 360)
                    .clipped()
                    .layoutPriority(3)
            }
            workspaceContent
                .frame(minHeight: 0, maxHeight: .infinity)
                .layoutPriority(1)
            if shouldShowStatusBar {
                statusBar
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BeatDropper")
                    .font(.title2.weight(.semibold))
                if let analysisQueueStatus = model.analysisQueueStatus {
                    Text(analysisQueueStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Mode", selection: $model.workspaceMode) {
                ForEach(NativeWorkspaceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .accessibilityLabel("Workspace mode")

            Spacer()

            Button("New Set", systemImage: "folder") {
                model.newSet()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .help("Start a new set from selected audio files")

            if !model.playlist.isEmpty {
                Button("Add Tracks", systemImage: "plus.circle") {
                    model.addTracks()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Add tracks to the current set")
            }

            Button("Import Folder", systemImage: "folder.badge.plus") {
                model.importFolder()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help("Import a music folder into the library")

            if model.workspaceMode == .playing || !model.isLibraryBrowserVisible {
                Button("Library", systemImage: "rectangle.stack") {
                    model.workspaceMode = .creative
                    model.isLibraryBrowserVisible = true
                }
                .help("Show library browser")
            }

            if model.workspaceMode == .playing {
                Button(model.isInspectorVisible ? "Hide Inspector" : "Inspector", systemImage: "sidebar.right") {
                    model.isInspectorVisible.toggle()
                }
                .keyboardShortcut("3", modifiers: [.command])
                .help(model.isInspectorVisible ? "Hide mix inspector" : "Show mix inspector")
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Primary toolbar")
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if model.workspaceMode == .creative {
            creativeWorkspace
        } else {
            playingWorkspace
        }
    }

    private var playingWorkspace: some View {
        VStack(spacing: 8) {
            playbackControlBar
                .fixedSize(horizontal: false, vertical: true)

            playlistPane
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.32), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var shouldShowInspectorDrawer: Bool {
        model.workspaceMode == .playing && model.isInspectorVisible
    }

    private var inspectorDrawer: some View {
        inspectorPane
            .frame(width: 360)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .leading)
            .shadow(color: .black.opacity(0.28), radius: 14, x: -8, y: 0)
            .accessibilityLabel("Mix inspector drawer")
    }

    private var creativeWorkspace: some View {
        VStack(spacing: 14) {
            creativeTrackMonitor
                .frame(height: 260)
            creativePreviewTransportBar
                .frame(height: 52)
                .zIndex(1)
            creativeCollectionArea
                .frame(minHeight: 0, maxHeight: .infinity)
                .zIndex(0)
        }
        .accessibilityLabel("Creative workspace")
    }

    private var creativeCollectionArea: some View {
        HStack(spacing: 8) {
            playlistPane
                .frame(minWidth: 560, idealWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.32), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .layoutPriority(2)

            if model.isLibraryBrowserVisible {
                libraryPane
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
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
        .padding(.top, 4)
    }

    private var creativeTrackMonitor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let track = model.creativePreparationTrack {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Track Prep")
                            .font(.title3.weight(.semibold))
                        Text(track.track.title)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 14) {
                            metric("BPM", model.creativeEffectiveBPM.map { String(Int($0.rounded())) } ?? "--")
                            metric("Length", formatDuration(track.track.durationSec))
                            metric("Quality", model.creativePreparationAnalysis.map { "\(Int(($0.analysisConfidence * 100).rounded()))%" } ?? "--")
                            metric("Position", formatDuration(model.creativePlaybackPositionSec))
                        }
                    }

                    Spacer(minLength: 8)

                    creativeBPMControls
                        .frame(width: 300)
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

    private var creativePreviewTransportBar: some View {
        HStack(spacing: 12) {
            Label("Preview", systemImage: "playpause")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
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

            Spacer(minLength: 12)

            Text(formatDuration(model.creativePlaybackPositionSec))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.24), lineWidth: 1)
        )
        .accessibilityLabel("Preview transport controls")
    }

    private var creativeBPMControls: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private func creativeWaveform(track: ImportedTrack) -> some View {
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
        .frame(height: 88)
        .accessibilityLabel("Creative waveform editor")
        .accessibilityValue("\(preparation.hotCues.count) hot cues")
    }

    private var creativeCueControls: some View {
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

    private var mixMonitor: some View {
        VStack(spacing: 8) {
            playingMonitorMetaBar
            playingWaveformStack
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.32), lineWidth: 1)
        )
        .accessibilityLabel("Live mix monitor")
    }

    private var playingMonitorMetaBar: some View {
        HStack(spacing: 12) {
            Label("Track Monitor", systemImage: "waveform")
                .font(.headline.weight(.semibold))

            Spacer(minLength: 12)

            Text(playingMixStatusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .accessibilityLabel("Playing monitor status")
    }

    private var playingMixStatusText: String {
        if let plan = model.currentMixPlan {
            return "AI Mix \(model.scheduledMixCountdownSec.map { "in \(formatDuration($0))" } ?? "ready") · OUT \(formatDuration(plan.transitionStartSec)) · IN \(formatDuration(plan.nextTrackStartOffsetSec)) · \(Int((plan.confidence * 100).rounded()))%"
        }
        if model.isPlanningMix {
            return "AI Mix planning"
        }
        if model.isAIMixEnabled {
            return "AI Mix active"
        }
        return "AI Mix off"
    }

    private var playingWaveformStack: some View {
        VStack(spacing: 10) {
            deckWaveformRow(
                title: "Current",
                value: model.audioEngine.currentTrack != nil
                    ? formatDuration(model.audioEngine.elapsedSec)
                    : formatDuration(model.currentMixPlan?.transitionStartSec ?? model.currentDeckAnalysis?.outroCueSec ?? 0),
                track: model.currentDeckDisplayTrack,
                analysis: model.currentDeckAnalysis,
                elapsedSec: model.audioEngine.currentTrack != nil ? model.audioEngine.elapsedSec : nil,
                cueTimeSec: model.currentMixPlan?.transitionStartSec ?? model.currentDeckAnalysis?.outroCueSec,
                cueLabel: "OUT",
                isNextDeck: false,
                status: model.currentDeckDisplayStatus,
                meter: model.audioEngine.currentDeckMeter
            )

            deckWaveformRow(
                title: "Next",
                value: formatDuration(model.currentMixPlan?.nextTrackStartOffsetSec ?? model.nextDeckAnalysis?.introCueSec ?? 0),
                track: model.nextDeckDisplayTrack,
                analysis: model.nextDeckAnalysis,
                elapsedSec: nil,
                cueTimeSec: model.currentMixPlan?.nextTrackStartOffsetSec ?? model.nextDeckAnalysis?.introCueSec,
                cueLabel: "IN",
                isNextDeck: true,
                status: model.nextDeckDisplayStatus,
                meter: model.audioEngine.nextDeckMeter
            )
        }
        .padding(10)
        .background(
            Color(nsColor: .textBackgroundColor).opacity(0.35),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        )
        .accessibilityLabel("Playing waveform stack")
    }

    private func deckWaveformRow(
        title: String,
        value: String,
        track: Track?,
        analysis: TrackAnalysis?,
        elapsedSec: Double?,
        cueTimeSec: Double?,
        cueLabel: String,
        isNextDeck: Bool,
        status: String,
        meter: AudioLevelMeter
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                Text(track?.title ?? "No track")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                miniDeckMeter(meter)
                Text(status)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 124, alignment: .leading)

            trackWaveformStrip(
                title: title,
                track: track,
                analysis: analysis,
                elapsedSec: elapsedSec,
                cueTimeSec: cueTimeSec,
                cueLabel: cueLabel,
                isNextDeck: isNextDeck
            )
            .frame(height: 118)
        }
    }

    private func miniDeckMeter(_ meter: AudioLevelMeter) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor).opacity(0.28))
                RoundedRectangle(cornerRadius: 2)
                    .fill(meter.clipped ? Color.red : Color.accentColor)
                    .frame(width: max(2, proxy.size.width * meter.rms))
                Rectangle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 1.5)
                    .offset(x: max(0, min(proxy.size.width - 1.5, proxy.size.width * meter.peak)))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Deck level")
        .accessibilityValue(meter.clipped ? "clipping" : "\(Int(meter.peakDb.rounded())) decibels")
    }

    private func trackWaveformStrip(
        title: String,
        track: Track?,
        analysis: TrackAnalysis?,
        elapsedSec: Double?,
        cueTimeSec: Double?,
        cueLabel: String,
        isNextDeck: Bool
    ) -> some View {
        let points = waveformRenderPoints(for: analysis)
        let durationSec = max(0, track?.durationSec ?? 0)
        let accessibilityTitle = "\(title) waveform overview"

        return Canvas { context, size in
            drawWaveformBackground(in: context, size: size)

            guard track != nil, durationSec > 0 else {
                drawWaveformPlaceholder(in: context, size: size, label: "--")
                return
            }

            guard !points.isEmpty else {
                drawWaveformPlaceholder(in: context, size: size, label: "DSP --")
                return
            }

            drawBarMarkers(analysis?.barGrid ?? [], durationSec: durationSec, in: context, size: size)
            drawPhraseMarkers(analysis?.phraseMarkers ?? [], durationSec: durationSec, in: context, size: size)
            drawTransientMarkers(analysis?.transientMarkers ?? [], durationSec: durationSec, in: context, size: size)

            drawWaveformPoints(points, in: context, size: size, isNextDeck: isNextDeck)

            if let cueTimeSec {
                drawWaveformCursor(
                    timeSec: cueTimeSec,
                    durationSec: durationSec,
                    label: cueLabel,
                    color: isNextDeck ? .cyan : .orange,
                    in: context,
                    size: size,
                    alignTrailing: !isNextDeck
                )
            }

            if let elapsedSec {
                drawWaveformCursor(
                    timeSec: elapsedSec,
                    durationSec: durationSec,
                    label: "PLAY",
                    color: .white,
                    in: context,
                    size: size
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        )
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(points.isEmpty ? "no waveform data" : "\(points.count) waveform points")
    }

    private func metric(_ label: String, _ value: String) -> some View {
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

    private func centeredIconButton(
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

    private var playlistPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playlist")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(model.playlist.count) tracks · \(formatDuration(model.totalDurationSec)) total")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if model.workspaceMode == .creative {
                savedSetsManagementBar
            }

            if !model.playlist.isEmpty {
                playlistEditActions
            }

            playlistContent
                .frame(minHeight: 120, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, model.workspaceMode == .creative ? 24 : 20)
        .padding(.bottom, 16)
    }

    private var playlistEditActions: some View {
        HStack(spacing: 8) {
            centeredIconButton(
                systemImage: "arrow.up",
                help: "Move selected track up",
                accessibilityLabel: "Move selected track up"
            ) {
                model.moveSelectedTrack(offset: -1)
            }
            .disabled(!model.canMoveSelectedTrackUp)

            centeredIconButton(
                systemImage: "arrow.down",
                help: "Move selected track down",
                accessibilityLabel: "Move selected track down"
            ) {
                model.moveSelectedTrack(offset: 1)
            }
            .disabled(!model.canMoveSelectedTrackDown)

            centeredIconButton(
                systemImage: "trash",
                help: "Remove selected track",
                accessibilityLabel: "Remove selected track"
            ) {
                model.removeSelectedTrack()
            }
            .disabled(!model.canRemoveSelectedTrack)

            centeredIconButton(
                systemImage: "text.badge.xmark",
                help: "Clear playlist",
                accessibilityLabel: "Clear playlist"
            ) {
                model.clearPlaylist()
            }
            .disabled(!model.canClearPlaylist)
        }
    }

    @ViewBuilder
    private var playlistContent: some View {
        if model.playlist.isEmpty {
            emptyPanel("No Tracks", systemImage: "music.note")
                .accessibilityLabel("Current playlist")
        } else {
            Table(model.playlist, selection: $model.selectedTrackID) {
                TableColumn("#") { imported in
                    Text(rowNumber(for: imported))
                        .foregroundStyle(.secondary)
                }
                .width(34)

                TableColumn("Track") { imported in
                    HStack(spacing: 6) {
                        if !model.isTrackAvailable(imported) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        Text(imported.track.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(model.isTrackAvailable(imported) ? .primary : .secondary)
                }

                TableColumn("BPM") { imported in
                    Text(model.displayBPM(for: imported))
                        .monospacedDigit()
                }
                .width(52)

                TableColumn("Length") { imported in
                    Text(formatDuration(imported.track.durationSec))
                        .monospacedDigit()
                }
                .width(64)
            }
            .accessibilityLabel("Current playlist")
        }
    }

    private var maintenanceActions: some View {
        HStack(spacing: 8) {
            if model.hasLibrarySourceFolders {
                Button("Rescan", systemImage: "arrow.triangle.2.circlepath") {
                    model.rescanLibraryFolders()
                }
                .help("Rescan imported library folders")
            }

            if model.hasMissingSourceFolders {
                Menu("Relink", systemImage: "link") {
                    ForEach(model.missingSourceFolders) { folder in
                        Button(folder.displayName, systemImage: "folder.badge.questionmark") {
                            model.relinkMissingSourceFolder(folder)
                        }
                    }
                }
                .help("Relink missing library folders")
            }

            if model.selectedTrackNeedsRelink {
                Button("Relink File", systemImage: "link") {
                    model.relinkSelectedTrack()
                }
            }
        }
        .controlSize(.small)
    }

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(model.libraryBrowserTracks.count) tracks")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                maintenanceActions

                centeredIconButton(
                    systemImage: "xmark",
                    help: "Hide library browser",
                    accessibilityLabel: "Hide library browser"
                ) {
                    model.isLibraryBrowserVisible = false
                }
            }

            if !model.libraryBrowserTracks.isEmpty || !model.librarySearchText.isEmpty {
                TextField("Search library", text: $model.librarySearchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search library")
            }

            if model.canAddSelectedLibraryTrackToPlaylist {
                Button("Add to Set", systemImage: "plus.circle") {
                    model.addSelectedLibraryTrackToPlaylist()
                }
                .help("Add selected library track to the current set")
            }

            libraryContent
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var libraryContent: some View {
        if model.filteredLibraryTracks.isEmpty {
            emptyPanel(libraryEmptyTitle, systemImage: "rectangle.stack")
                .accessibilityLabel("Library browser")
        } else {
            Table(model.filteredLibraryTracks, selection: $model.selectedLibraryTrackID) {
                TableColumn("Track") { row in
                    HStack(spacing: 6) {
                        if !model.isTrackAvailable(row) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        Text(row.track.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(model.isTrackAvailable(row) ? .primary : .secondary)
                }

                TableColumn("BPM") { row in
                    Text(model.displayBPM(for: row))
                        .monospacedDigit()
                }
                .width(48)
            }
            .accessibilityLabel("Library browser")
        }
    }

    private var libraryEmptyTitle: String {
        model.librarySearchText.isEmpty ? "No Library Tracks" : "No Matches"
    }

    private func emptyPanel(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var savedSetsManagementBar: some View {
        ViewThatFits(in: .horizontal) {
            savedSetsWideLayout
            savedSetsCompactLayout
        }
        .padding(10)
        .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.28), lineWidth: 1)
        )
        .accessibilityLabel("Saved sets")
    }

    private var savedSetsWideLayout: some View {
        HStack(spacing: 10) {
            Label("Saved Sets", systemImage: "music.note.list")
                .font(.headline)
                .lineLimit(1)
                .frame(width: 126, alignment: .leading)

            Picker("Saved Set", selection: savedSetSelection) {
                Text("New Saved Set").tag("")
                ForEach(model.userPlaylists) { playlist in
                    Text(playlist.name).tag(playlist.id)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            TextField("Set name", text: $model.userPlaylistNameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)

            savedSetActions

            Spacer(minLength: 0)

            Text("\(model.userPlaylists.count) saved")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var savedSetsCompactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Saved Sets", systemImage: "music.note.list")
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 10) {
                Picker("Saved Set", selection: savedSetSelection) {
                    Text("New Saved Set").tag("")
                    ForEach(model.userPlaylists) { playlist in
                        Text(playlist.name).tag(playlist.id)
                    }
                }
                .labelsHidden()

                TextField("Set name", text: $model.userPlaylistNameDraft)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                savedSetActions
                Spacer()
                Text("\(model.userPlaylists.count) saved")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var savedSetActions: some View {
        if shouldShowSavedSetActions {
            HStack(spacing: 8) {
                if shouldShowSaveSetAction {
                    Button("Save", systemImage: "square.and.arrow.down") {
                        model.saveCurrentSet()
                    }
                    .disabled(!model.canSaveCurrentSet)
                    .help("Save the current set as a taste playlist")
                }

                if model.canLoadSelectedSet {
                    Button("Load", systemImage: "arrow.down.doc") {
                        model.loadSelectedSavedSet()
                    }
                    .help("Load the selected saved set")

                    Button("Rename", systemImage: "pencil") {
                        model.renameSelectedSavedSet()
                    }
                    .disabled(model.userPlaylistNameDraft.isEmpty)
                    .help("Rename the selected saved set")

                    Button("Delete", systemImage: "trash") {
                        model.deleteSelectedSavedSet()
                    }
                    .help("Delete the selected saved set")
                }
            }
            .controlSize(.small)
        }
    }

    private var shouldShowSavedSetActions: Bool {
        shouldShowSaveSetAction || model.canLoadSelectedSet
    }

    private var shouldShowSaveSetAction: Bool {
        !model.playlist.isEmpty || !model.userPlaylistNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var savedSetSelection: Binding<String> {
        Binding(
            get: { model.selectedUserPlaylistId },
            set: { model.selectUserPlaylist($0) }
        )
    }

    private var inspectorPane: some View {
        inspectorContent
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Mix Pair Inspector")
                    .font(.title3.weight(.semibold))

                Spacer()

                centeredIconButton(
                    systemImage: "xmark",
                    help: "Close mix inspector",
                    accessibilityLabel: "Close mix inspector"
                ) {
                    model.isInspectorVisible = false
                }
            }

            if let selectedTrack = model.selectedTrack {
                GroupBox("Selected Track") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.isTrackAvailable(selectedTrack) {
                            HStack {
                                Label("File unavailable", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                Spacer()
                                Button("Relink File", systemImage: "link") {
                                    model.relinkSelectedTrack()
                                }
                            }
                        }
                        Text(selectedTrack.track.title)
                            .font(.headline)
                            .lineLimit(2)
                        LabeledContent("Status", value: model.availabilityStatus(for: selectedTrack))
                        LabeledContent("BPM", value: selectedTrack.track.bpm.map { String(Int($0.rounded())) } ?? "--")
                        LabeledContent("Length", value: formatDuration(selectedTrack.track.durationSec))
                        LabeledContent("Format", value: selectedTrack.track.format.rawValue.uppercased())
                        LabeledContent("File", value: selectedTrack.url.lastPathComponent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Analysis") {
                    analysisSummary(for: selectedTrack)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("AI Mix Plan") {
                    mixPlanSummary
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No Selection", systemImage: "waveform")
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func analysisSummary(for selectedTrack: ImportedTrack) -> some View {
        if !model.isTrackAvailable(selectedTrack) {
            Text("--")
                .foregroundStyle(.secondary)
        } else if model.analyzingTrackIds.contains(selectedTrack.id) {
            ProgressView("Analyzing")
                .controlSize(.small)
        } else if let analysis = model.selectedTrackAnalysis {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Ready", value: analysis.analysisConfidence >= 0.65 ? "Yes" : "Low")
                LabeledContent("BPM", value: analysis.bpm.map { String(Int($0.rounded())) } ?? "--")
                LabeledContent("Conf", value: "\(Int((analysis.analysisConfidence * 100).rounded()))%")
                LabeledContent("Grid", value: "\(Int((analysis.analysisQuality.beatGrid * 100).rounded()))%")
                LabeledContent("Cue", value: cueSummary(for: analysis))
                if let intro = analysis.introCueSec {
                    LabeledContent("Intro", value: formatDuration(intro))
                }
                if let outro = analysis.outroCueSec {
                    LabeledContent("Outro", value: formatDuration(outro))
                }
            }
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mixPlanSummary: some View {
        if model.isPlanningMix {
            ProgressView("Planning")
                .controlSize(.small)
        } else if let plan = model.currentMixPlan {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Transition", value: "\(formatDuration(plan.transitionStartSec)) -> \(formatDuration(plan.transitionEndSec))")
                LabeledContent("Next In", value: formatDuration(plan.nextTrackStartOffsetSec))
                LabeledContent("Style", value: plan.style.rawValue.replacingOccurrences(of: "_", with: " "))
                LabeledContent("Confidence", value: "\(Int((plan.confidence * 100).rounded()))%")
                if let countdown = model.scheduledMixCountdownSec {
                    LabeledContent("Starts", value: formatDuration(countdown))
                }
            }
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    private var playbackControlBar: some View {
        ZStack {
            Label("Transport", systemImage: "playpause")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.24), lineWidth: 1)
        )
        .accessibilityLabel("Transport controls")
    }

    private var statusBar: some View {
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

    private var shouldShowStatusBar: Bool {
        shouldShowMixMonitor ||
            model.audioEngine.isPlaybackActive ||
            model.audioEngine.state == .paused
    }

    private var shouldShowMixMonitor: Bool {
        model.workspaceMode == .playing && hasPlayableSurface
    }

    private var hasPlayableSurface: Bool {
        !model.playlist.isEmpty ||
            model.currentMixPlan != nil ||
            model.isPlanningMix ||
            model.audioEngine.currentTrack != nil ||
            model.audioEngine.queuedTrack != nil ||
            model.audioEngine.isPlaybackActive ||
            model.audioEngine.state == .paused
    }

    private var transportDetail: String {
        if let recoveryNotice = model.audioEngine.recoveryNotice {
            return recoveryNotice
        }
        if model.audioEngine.state == .crossfading {
            return "\(model.notice) · \(Int((model.audioEngine.crossfadeProgress * 100).rounded()))%"
        }
        return model.notice
    }

    private func outputLevelMeter(_ label: String, _ meter: AudioLevelMeter) -> some View {
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

    private func cueSummary(for analysis: TrackAnalysis) -> String {
        let cueConfidence = analysis.cueCandidates.map(\.confidence).max() ?? 0
        return "\(Int((cueConfidence * 100).rounded()))%"
    }

    private func rowNumber(for imported: ImportedTrack) -> String {
        guard let index = model.playlist.firstIndex(where: { $0.id == imported.id }) else {
            return "--"
        }
        return String(index + 1)
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--"
        }
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    private var parsedCreativeBPMDraft: Double? {
        let normalized = creativeBPMDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let bpm = Double(normalized), bpm.isFinite else {
            return nil
        }
        return bpm
    }

    private var isCreativeBPMDraftValid: Bool {
        guard let bpm = parsedCreativeBPMDraft else {
            return false
        }
        return (40...260).contains(bpm)
    }

    private func syncCreativeBPMDraft() {
        if let bpm = model.creativeTrackPreparation.bpmOverride ?? model.creativeEffectiveBPM {
            creativeBPMDraft = String(format: "%.1f", bpm)
        } else {
            creativeBPMDraft = ""
        }
    }

    private func progress(_ elapsedSec: Double, durationSec: Double) -> Double {
        guard elapsedSec.isFinite, durationSec.isFinite, durationSec > 0 else {
            return 0
        }
        return min(1, max(0, elapsedSec / durationSec))
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else {
            return false
        }

        let group = DispatchGroup()
        let accumulator = DroppedFileURLAccumulator()

        for provider in fileURLProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = Self.droppedFileURL(from: item) {
                    accumulator.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = accumulator.snapshot()
            if urls.isEmpty {
                model.notice = "No supported audio files"
            } else {
                model.openDroppedItemsAsSet(urls)
            }
        }

        return true
    }

    nonisolated private static func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url.isFileURL ? url : nil
        }

        if let data = item as? Data,
           let text = String(data: data, encoding: .utf8),
           let url = URL(string: text) {
            return url.isFileURL ? url : nil
        }

        if let string = item as? String,
           let url = URL(string: string) {
            return url.isFileURL ? url : nil
        }

        if let string = item as? NSString,
           let url = URL(string: string as String) {
            return url.isFileURL ? url : nil
        }

        return nil
    }
}

private extension ContentView {
    func waveformRenderPoints(for analysis: TrackAnalysis?, maxCount: Int = 180) -> [WaveformRenderPoint] {
        guard let analysis else {
            return []
        }

        if !analysis.waveformDetail.isEmpty {
            let stride = max(1, Int(ceil(Double(analysis.waveformDetail.count) / Double(maxCount))))
            return analysis.waveformDetail.enumerated().compactMap { index, point in
                guard index % stride == 0 else {
                    return nil
                }
                let band = spectralBand(
                    for: analysis,
                    sourceIndex: index,
                    sourceCount: analysis.waveformDetail.count
                )
                return WaveformRenderPoint(
                    id: index,
                    timeSec: point.timeSec,
                    peak: clampedUnit(point.peak),
                    rms: clampedUnit(point.rms),
                    low: clampedUnit(band?.low ?? point.rms),
                    mid: clampedUnit(band?.mid ?? point.peak),
                    high: clampedUnit(band?.high ?? max(0, point.peak - point.rms))
                )
            }
            .prefix(maxCount)
            .map { $0 }
        }

        if !analysis.waveformPeaks.isEmpty {
            let stride = max(1, Int(ceil(Double(analysis.waveformPeaks.count) / Double(maxCount))))
            return analysis.waveformPeaks.enumerated().compactMap { index, point in
                guard index % stride == 0 else {
                    return nil
                }
                let band = spectralBand(
                    for: analysis,
                    sourceIndex: index,
                    sourceCount: analysis.waveformPeaks.count
                )
                return WaveformRenderPoint(
                    id: index,
                    timeSec: point.timeSec,
                    peak: clampedUnit(point.peak),
                    rms: clampedUnit(point.rms),
                    low: clampedUnit(band?.low ?? point.rms),
                    mid: clampedUnit(band?.mid ?? point.peak),
                    high: clampedUnit(band?.high ?? max(0, point.peak - point.rms))
                )
            }
            .prefix(maxCount)
            .map { $0 }
        }

        return []
    }

    func spectralBand(
        for analysis: TrackAnalysis,
        sourceIndex: Int,
        sourceCount: Int
    ) -> SpectralBandPoint? {
        guard !analysis.spectralBands.isEmpty, sourceCount > 0 else {
            return nil
        }
        let ratio = Double(sourceIndex) / Double(max(1, sourceCount - 1))
        let bandIndex = Int((ratio * Double(analysis.spectralBands.count - 1)).rounded())
        return analysis.spectralBands[min(max(0, bandIndex), analysis.spectralBands.count - 1)]
    }

    func drawWaveformBackground(in context: GraphicsContext, size: CGSize) {
        let fullRect = CGRect(origin: .zero, size: size)
        context.fill(
            roundedRectPath(fullRect, radius: 7),
            with: .color(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )

        drawHorizontalLine(
            y: size.height * 0.5,
            color: Color.primary.opacity(0.16),
            lineWidth: 1,
            in: context,
            size: size
        )
        drawHorizontalLine(
            y: size.height * 0.25,
            color: Color.primary.opacity(0.06),
            lineWidth: 1,
            in: context,
            size: size
        )
        drawHorizontalLine(
            y: size.height * 0.75,
            color: Color.primary.opacity(0.06),
            lineWidth: 1,
            in: context,
            size: size
        )
    }

    func drawWaveformPlaceholder(
        in context: GraphicsContext,
        size: CGSize,
        label: String
    ) {
        let resolved = context.resolve(
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        )
        context.draw(resolved, at: CGPoint(x: size.width * 0.5, y: size.height * 0.5), anchor: .center)
    }

    func drawWaveformPoints(
        _ points: [WaveformRenderPoint],
        in context: GraphicsContext,
        size: CGSize,
        isNextDeck: Bool
    ) {
        guard !points.isEmpty, size.width > 0, size.height > 0 else {
            return
        }

        let count = max(1, points.count)
        let step = size.width / CGFloat(count)
        let barWidth = max(1.4, min(4.4, step * 0.58))
        let centerY = size.height * 0.52
        let upperMaxHeight = size.height * 0.42
        let lowerMaxHeight = size.height * 0.34

        for (index, point) in points.enumerated() {
            let x = step * CGFloat(index) + (step - barWidth) * 0.5
            let peakHeight = max(5, CGFloat(point.peak) * upperMaxHeight)
            let rmsHeight = max(3, CGFloat(point.rms) * lowerMaxHeight)
            let highAlpha = 0.28 + clampedUnit(point.high) * 0.48
            let midAlpha = 0.25 + clampedUnit(point.mid) * 0.42
            let lowAlpha = 0.24 + clampedUnit(point.low) * 0.48

            let upperColor = isNextDeck
                ? Color.cyan.opacity(midAlpha)
                : Color.orange.opacity(midAlpha)
            let upperAccent = isNextDeck
                ? Color.teal.opacity(highAlpha)
                : Color.red.opacity(highAlpha)
            let lowerColor = Color.accentColor.opacity(lowAlpha)

            let upperRect = CGRect(
                x: x,
                y: max(2, centerY - peakHeight),
                width: barWidth,
                height: peakHeight
            )
            let lowerRect = CGRect(
                x: x,
                y: centerY + 2,
                width: barWidth,
                height: rmsHeight
            )

            context.fill(roundedRectPath(upperRect, radius: barWidth * 0.5), with: .color(upperColor))
            context.fill(roundedRectPath(upperRect.insetBy(dx: 0, dy: peakHeight * 0.35), radius: barWidth * 0.5), with: .color(upperAccent))
            context.fill(roundedRectPath(lowerRect, radius: barWidth * 0.5), with: .color(lowerColor))
        }
    }

    func drawBarMarkers(
        _ markers: [BarMarker],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for marker in markers where marker.index % 4 == 0 {
            let x = xPosition(timeSec: marker.startSec, durationSec: durationSec, width: size.width)
            let isPhrase = marker.index % 8 == 0
            drawVerticalLine(
                x: x,
                yStart: 0,
                yEnd: size.height,
                color: Color.primary.opacity(isPhrase ? 0.18 : 0.08),
                lineWidth: isPhrase ? 1.2 : 0.8,
                in: context
            )
        }
    }

    func drawPhraseMarkers(
        _ markers: [PhraseMarker],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for marker in markers.prefix(64) {
            let x = xPosition(timeSec: marker.startSec, durationSec: durationSec, width: size.width)
            drawVerticalLine(
                x: x,
                yStart: 0,
                yEnd: size.height,
                color: Color.white.opacity(0.12 + clampedUnit(marker.confidence) * 0.2),
                lineWidth: 1.4,
                in: context
            )
        }
    }

    func drawTransientMarkers(
        _ markers: [TransientMarker],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for marker in markers.prefix(90) {
            let x = xPosition(timeSec: marker.timeSec, durationSec: durationSec, width: size.width)
            let strength = clampedUnit(marker.strength)
            let markerHeight = size.height * CGFloat(0.28 + strength * 0.46)
            let yStart = (size.height - markerHeight) * 0.5
            drawVerticalLine(
                x: x,
                yStart: yStart,
                yEnd: yStart + markerHeight,
                color: Color.white.opacity(0.12 + strength * 0.42),
                lineWidth: 0.9,
                in: context
            )
        }
    }

    func drawPreparationCueMarkers(
        _ cues: [TrackPreparationCue],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for cue in cues.prefix(24) {
            let x = xPosition(timeSec: cue.timeSec, durationSec: durationSec, width: size.width)
            drawVerticalLine(
                x: x,
                yStart: 0,
                yEnd: size.height,
                color: cueColor(cue.kind).opacity(0.9),
                lineWidth: 1.8,
                in: context
            )

            let label = cue.kind.displayName.prefix(1).uppercased()
            let rect = CGRect(
                x: min(max(4, x + 4), max(4, size.width - 24)),
                y: size.height - 22,
                width: 20,
                height: 16
            )
            context.fill(roundedRectPath(rect, radius: 8), with: .color(cueColor(cue.kind).opacity(0.92)))
            let resolved = context.resolve(
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.black)
            )
            context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    func drawWaveformCursor(
        timeSec: Double,
        durationSec: Double,
        label: String,
        color: Color,
        in context: GraphicsContext,
        size: CGSize,
        alignTrailing: Bool = false
    ) {
        guard durationSec > 0 else {
            return
        }

        let x = xPosition(timeSec: timeSec, durationSec: durationSec, width: size.width)
        drawVerticalLine(
            x: x,
            yStart: 0,
            yEnd: size.height,
            color: color.opacity(0.9),
            lineWidth: label == "PLAY" ? 2.2 : 1.8,
            in: context
        )

        let width: CGFloat = label == "PLAY" ? 36 : 30
        let labelCenterX = alignTrailing
            ? min(max(width * 0.5 + 3, x - width * 0.5), size.width - width * 0.5 - 3)
            : min(max(width * 0.5 + 3, x + width * 0.5), size.width - width * 0.5 - 3)
        let rect = CGRect(x: labelCenterX - width * 0.5, y: 4, width: width, height: 16)

        context.fill(roundedRectPath(rect, radius: 8), with: .color(color.opacity(0.95)))
        let resolved = context.resolve(
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundColor(.black)
        )
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    func cueColor(_ kind: TrackPreparationCueKind) -> Color {
        switch kind {
        case .intro:
            return .cyan
        case .drop:
            return .orange
        case .breakdown:
            return .purple
        case .outro:
            return .red
        case .custom:
            return .yellow
        }
    }

    func drawHorizontalLine(
        y: CGFloat,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext,
        size: CGSize
    ) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    func drawVerticalLine(
        x: CGFloat,
        yStart: CGFloat,
        yEnd: CGFloat,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext
    ) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: yStart))
        path.addLine(to: CGPoint(x: x, y: yEnd))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: radius, height: radius)
        )
        return path
    }

    func xPosition(timeSec: Double, durationSec: Double, width: CGFloat) -> CGFloat {
        guard timeSec.isFinite, durationSec.isFinite, durationSec > 0 else {
            return 0
        }
        return min(width, max(0, CGFloat(timeSec / durationSec) * width))
    }

    func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(1, max(0, value))
    }
}
