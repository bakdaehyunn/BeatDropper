import Foundation

public let nativeLibraryStateSchemaVersion = 1

public enum TrackPreparationCueKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case intro
    case drop
    case breakdown = "break"
    case outro
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .intro:
            return "Intro"
        case .drop:
            return "Drop"
        case .breakdown:
            return "Break"
        case .outro:
            return "Outro"
        case .custom:
            return "Custom"
        }
    }
}

public struct TrackPreparationCue: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: TrackPreparationCueKind
    public var timeSec: Double
    public var label: String

    public init(
        id: String = UUID().uuidString,
        kind: TrackPreparationCueKind,
        timeSec: Double,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.timeSec = timeSec
        self.label = label
    }
}

public struct TrackPreparation: Codable, Hashable, Sendable {
    public static let empty = TrackPreparation()

    public var bpmOverride: Double?
    public var hotCues: [TrackPreparationCue]

    public init(
        bpmOverride: Double? = nil,
        hotCues: [TrackPreparationCue] = []
    ) {
        self.bpmOverride = bpmOverride
        self.hotCues = hotCues
    }
}

public struct NativeTrackRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String { track.id }
    public var track: Track
    public var filePath: String
    public var sourceFolderPath: String?
    public var fileFingerprint: String?
    public var missing: Bool
    public var missingAt: String?
    public var addedAt: String
    public var updatedAt: String
    public var preparation: TrackPreparation

    public init(
        track: Track,
        filePath: String,
        sourceFolderPath: String? = nil,
        fileFingerprint: String? = nil,
        missing: Bool = false,
        missingAt: String? = nil,
        addedAt: String,
        updatedAt: String,
        preparation: TrackPreparation = .empty
    ) {
        self.track = track
        self.filePath = filePath
        self.sourceFolderPath = sourceFolderPath
        self.fileFingerprint = fileFingerprint
        self.missing = missing
        self.missingAt = missingAt
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.preparation = preparation
    }

    private enum CodingKeys: String, CodingKey {
        case track
        case filePath
        case sourceFolderPath
        case fileFingerprint
        case missing
        case missingAt
        case addedAt
        case updatedAt
        case preparation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.track = try container.decode(Track.self, forKey: .track)
        self.filePath = try container.decode(String.self, forKey: .filePath)
        self.sourceFolderPath = try container.decodeIfPresent(String.self, forKey: .sourceFolderPath)
        self.fileFingerprint = try container.decodeIfPresent(String.self, forKey: .fileFingerprint)
        self.missing = try container.decodeIfPresent(Bool.self, forKey: .missing) ?? false
        self.missingAt = try container.decodeIfPresent(String.self, forKey: .missingAt)
        self.addedAt = try container.decode(String.self, forKey: .addedAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.preparation = try container.decodeIfPresent(TrackPreparation.self, forKey: .preparation) ?? .empty
    }
}

public struct NativeLibrarySourceFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var displayName: String
    public var addedAt: String
    public var updatedAt: String
    public var lastScannedAt: String
    public var trackCount: Int
    public var missing: Bool
    public var missingAt: String?

    public init(
        path: String,
        displayName: String,
        addedAt: String,
        updatedAt: String,
        lastScannedAt: String,
        trackCount: Int,
        missing: Bool = false,
        missingAt: String? = nil
    ) {
        self.path = path
        self.displayName = displayName
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.lastScannedAt = lastScannedAt
        self.trackCount = trackCount
        self.missing = missing
        self.missingAt = missingAt
    }
}

public struct NativeLibraryState: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var trackRecords: [NativeTrackRecord]
    public var sourceFolders: [NativeLibrarySourceFolder]
    public var currentPlaylistTrackIds: [String]
    public var userPlaylists: [UserPlaylist]
    public var selectedUserPlaylistId: String

    public init(
        schemaVersion: Int = nativeLibraryStateSchemaVersion,
        trackRecords: [NativeTrackRecord] = [],
        sourceFolders: [NativeLibrarySourceFolder] = [],
        currentPlaylistTrackIds: [String] = [],
        userPlaylists: [UserPlaylist] = [],
        selectedUserPlaylistId: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.trackRecords = trackRecords
        self.sourceFolders = sourceFolders
        self.currentPlaylistTrackIds = currentPlaylistTrackIds
        self.userPlaylists = userPlaylists
        self.selectedUserPlaylistId = selectedUserPlaylistId
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case trackRecords
        case sourceFolders
        case currentPlaylistTrackIds
        case userPlaylists
        case selectedUserPlaylistId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.trackRecords = try container.decodeIfPresent([NativeTrackRecord].self, forKey: .trackRecords) ?? []
        self.sourceFolders = try container.decodeIfPresent([NativeLibrarySourceFolder].self, forKey: .sourceFolders) ?? []
        self.currentPlaylistTrackIds = try container.decodeIfPresent([String].self, forKey: .currentPlaylistTrackIds) ?? []
        self.userPlaylists = try container.decodeIfPresent([UserPlaylist].self, forKey: .userPlaylists) ?? []
        self.selectedUserPlaylistId = try container.decodeIfPresent(String.self, forKey: .selectedUserPlaylistId) ?? ""
    }
}

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

    public func loadMigratingElectronStateIfNeeded() throws -> NativeLibraryState {
        if FileManager.default.fileExists(atPath: fileURL.path) ||
            FileManager.default.fileExists(atPath: backupFileURL.path) {
            return try load()
        }

        let folderURL = fileURL.deletingLastPathComponent()
        let migration = try NativeLibraryMigration.migrateElectronState(
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

public func normalizeUserPlaylistName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
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
