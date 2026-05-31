import BeatDropperCore
import SwiftUI

extension ContentView {
    var playlistPane: some View {
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
        .padding(.top, model.workspaceMode == .creative ? 20 : 18)
        .padding(.bottom, 16)
    }

    var playlistEditActions: some View {
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
    var playlistContent: some View {
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

    var maintenanceActions: some View {
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

    var libraryPane: some View {
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
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    var libraryContent: some View {
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

    var libraryEmptyTitle: String {
        model.librarySearchText.isEmpty ? "No Library Tracks" : "No Matches"
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

    var savedSetsCompactLayout: some View {
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
    var savedSetActions: some View {
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

    var shouldShowSavedSetActions: Bool {
        shouldShowSaveSetAction || model.canLoadSelectedSet
    }

    var shouldShowSaveSetAction: Bool {
        !model.playlist.isEmpty || !model.userPlaylistNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var savedSetSelection: Binding<String> {
        Binding(
            get: { model.selectedUserPlaylistId },
            set: { model.selectUserPlaylist($0) }
        )
    }

    func rowNumber(for imported: ImportedTrack) -> String {
        guard let index = model.playlist.firstIndex(where: { $0.id == imported.id }) else {
            return "--"
        }
        return String(index + 1)
    }
}
