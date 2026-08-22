import BeatDropperReview
import Foundation

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
