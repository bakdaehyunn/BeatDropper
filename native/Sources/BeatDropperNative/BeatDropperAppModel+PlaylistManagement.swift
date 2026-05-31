import BeatDropperCore
import Foundation

extension BeatDropperAppModel {
    func replacePlaylist(with imported: [ImportedTrack], sourceFolderURL: URL? = nil) {
        guard !imported.isEmpty else {
            notice = "Canceled"
            return
        }

        let resolved = upsertLibraryRecords(for: imported, sourceFolderURL: sourceFolderURL)
        audioEngine.stop()
        stopMixPlanScheduler()
        playlist = resolved
        selectedTrackID = resolved.first?.id
        clearCurrentMixPlan()
        persistLibraryState()
        refreshAnalyses(for: resolved)
        syncAIMixAfterPlaylistMutation()
        notice = "Loaded \(resolved.count) tracks"
    }

    func appendPlaylist(with imported: [ImportedTrack]) {
        guard !imported.isEmpty else {
            notice = "Canceled"
            return
        }

        let resolved = upsertLibraryRecords(for: imported, sourceFolderURL: nil)
        playlist.append(contentsOf: resolved)
        selectedTrackID = selectedTrackID ?? resolved.first?.id
        persistLibraryState()
        refreshAnalyses(for: resolved)
        syncAIMixAfterPlaylistMutation()
        notice = "Added \(resolved.count) tracks"
    }

    func addSelectedLibraryTrackToPlaylist() {
        guard let selectedLibraryTrack else {
            notice = "Select a library track first"
            return
        }
        addLibraryTrackToPlaylist(selectedLibraryTrack)
    }

    func addLibraryTrackToPlaylist(_ imported: ImportedTrack) {
        if playlist.contains(where: { $0.id == imported.id }) {
            selectedTrackID = imported.id
            notice = "Already in current set"
            return
        }

        playlist.append(imported)
        selectedTrackID = imported.id
        clearCurrentMixPlan()
        persistLibraryState()
        refreshAnalyses(for: [imported])
        syncAIMixAfterPlaylistMutation()
        notice = "Added \(imported.track.title) to set"
    }

    func removeSelectedTrack() {
        guard let selectedTrackID else {
            return
        }

        playlist.removeAll { $0.id == selectedTrackID }
        self.selectedTrackID = playlist.first?.id
        clearCurrentMixPlan()
        persistLibraryState()
        syncAIMixAfterPlaylistMutation()
        notice = "Removed track"
    }

    func clearPlaylist() {
        audioEngine.stop()
        stopMixPlanScheduler()
        playlist.removeAll()
        selectedTrackID = nil
        clearCurrentMixPlan()
        isAIMixEnabled = false
        persistLibraryState()
        notice = "Cleared playlist"
    }

    func moveSelectedTrack(offset: Int) {
        guard
            let selectedTrackID,
            let currentIndex = playlist.firstIndex(where: { $0.id == selectedTrackID })
        else {
            return
        }

        let targetIndex = max(0, min(playlist.count - 1, currentIndex + offset))
        guard currentIndex != targetIndex else {
            return
        }

        let item = playlist.remove(at: currentIndex)
        playlist.insert(item, at: targetIndex)
        clearCurrentMixPlan()
        persistLibraryState()
        syncAIMixAfterPlaylistMutation()
    }

    func selectUserPlaylist(_ id: String) {
        selectedUserPlaylistId = id
        userPlaylistNameDraft = selectedUserPlaylist?.name ?? ""
        persistLibraryState()
    }

    func saveCurrentSet() {
        let name = normalizeUserPlaylistName(userPlaylistNameDraft)
        guard !name.isEmpty else {
            notice = "Name the saved set first"
            return
        }
        guard !playlist.isEmpty else {
            notice = "Add tracks before saving a set"
            return
        }

        let now = timestamp()
        let trackIds = playlist.map(\.id)

        if let index = userPlaylists.firstIndex(where: { $0.id == selectedUserPlaylistId }) {
            let current = userPlaylists[index]
            userPlaylists[index] = UserPlaylist(
                id: current.id,
                name: name,
                trackIds: trackIds,
                createdAt: current.createdAt,
                updatedAt: now
            )
            notice = "Saved \(name)"
        } else {
            let playlist = UserPlaylist(
                id: UUID().uuidString,
                name: name,
                trackIds: trackIds,
                createdAt: now,
                updatedAt: now
            )
            userPlaylists.append(playlist)
            selectedUserPlaylistId = playlist.id
            notice = "Saved \(name)"
        }

        persistLibraryState()
    }

    func loadSelectedSavedSet() {
        guard let selectedUserPlaylist else {
            notice = "Choose a saved set first"
            return
        }

        let recordsById = Dictionary(uniqueKeysWithValues: libraryRecords.map { ($0.id, $0) })
        let restored = selectedUserPlaylist.trackIds.compactMap { id in
            recordsById[id].map(ImportedTrack.init(record:))
        }

        guard !restored.isEmpty else {
            notice = "Saved set has no available tracks"
            return
        }

        audioEngine.stop()
        playlist = restored
        selectedTrackID = restored.first?.id
        selectFirstAvailableTrackIfNeeded()
        userPlaylistNameDraft = selectedUserPlaylist.name
        clearCurrentMixPlan()
        persistLibraryState()
        refreshAnalyses(for: restored)
        syncAIMixAfterPlaylistMutation()
        notice = "Loaded \(selectedUserPlaylist.name)"
    }

    func renameSelectedSavedSet() {
        let name = normalizeUserPlaylistName(userPlaylistNameDraft)
        guard !name.isEmpty else {
            notice = "Name the saved set first"
            return
        }
        guard let index = userPlaylists.firstIndex(where: { $0.id == selectedUserPlaylistId }) else {
            notice = "Choose a saved set first"
            return
        }

        let current = userPlaylists[index]
        userPlaylists[index] = UserPlaylist(
            id: current.id,
            name: name,
            trackIds: current.trackIds,
            createdAt: current.createdAt,
            updatedAt: timestamp()
        )
        persistLibraryState()
        notice = "Renamed saved set"
    }

    func deleteSelectedSavedSet() {
        guard let selectedUserPlaylist else {
            notice = "Choose a saved set first"
            return
        }

        userPlaylists.removeAll { $0.id == selectedUserPlaylist.id }
        selectedUserPlaylistId = ""
        userPlaylistNameDraft = ""
        persistLibraryState()
        notice = "Deleted \(selectedUserPlaylist.name)"
    }
}
