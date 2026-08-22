import BeatDropperDomain
import BeatDropperLibrary
import Foundation

public struct ImportedTrack: Identifiable, Hashable, Sendable {
    public var id: String { track.id }
    public var track: Track
    public var url: URL
    public var sourceFolderPath: String?
    public var fileFingerprint: String?
    public var missing: Bool
    public var missingAt: String?

    public init(
        track: Track,
        url: URL,
        sourceFolderPath: String?,
        fileFingerprint: String?,
        missing: Bool,
        missingAt: String?
    ) {
        self.track = track
        self.url = url
        self.sourceFolderPath = sourceFolderPath
        self.fileFingerprint = fileFingerprint
        self.missing = missing
        self.missingAt = missingAt
    }

    public init(record: NativeTrackRecord) {
        track = record.track
        url = URL(fileURLWithPath: record.filePath)
        sourceFolderPath = record.sourceFolderPath
        fileFingerprint = record.fileFingerprint
        missing = record.missing
        missingAt = record.missingAt
    }

    public func record(addedAt: String, updatedAt: String) -> NativeTrackRecord {
        NativeTrackRecord(
            track: track,
            filePath: url.path,
            sourceFolderPath: sourceFolderPath,
            fileFingerprint: fileFingerprint,
            missing: missing,
            missingAt: missingAt,
            addedAt: addedAt,
            updatedAt: updatedAt
        )
    }
}

public struct NativeOpenImportSelection: Sendable {
    public var audioFileURLs: [URL]
    public var folderURLs: [URL]
    public var unsupportedURLs: [URL]

    public var supportedItemCount: Int { audioFileURLs.count + folderURLs.count }

    public init(audioFileURLs: [URL], folderURLs: [URL], unsupportedURLs: [URL]) {
        self.audioFileURLs = audioFileURLs
        self.folderURLs = folderURLs
        self.unsupportedURLs = unsupportedURLs
    }
}
