import Foundation
import BeatDropperDomain

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

public func normalizeUserPlaylistName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
}
