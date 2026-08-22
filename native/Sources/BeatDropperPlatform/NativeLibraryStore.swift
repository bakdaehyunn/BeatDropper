import BeatDropperDomain
import BeatDropperLibrary
import Foundation

public final class NativeLibraryStore: @unchecked Sendable {
    public let fileURL: URL
    public var backupFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("backup.json")
    }

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport(
        appFolderName: String = "BeatDropper",
        filename: String = "native-library.json",
        fileManager: FileManager = .default
    ) -> NativeLibraryStore {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return NativeLibraryStore(
            fileURL: baseURL
                .appendingPathComponent(appFolderName, isDirectory: true)
                .appendingPathComponent(filename)
        )
    }

    public func load() throws -> NativeLibraryState {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.fileExists(atPath: backupFileURL.path) else {
                return NativeLibraryState()
            }
            return try loadState(at: backupFileURL)
        }

        do {
            return try loadState(at: fileURL)
        } catch {
            guard FileManager.default.fileExists(atPath: backupFileURL.path) else {
                throw error
            }
            return try loadState(at: backupFileURL)
        }
    }

    public func loadMigratingLegacyDesktopStateIfNeeded() throws -> NativeLibraryState {
        if FileManager.default.fileExists(atPath: fileURL.path) ||
            FileManager.default.fileExists(atPath: backupFileURL.path) {
            return try load()
        }

        let folderURL = fileURL.deletingLastPathComponent()
        let migration = try NativeLibraryMigration.migrateLegacyDesktopState(
            musicLibraryFileURL: folderURL.appendingPathComponent("music-library.json"),
            userPlaylistFileURL: folderURL.appendingPathComponent("user-playlists.json")
        )
        guard migration.didImportAnything else {
            return NativeLibraryState()
        }

        try save(migration.state)
        return try load()
    }

    public func save(_ state: NativeLibraryState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(sanitized(state))
        try data.write(to: fileURL, options: [.atomic])
        try writeCurrentStateBackup()
    }

    private func loadState(at url: URL) throws -> NativeLibraryState {
        let data = try Data(contentsOf: url)
        let state = try decoder.decode(NativeLibraryState.self, from: data)
        guard state.schemaVersion == nativeLibraryStateSchemaVersion else {
            return NativeLibraryState()
        }
        return sanitized(state)
    }

    private func writeCurrentStateBackup() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        let temporaryBackupURL = backupFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(backupFileURL.lastPathComponent).\(UUID().uuidString).tmp")
        try FileManager.default.copyItem(at: fileURL, to: temporaryBackupURL)
        if FileManager.default.fileExists(atPath: backupFileURL.path) {
            _ = try FileManager.default.replaceItemAt(
                backupFileURL,
                withItemAt: temporaryBackupURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: temporaryBackupURL, to: backupFileURL)
        }
    }

    private func sanitized(_ state: NativeLibraryState) -> NativeLibraryState {
        var recordsById: [String: NativeTrackRecord] = [:]
        var records: [NativeTrackRecord] = []
        for var record in state.trackRecords where !record.id.isEmpty && !record.filePath.isEmpty {
            record.preparation = sanitizedPreparation(record.preparation, durationSec: record.track.durationSec)
            if recordsById[record.id] == nil {
                records.append(record)
            }
            recordsById[record.id] = record
        }
        records = records.compactMap { recordsById[$0.id] }

        let availableIds = Set(recordsById.keys)
        let sourceFolders = state.sourceFolders
            .map { folder in
                NativeLibrarySourceFolder(
                    path: folder.path.trimmingCharacters(in: .whitespacesAndNewlines),
                    displayName: folder.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    addedAt: folder.addedAt,
                    updatedAt: folder.updatedAt,
                    lastScannedAt: folder.lastScannedAt,
                    trackCount: max(0, folder.trackCount),
                    missing: folder.missing,
                    missingAt: folder.missingAt
                )
            }
            .filter { !$0.path.isEmpty && !$0.displayName.isEmpty }
            .deduplicatedById()

        let playlists = state.userPlaylists.map { playlist in
            UserPlaylist(
                id: playlist.id,
                name: normalizeUserPlaylistName(playlist.name),
                trackIds: playlist.trackIds.filter { availableIds.contains($0) },
                createdAt: playlist.createdAt,
                updatedAt: playlist.updatedAt
            )
        }
        .filter { !$0.id.isEmpty && !$0.name.isEmpty }

        let selectedId = playlists.contains { $0.id == state.selectedUserPlaylistId }
            ? state.selectedUserPlaylistId
            : ""

        return NativeLibraryState(
            trackRecords: records,
            sourceFolders: sourceFolders,
            currentPlaylistTrackIds: state.currentPlaylistTrackIds.filter { availableIds.contains($0) },
            userPlaylists: playlists,
            selectedUserPlaylistId: selectedId
        )
    }

    private func sanitizedPreparation(_ preparation: TrackPreparation, durationSec: Double) -> TrackPreparation {
        let safeDuration = durationSec.isFinite ? max(0, durationSec) : 0
        let bpmOverride = preparation.bpmOverride.flatMap { bpm -> Double? in
            guard bpm.isFinite, bpm >= 40, bpm <= 260 else {
                return nil
            }
            return (bpm * 10).rounded() / 10
        }

        var seenCueIds = Set<String>()
        let hotCues = preparation.hotCues.compactMap { cue -> TrackPreparationCue? in
            guard cue.timeSec.isFinite else {
                return nil
            }
            let id = cue.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seenCueIds.contains(id) else {
                return nil
            }
            seenCueIds.insert(id)
            let label = cue.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return TrackPreparationCue(
                id: id,
                kind: cue.kind,
                timeSec: min(max(0, cue.timeSec), safeDuration),
                label: label.isEmpty ? cue.kind.displayName : label
            )
        }

        return TrackPreparation(bpmOverride: bpmOverride, hotCues: hotCues.sorted { $0.timeSec < $1.timeSec })
    }
}

private extension Array where Element == NativeLibrarySourceFolder {
    func deduplicatedById() -> [NativeLibrarySourceFolder] {
        var foldersById: [String: NativeLibrarySourceFolder] = [:]
        var orderedIds: [String] = []
        for folder in self {
            if foldersById[folder.id] == nil {
                orderedIds.append(folder.id)
            }
            foldersById[folder.id] = folder
        }
        return orderedIds.compactMap { foldersById[$0] }
    }
}
