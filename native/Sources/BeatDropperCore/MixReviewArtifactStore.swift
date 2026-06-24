import Foundation

public let mixReviewArtifactStateSchemaVersion = 3
public let mixReviewArtifactAnnotationCharacterLimit = 2_000

public struct MixReviewArtifactTrackPair: Codable, Hashable, Sendable {
    public var currentTrackId: String
    public var nextTrackId: String

    public init(currentTrackId: String, nextTrackId: String) {
        self.currentTrackId = currentTrackId
        self.nextTrackId = nextTrackId
    }
}

public struct PersistedMixReviewArtifact: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var importedAt: String
    public var fileName: String
    public var format: String
    public var content: String
    public var reviewCount: Int
    public var schemaVersion: Int?
    public var trackPairs: [MixReviewArtifactTrackPair]
    public var reviewAnnotation: String

    public init(
        id: String,
        importedAt: String,
        fileName: String,
        format: String,
        content: String,
        reviewCount: Int,
        schemaVersion: Int? = nil,
        trackPairs: [MixReviewArtifactTrackPair] = [],
        reviewAnnotation: String = ""
    ) {
        self.id = id
        self.importedAt = importedAt
        self.fileName = fileName
        self.format = format
        self.content = content
        self.reviewCount = reviewCount
        self.schemaVersion = schemaVersion
        self.trackPairs = trackPairs
        self.reviewAnnotation = reviewAnnotation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case importedAt
        case fileName
        case format
        case content
        case reviewCount
        case schemaVersion
        case trackPairs
        case reviewAnnotation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.importedAt = try container.decode(String.self, forKey: .importedAt)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.format = try container.decode(String.self, forKey: .format)
        self.content = try container.decode(String.self, forKey: .content)
        self.reviewCount = try container.decode(Int.self, forKey: .reviewCount)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        self.trackPairs = try container.decodeIfPresent([MixReviewArtifactTrackPair].self, forKey: .trackPairs) ?? []
        self.reviewAnnotation = try container.decodeIfPresent(String.self, forKey: .reviewAnnotation) ?? ""
    }
}

public struct MixReviewArtifactState: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var artifacts: [PersistedMixReviewArtifact]

    public init(
        schemaVersion: Int = mixReviewArtifactStateSchemaVersion,
        artifacts: [PersistedMixReviewArtifact] = []
    ) {
        self.schemaVersion = schemaVersion
        self.artifacts = artifacts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case artifacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.artifacts = try container.decodeIfPresent([PersistedMixReviewArtifact].self, forKey: .artifacts) ?? []
    }
}

public final class MixReviewArtifactStore: @unchecked Sendable {
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
        filename: String = "mix-review-artifacts.json",
        fileManager: FileManager = .default
    ) -> MixReviewArtifactStore {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return MixReviewArtifactStore(
            fileURL: baseURL
                .appendingPathComponent(appFolderName, isDirectory: true)
                .appendingPathComponent(filename)
        )
    }

    public func load() throws -> MixReviewArtifactState {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.fileExists(atPath: backupFileURL.path) else {
                return MixReviewArtifactState()
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

    public func save(_ state: MixReviewArtifactState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(Self.sanitized(state))
        try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        try writeCurrentStateBackup()
    }

    private func loadState(at url: URL) throws -> MixReviewArtifactState {
        try Self.sanitized(decoder.decode(MixReviewArtifactState.self, from: Data(contentsOf: url)))
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

    public static func sanitized(_ state: MixReviewArtifactState) -> MixReviewArtifactState {
        MixReviewArtifactState(
            schemaVersion: mixReviewArtifactStateSchemaVersion,
            artifacts: Array(state.artifacts.prefix(12)).map(sanitizedArtifact)
        )
    }

    private static func sanitizedArtifact(_ artifact: PersistedMixReviewArtifact) -> PersistedMixReviewArtifact {
        var sanitizedArtifact = artifact
        sanitizedArtifact.reviewAnnotation = String(
            sanitizedArtifact.reviewAnnotation.prefix(mixReviewArtifactAnnotationCharacterLimit)
        )
        return sanitizedArtifact
    }
}
