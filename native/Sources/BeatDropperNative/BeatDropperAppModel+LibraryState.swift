import BeatDropperCore
import Foundation

extension BeatDropperAppModel {
    func restoreLibraryState() {
        do {
            let state = try store.loadMigratingLegacyDesktopStateIfNeeded()
            libraryRecords = state.trackRecords
            librarySourceFolders = state.sourceFolders
            userPlaylists = state.userPlaylists
            selectedUserPlaylistId = state.selectedUserPlaylistId
            userPlaylistNameDraft = selectedUserPlaylist?.name ?? ""

            let recordsById = Dictionary(uniqueKeysWithValues: state.trackRecords.map { ($0.id, $0) })
            playlist = state.currentPlaylistTrackIds.compactMap { id in
                recordsById[id].map(ImportedTrack.init(record:))
            }
            selectedTrackID = playlist.first?.id
            selectFirstAvailableTrackIfNeeded()
            refreshAnalyses(for: playlist)
            notice = playlist.isEmpty ? "Ready" : "Restored \(playlist.count) tracks"
        } catch {
            notice = "Could not restore library: \(error.localizedDescription)"
        }
    }

    func persistLibraryState() {
        do {
            let state = NativeLibraryState(
                trackRecords: libraryRecords,
                sourceFolders: librarySourceFolders,
                currentPlaylistTrackIds: playlist.map(\.id),
                userPlaylists: userPlaylists,
                selectedUserPlaylistId: selectedUserPlaylistId
            )
            try store.save(state)
        } catch {
            notice = "Could not save library: \(error.localizedDescription)"
        }
    }

    func rebuildLibraryBrowserIndex() {
        libraryBrowserTracks = NativeLibraryBrowserIndex.build(
            records: libraryRecords,
            sourceFolders: librarySourceFolders
        )
        rebuildFilteredLibraryTracks()
    }

    func rebuildFilteredLibraryTracks() {
        filteredLibraryTracks = NativeLibraryBrowserIndex.filter(
            libraryBrowserTracks,
            query: librarySearchText
        )
        if let selectedLibraryTrackID,
           !libraryBrowserTracks.contains(where: { $0.id == selectedLibraryTrackID }) {
            self.selectedLibraryTrackID = nil
        }
    }

    @discardableResult
    func upsertLibraryRecords(for imported: [ImportedTrack], sourceFolderURL: URL?) -> [ImportedTrack] {
        let now = timestamp()
        let sourceFolderPath = sourceFolderURL?.standardizedFileURL.path
        let sourceFolder = sourceFolderURL.map {
            NativeLibrarySourceFolderInput(path: $0.standardizedFileURL.path, displayName: $0.lastPathComponent)
        }
        let importItems = imported.map { track in
            NativeLibraryImportItem(
                track: track.track,
                filePath: track.url.path,
                sourceFolderPath: sourceFolderPath,
                fileFingerprint: fileFingerprint(for: track)
            )
        }
        let result = NativeLibraryReconciler.upsert(
            existingRecords: libraryRecords,
            existingSourceFolders: librarySourceFolders,
            imported: importItems,
            sourceFolder: sourceFolder,
            now: now
        )
        libraryRecords = result.trackRecords
        librarySourceFolders = result.sourceFolders

        let recordsById = Dictionary(uniqueKeysWithValues: libraryRecords.map { ($0.id, $0) })
        var seenResolvedIds = Set<String>()
        return imported.compactMap { importedTrack in
            let resolvedId = result.resolvedTrackIdByImportId[importedTrack.id] ?? importedTrack.id
            guard !seenResolvedIds.contains(resolvedId) else {
                return nil
            }
            seenResolvedIds.insert(resolvedId)
            if let record = recordsById[resolvedId] {
                return ImportedTrack(record: record)
            }
            return importedTrack
        }
    }

    @discardableResult
    func relinkLibraryRecord(
        trackId: String,
        replacement: ImportedTrack,
        sourceFolderURL: URL?
    ) -> ImportedTrack? {
        let now = timestamp()
        let sourceFolderPath = sourceFolderURL?.standardizedFileURL.path
        let sourceFolder = sourceFolderURL.map {
            NativeLibrarySourceFolderInput(path: $0.standardizedFileURL.path, displayName: $0.lastPathComponent)
        }
        let item = NativeLibraryImportItem(
            track: replacement.track,
            filePath: replacement.url.path,
            sourceFolderPath: sourceFolderPath,
            fileFingerprint: fileFingerprint(for: replacement)
        )
        let result = NativeLibraryReconciler.relinkTrack(
            existingRecords: libraryRecords,
            existingSourceFolders: librarySourceFolders,
            trackId: trackId,
            replacement: item,
            sourceFolder: sourceFolder,
            now: now
        )
        libraryRecords = result.trackRecords
        librarySourceFolders = result.sourceFolders
        pruneUnreferencedMissingSourceFolders()
        return libraryRecords.first { $0.id == trackId }.map(ImportedTrack.init(record:))
    }

    func markSourceFolderMissing(_ sourceFolderPath: String) {
        let result = NativeLibraryReconciler.markSourceFolderMissing(
            existingRecords: libraryRecords,
            existingSourceFolders: librarySourceFolders,
            sourceFolderPath: sourceFolderPath,
            now: timestamp()
        )
        libraryRecords = result.trackRecords
        librarySourceFolders = result.sourceFolders
    }

    func pruneUnreferencedMissingSourceFolders() {
        let referencedSourcePaths = Set(libraryRecords.compactMap { record -> String? in
            guard let sourceFolderPath = record.sourceFolderPath else {
                return nil
            }
            return URL(fileURLWithPath: sourceFolderPath).standardizedFileURL.path
        })
        librarySourceFolders.removeAll { folder in
            folder.missing && !referencedSourcePaths.contains(URL(fileURLWithPath: folder.path).standardizedFileURL.path)
        }
    }

    func refreshPlaylistFromLibraryRecords() {
        let recordsById = Dictionary(uniqueKeysWithValues: libraryRecords.map { ($0.id, $0) })
        playlist = playlist.map { imported in
            guard let record = recordsById[imported.id] else {
                return imported
            }
            return ImportedTrack(record: record)
        }
    }

    func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    func fileFingerprint(for imported: ImportedTrack) -> String {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: imported.url.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        let titleKey = imported.track.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let durationMs = Int((imported.track.durationSec * 1_000).rounded())
        return "\(titleKey)|\(imported.track.format.rawValue)|\(durationMs)|\(fileSize)"
    }

    @discardableResult
    func markTrackMissingIfUnavailable(_ imported: ImportedTrack) -> Bool {
        if isTrackAvailableForImmediateUse(imported) {
            return true
        }

        let now = timestamp()
        for index in playlist.indices where playlist[index].id == imported.id {
            playlist[index].missing = true
            playlist[index].missingAt = playlist[index].missingAt ?? now
        }
        for index in libraryRecords.indices where libraryRecords[index].id == imported.id {
            libraryRecords[index].missing = true
            libraryRecords[index].missingAt = libraryRecords[index].missingAt ?? now
            libraryRecords[index].updatedAt = now
        }
        clearCurrentMixPlan()
        persistLibraryState()
        return false
    }

    func selectFirstAvailableTrackIfNeeded() {
        if let selectedTrack, isTrackAvailableForImmediateUse(selectedTrack) {
            return
        }
        selectedTrackID = playlist.first(where: isTrackAvailableForImmediateUse)?.id ?? playlist.first?.id
    }
}
