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

struct ContentView: View {
    @EnvironmentObject private var model: BeatDropperAppModel
    @State private var isFileDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if model.workspaceMode == .playing {
                Divider()
                mixMonitor
            }
            Divider()
            workspaceContent
            Divider()
            transportBar
        }
        .frame(minWidth: 980, minHeight: 680)
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

            Button("Add Tracks", systemImage: "plus.circle") {
                model.addTracks()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(model.playlist.isEmpty)
            .help("Add tracks to the current set")

            Button("Import Folder", systemImage: "folder.badge.plus") {
                model.importFolder()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help("Import a music folder into the library")

            Button("Library", systemImage: "rectangle.stack") {
                model.workspaceMode = .creative
                model.isLibraryBrowserVisible = true
            }
            .help("Show library browser")

            Button("Inspector", systemImage: model.isInspectorVisible ? "sidebar.right" : "sidebar.right") {
                model.isInspectorVisible.toggle()
            }
            .keyboardShortcut("3", modifiers: [.command])
            .help(model.isInspectorVisible ? "Hide mix inspector" : "Show mix inspector")

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Primary toolbar")
    }

    @ViewBuilder
    private var workspaceContent: some View {
        HSplitView {
            playlistPane
                .frame(minWidth: model.workspaceMode == .playing ? 620 : 460)

            if model.workspaceMode == .creative {
                if model.isLibraryBrowserVisible {
                    libraryPane
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 500)
                }

                creativePane
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
            } else if model.isInspectorVisible {
                inspectorPane
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            }
        }
    }

    private var mixMonitor: some View {
        HStack(spacing: 12) {
            deckPanel(
                title: "Current Deck",
                track: model.currentDeckDisplayTrack,
                analysis: model.currentDeckAnalysis,
                status: model.currentDeckDisplayStatus,
                elapsedSec: model.audioEngine.currentTrack != nil ? model.audioEngine.elapsedSec : nil,
                meter: model.audioEngine.currentDeckMeter
            )

            mixPlanMonitor
                .frame(width: 300)

            deckPanel(
                title: "Next Deck",
                track: model.nextDeckDisplayTrack,
                analysis: model.nextDeckAnalysis,
                status: model.nextDeckDisplayStatus,
                elapsedSec: nil,
                meter: model.audioEngine.nextDeckMeter
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityLabel("Live mix monitor")
    }

    private func deckPanel(
        title: String,
        track: Track?,
        analysis: TrackAnalysis?,
        status: String,
        elapsedSec: Double?,
        meter: AudioLevelMeter
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(track?.title ?? "No track")
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 14) {
                metric("BPM", track?.bpm.map { String(Int($0.rounded())) } ?? "--")
                metric("Length", track.map { formatDuration($0.durationSec) } ?? "--")
                metric("Quality", analysis.map { "\(Int(($0.analysisConfidence * 100).rounded()))%" } ?? "--")
            }

            outputLevelMeter("LEVEL", meter)

            if let track, let elapsedSec {
                ProgressView(value: progress(elapsedSec, durationSec: track.durationSec))
                    .controlSize(.small)
                Text("\(formatDuration(elapsedSec)) / \(formatDuration(track.durationSec))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView(value: 0)
                    .controlSize(.small)
                    .opacity(0.35)
                Text(track == nil ? "--" : "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        )
    }

    private var mixPlanMonitor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI MIX")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isPlanningMix {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let plan = model.currentMixPlan {
                Text(model.scheduledMixCountdownSec.map { "In \(formatDuration($0))" } ?? "Ready")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 14) {
                    metric("Out", formatDuration(plan.transitionStartSec))
                    metric("In", formatDuration(plan.nextTrackStartOffsetSec))
                    metric("Conf", "\(Int((plan.confidence * 100).rounded()))%")
                }
            } else {
                Text(model.isPlanningMix ? "Planning" : "--")
                    .font(.headline)
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 140, alignment: .topLeading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        )
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

    private var playlistPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playlist")
                        .font(.title3.weight(.semibold))
                    Text("\(model.playlist.count) tracks · \(formatDuration(model.totalDurationSec)) total")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Button("", systemImage: "arrow.up") {
                    model.moveSelectedTrack(offset: -1)
                }
                .help("Move selected track up")
                .accessibilityLabel("Move selected track up")
                .disabled(!model.canMoveSelectedTrackUp)

                Button("", systemImage: "arrow.down") {
                    model.moveSelectedTrack(offset: 1)
                }
                .help("Move selected track down")
                .accessibilityLabel("Move selected track down")
                .disabled(!model.canMoveSelectedTrackDown)

                Button("", systemImage: "trash") {
                    model.removeSelectedTrack()
                }
                .help("Remove selected track")
                .accessibilityLabel("Remove selected track")
                .disabled(!model.canRemoveSelectedTrack)

                Button("", systemImage: "text.badge.xmark") {
                    model.clearPlaylist()
                }
                .help("Clear playlist")
                .accessibilityLabel("Clear playlist")
                .disabled(!model.canClearPlaylist)
            }

            Table(model.playlist, selection: $model.selectedTrackID) {
                TableColumn("#") { imported in
                    Text(rowNumber(for: imported))
                        .foregroundStyle(.secondary)
                }
                .width(44)

                TableColumn("Track") { imported in
                    HStack(spacing: 6) {
                        if !model.isTrackAvailable(imported) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        Text(imported.track.title)
                            .lineLimit(1)
                    }
                    .foregroundStyle(model.isTrackAvailable(imported) ? .primary : .secondary)
                }

                TableColumn("BPM") { imported in
                    Text(imported.track.bpm.map { String(Int($0.rounded())) } ?? "--")
                        .monospacedDigit()
                }
                .width(60)

                TableColumn("Length") { imported in
                    Text(formatDuration(imported.track.durationSec))
                        .monospacedDigit()
                }
                .width(78)
            }
            .overlay {
                if model.playlist.isEmpty {
                    ContentUnavailableView(
                        "No Tracks",
                        systemImage: "music.note"
                    )
                }
            }
            .accessibilityLabel("Current playlist")
        }
        .padding(16)
    }

    private var creativePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Creative")
                    .font(.title3.weight(.semibold))

                savedSetsPanel

                maintenancePanel

                if model.isInspectorVisible {
                    Divider()
                    inspectorContent
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityLabel("Creative workspace")
    }

    private var maintenancePanel: some View {
        GroupBox("Library") {
            VStack(alignment: .leading, spacing: 10) {
                Button("Rescan", systemImage: "arrow.triangle.2.circlepath") {
                    model.rescanLibraryFolders()
                }
                .disabled(!model.hasLibrarySourceFolders)
                .help("Rescan imported library folders")

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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.title3.weight(.semibold))
                    Text("\(model.libraryBrowserTracks.count) tracks")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("", systemImage: "xmark") {
                    model.isLibraryBrowserVisible = false
                }
                .help("Hide library browser")
                .accessibilityLabel("Hide library browser")
            }

            TextField("Search library", text: $model.librarySearchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search library")

            Button("Add to Set", systemImage: "plus.circle") {
                model.addSelectedLibraryTrackToPlaylist()
            }
            .disabled(!model.canAddSelectedLibraryTrackToPlaylist)
            .help("Add selected library track to the current set")

            Table(model.filteredLibraryTracks, selection: $model.selectedLibraryTrackID) {
                TableColumn("Track") { row in
                    HStack(spacing: 6) {
                        if !model.isTrackAvailable(row) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        Text(row.track.title)
                            .lineLimit(1)
                    }
                    .foregroundStyle(model.isTrackAvailable(row) ? .primary : .secondary)
                }

                TableColumn("BPM") { row in
                    Text(row.track.bpm.map { String(Int($0.rounded())) } ?? "--")
                        .monospacedDigit()
                }
                .width(56)

                TableColumn("Source") { row in
                    Text(row.sourceDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(110)
            }
            .overlay {
                if model.filteredLibraryTracks.isEmpty {
                    ContentUnavailableView(
                        "No Library Tracks",
                        systemImage: "rectangle.stack"
                    )
                }
            }
            .accessibilityLabel("Library browser")
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var savedSetsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Saved Sets", systemImage: "music.note.list")
                    .font(.headline)

                Spacer()

                Text("\(model.userPlaylists.count) saved")
                    .foregroundStyle(.secondary)
            }

            Picker("Saved Set", selection: savedSetSelection) {
                Text("New Saved Set").tag("")
                ForEach(model.userPlaylists) { playlist in
                    Text(playlist.name).tag(playlist.id)
                }
            }
            .labelsHidden()

            TextField("Set name", text: $model.userPlaylistNameDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button("Save Current", systemImage: "square.and.arrow.down") {
                    model.saveCurrentSet()
                }
                .disabled(!model.canSaveCurrentSet)
                .help("Save the current set as a taste playlist")

                Button("Load", systemImage: "arrow.down.doc") {
                    model.loadSelectedSavedSet()
                }
                .disabled(!model.canLoadSelectedSet)
                .help("Load the selected saved set")
            }

            HStack(spacing: 8) {
                Button("Rename", systemImage: "pencil") {
                    model.renameSelectedSavedSet()
                }
                .disabled(!model.canLoadSelectedSet || model.userPlaylistNameDraft.isEmpty)
                .help("Rename the selected saved set")

                Button("Delete", systemImage: "trash") {
                    model.deleteSelectedSavedSet()
                }
                .disabled(!model.canLoadSelectedSet)
                .help("Delete the selected saved set")
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
            Text("Mix Pair Inspector")
                .font(.title3.weight(.semibold))

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

    private var transportBar: some View {
        HStack {
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

            Button("Plan Mix", systemImage: "sparkles") {
                model.requestMixPlanForNextTrack()
            }
            .disabled(!model.canRequestMixPlan)
            .help("Request an AI mix plan for the next track")

            Button("", systemImage: "xmark.circle") {
                model.cancelMixPlan()
            }
            .help("Cancel AI mix plan")
            .accessibilityLabel("Cancel AI mix plan")
            .disabled(!model.canCancelMixPlan)

            Button("", systemImage: "backward.end") {
                model.playPreviousTrack()
            }
            .help("Crossfade to previous track")
            .accessibilityLabel("Crossfade to previous track")
            .disabled(!model.hasPreviousTrack)

            Button("", systemImage: model.isPlaybackActive ? "pause.fill" : "play.fill") {
                model.playPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaybackActive ? "Pause playback" : "Start playback")
            .accessibilityLabel(model.isPlaybackActive ? "Pause playback" : "Start playback")
            .disabled(!model.canUseTransportPlayPause)

            Button("", systemImage: "forward.end") {
                model.playNextTrack()
            }
            .help("Crossfade to next track")
            .accessibilityLabel("Crossfade to next track")
            .disabled(!model.hasNextTrack)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityLabel("Transport controls")
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
