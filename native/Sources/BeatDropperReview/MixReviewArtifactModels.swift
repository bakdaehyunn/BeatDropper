import Foundation
import BeatDropperDomain

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
