import BeatDropperApplication
import SwiftUI

extension ContentView {
    var playlistPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(navigation.workspaceMode == .playing ? "Set Flow" : "Set Builder")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(library.playlist.count) tracks · \(formatDuration(library.totalDurationSec)) total")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if navigation.workspaceMode == .creative {
                savedSetsManagementBar
                creativeEnergyFlow
            } else {
                playingSetFlowSummary
            }

            if !library.playlist.isEmpty {
                playlistEditActions
            }

            playlistContent
                .frame(minHeight: 120, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, navigation.workspaceMode == .creative ? 20 : 18)
        .padding(.bottom, 16)
    }

    var playlistEditActions: some View {
        HStack(spacing: 8) {
            centeredIconButton(
                systemImage: "arrow.up",
                help: "Move selected track up",
                accessibilityLabel: "Move selected track up"
            ) {
                model.libraryActions.moveSelectedTrack(offset: -1)
            }
            .disabled(!library.canMoveSelectedTrackUp)

            centeredIconButton(
                systemImage: "arrow.down",
                help: "Move selected track down",
                accessibilityLabel: "Move selected track down"
            ) {
                model.libraryActions.moveSelectedTrack(offset: 1)
            }
            .disabled(!library.canMoveSelectedTrackDown)

            centeredIconButton(
                systemImage: "trash",
                help: "Remove selected track",
                accessibilityLabel: "Remove selected track"
            ) {
                model.libraryActions.removeSelectedTrack()
            }
            .disabled(!library.canRemoveSelectedTrack)

            centeredIconButton(
                systemImage: "text.badge.xmark",
                help: "Clear playlist",
                accessibilityLabel: "Clear playlist"
            ) {
                model.libraryActions.clearPlaylist()
            }
            .disabled(!library.canClearPlaylist)
        }
    }

    @ViewBuilder
    var playlistContent: some View {
        if library.playlist.isEmpty {
            emptyPanel("No Tracks", systemImage: "music.note")
                .accessibilityLabel("Current playlist")
        } else {
            Table(library.playlist, selection: playlistSelection) {
                TableColumn("#") { imported in
                    Text(rowNumber(for: imported))
                        .foregroundStyle(.secondary)
                }
                .width(34)

                TableColumn("Track") { imported in
                    HStack(spacing: 6) {
                        if !library.isAvailable(imported) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        Text(imported.track.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(library.isAvailable(imported) ? .primary : .secondary)
                }

                TableColumn("BPM") { imported in
                    Text(library.displayBPM(for: imported))
                        .monospacedDigit()
                }
                .width(52)

                TableColumn("State") { imported in
                    Text(setFlowState(for: imported))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(setFlowStateColor(for: imported))
                }
                .width(70)

                TableColumn("Length") { imported in
                    Text(formatDuration(imported.track.durationSec))
                        .monospacedDigit()
                }
                .width(64)
            }
            .accessibilityLabel("Current playlist")
        }
    }

    var playingSetFlowSummary: some View {
        HStack(spacing: 8) {
            setFlowSummaryMetric(
                "Current",
                playing.currentDisplayTrack?.title ?? "Not loaded",
                systemImage: "play.circle.fill"
            )
            setFlowSummaryMetric(
                "Next",
                playing.nextDisplayTrack?.title ?? "Not queued",
                systemImage: "forward.end.circle"
            )
            setFlowSummaryMetric(
                "Remaining",
                "\(remainingSetFlowTrackCount) tracks",
                systemImage: "list.number"
            )
        }
        .accessibilityLabel("Compact set flow queue summary")
    }

    var creativeEnergyFlow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Energy Flow", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(library.playlist.isEmpty ? "Add tracks to shape the set" : "Analysis profile by set order")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if library.playlist.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .separatorColor).opacity(0.18))
                    .frame(height: 32)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(Array(library.playlist.enumerated()), id: \.element.id) { index, imported in
                            let energy = setEnergyLevel(for: imported)
                            Button {
                                model.libraryActions.selectPlaylistTrack(imported.id)
                            } label: {
                                VStack(spacing: 3) {
                                    Capsule()
                                        .fill(library.selectedTrackID == imported.id ? Color.accentColor : Color.accentColor.opacity(0.42))
                                        .frame(width: 18, height: 8 + (energy * 24))
                                    Text("\(index + 1)")
                                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Select \(imported.track.title)")
                            .accessibilityLabel("Track \(index + 1), \(imported.track.title), energy \(Int((energy * 100).rounded())) percent")
                        }
                    }
                    .frame(minHeight: 44, alignment: .bottom)
                }
            }
        }
        .padding(9)
        .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.24), lineWidth: 1)
        )
        .accessibilityLabel("Set energy flow")
    }

    func setEnergyLevel(for imported: ImportedTrack) -> Double {
        guard let profile = library.analysesByTrackID[imported.id]?.energyProfile,
              !profile.isEmpty else {
            return 0.2
        }
        return min(1, max(0, profile.reduce(0, +) / Double(profile.count)))
    }

    func setFlowSummaryMetric(_ label: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }

    var remainingSetFlowTrackCount: Int {
        guard let currentID = playing.session.currentTrack?.id,
              let index = library.playlist.firstIndex(where: { $0.track.id == currentID }) else {
            return library.playlist.count
        }
        return max(0, library.playlist.count - index - 1)
    }

    func setFlowState(for imported: ImportedTrack) -> String {
        if !library.isAvailable(imported) {
            return "Missing"
        }
        if playing.session.currentTrack?.id == imported.track.id {
            return "Current"
        }
        if playing.session.queuedTrack?.id == imported.track.id {
            return "Next"
        }
        if library.analyzingTrackIDs.contains(imported.id) {
            return "Analyzing"
        }
        return library.analysesByTrackID[imported.id] == nil ? "Pending" : "Ready"
    }

    func setFlowStateColor(for imported: ImportedTrack) -> Color {
        switch setFlowState(for: imported) {
        case "Missing": return .red
        case "Current": return .orange
        case "Next": return .cyan
        case "Analyzing": return .accentColor
        default: return .secondary
        }
    }

    var maintenanceActions: some View {
        HStack(spacing: 8) {
            if library.hasSourceFolders {
                Button("Rescan", systemImage: "arrow.triangle.2.circlepath") {
                    model.libraryActions.rescanLibraryFolders()
                }
                .help("Rescan imported library folders")
            }

            if library.hasMissingSourceFolders {
                Menu("Relink", systemImage: "link") {
                    ForEach(library.missingSourceFolders) { folder in
                        Button(folder.displayName, systemImage: "folder.badge.questionmark") {
                            model.libraryActions.relinkMissingSourceFolder(folder)
                        }
                    }
                }
                .help("Relink missing library folders")
            }

            if library.selectedTrackNeedsRelink {
                Button("Relink File", systemImage: "link") {
                    model.libraryActions.relinkSelectedTrack()
                }
            }
        }
        .controlSize(.small)
    }

    var libraryPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(library.browserTracks.count) tracks")
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
                    navigation.isLibraryBrowserVisible = false
                }
            }

            if !library.browserTracks.isEmpty || !library.searchText.isEmpty {
                TextField("Search library", text: librarySearchBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search library")
            }

            if library.canAddSelectedLibraryTrackToPlaylist {
                Button("Add to Set", systemImage: "plus.circle") {
                    model.libraryActions.addSelectedLibraryTrackToPlaylist()
                }
                .help("Add selected library track to the current set")
            }

            libraryContent
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    var libraryContent: some View {
        if library.filteredBrowserTracks.isEmpty {
            emptyPanel(libraryEmptyTitle, systemImage: "rectangle.stack")
                .accessibilityLabel("Library browser")
        } else {
            Table(library.filteredBrowserTracks, selection: librarySelection) {
                TableColumn("Track") { row in
                    HStack(spacing: 6) {
                        if !library.isAvailable(row) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                        Text(row.track.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(library.isAvailable(row) ? .primary : .secondary)
                }

                TableColumn("BPM") { row in
                    Text(library.displayBPM(for: row))
                        .monospacedDigit()
                }
                .width(48)
            }
            .accessibilityLabel("Library browser")
        }
    }

    var libraryEmptyTitle: String {
        library.searchText.isEmpty ? "No Library Tracks" : "No Matches"
    }

    func emptyPanel(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    var savedSetsManagementBar: some View {
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

    var savedSetsWideLayout: some View {
        HStack(spacing: 10) {
            Label("Saved Sets", systemImage: "music.note.list")
                .font(.headline)
                .lineLimit(1)
                .frame(width: 126, alignment: .leading)

            Picker("Saved Set", selection: savedSetSelection) {
                Text("New Saved Set").tag("")
                ForEach(library.userPlaylists) { playlist in
                    Text(playlist.name).tag(playlist.id)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            TextField("Set name", text: $library.userPlaylistNameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)

            savedSetActions

            Spacer(minLength: 0)

            Text("\(library.userPlaylists.count) saved")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    var savedSetsCompactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Saved Sets", systemImage: "music.note.list")
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 10) {
                Picker("Saved Set", selection: savedSetSelection) {
                    Text("New Saved Set").tag("")
                    ForEach(library.userPlaylists) { playlist in
                        Text(playlist.name).tag(playlist.id)
                    }
                }
                .labelsHidden()

                TextField("Set name", text: $library.userPlaylistNameDraft)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                savedSetActions
                Spacer()
                Text("\(library.userPlaylists.count) saved")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    var savedSetActions: some View {
        if shouldShowSavedSetActions {
            HStack(spacing: 8) {
                if shouldShowSaveSetAction {
                    Button("Save", systemImage: "square.and.arrow.down") {
                        model.libraryActions.saveCurrentSet()
                    }
                    .disabled(!library.canSaveCurrentSet)
                    .help("Save the current set as a taste playlist")
                }

                if library.canLoadSelectedSet {
                    Button("Load", systemImage: "arrow.down.doc") {
                        model.libraryActions.loadSelectedSavedSet()
                    }
                    .help("Load the selected saved set")

                    Button("Rename", systemImage: "pencil") {
                        model.libraryActions.renameSelectedSavedSet()
                    }
                    .disabled(library.userPlaylistNameDraft.isEmpty)
                    .help("Rename the selected saved set")

                    Button("Delete", systemImage: "trash") {
                        model.libraryActions.deleteSelectedSavedSet()
                    }
                    .help("Delete the selected saved set")
                }
            }
            .controlSize(.small)
        }
    }

    var shouldShowSavedSetActions: Bool {
        shouldShowSaveSetAction || library.canLoadSelectedSet
    }

    var shouldShowSaveSetAction: Bool {
        !library.playlist.isEmpty || !library.userPlaylistNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var savedSetSelection: Binding<String> {
        Binding(
            get: { library.selectedUserPlaylistID },
            set: { model.libraryActions.selectUserPlaylist($0) }
        )
    }

    var playlistSelection: Binding<ImportedTrack.ID?> {
        Binding(
            get: { library.selectedTrackID },
            set: { trackID in model.libraryActions.selectPlaylistTrack(trackID) }
        )
    }

    var librarySelection: Binding<ImportedTrack.ID?> {
        Binding(
            get: { library.selectedLibraryTrackID },
            set: { trackID in model.libraryActions.selectLibraryTrack(trackID) }
        )
    }

    var librarySearchBinding: Binding<String> {
        Binding(
            get: { library.searchText },
            set: { text in library.updateSearchText(text) }
        )
    }

    func rowNumber(for imported: ImportedTrack) -> String {
        guard let index = library.playlist.firstIndex(where: { $0.id == imported.id }) else {
            return "--"
        }
        return String(index + 1)
    }
}
