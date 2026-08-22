import Foundation
import BeatDropperDomain

public struct NativeLibraryBrowserTrack: Hashable, Identifiable, Sendable {
    public var id: String { track.id }
    public var track: Track
    public var filePath: String
    public var sourceFolderPath: String?
    public var fileFingerprint: String?
    public var sourceDisplayName: String
    public var missing: Bool
    public var missingAt: String?
    public var searchKey: String

    public init(
        track: Track,
        filePath: String,
        sourceFolderPath: String?,
        fileFingerprint: String?,
        sourceDisplayName: String,
        missing: Bool,
        missingAt: String?,
        searchKey: String
    ) {
        self.track = track
        self.filePath = filePath
        self.sourceFolderPath = sourceFolderPath
        self.fileFingerprint = fileFingerprint
        self.sourceDisplayName = sourceDisplayName
        self.missing = missing
        self.missingAt = missingAt
        self.searchKey = searchKey
    }
}

public enum NativeLibraryBrowserIndex {
    public static func build(
        records: [NativeTrackRecord],
        sourceFolders: [NativeLibrarySourceFolder]
    ) -> [NativeLibraryBrowserTrack] {
        let sourceNamesByPath = Dictionary(
            uniqueKeysWithValues: sourceFolders.map { folder in
                (normalizedPath(folder.path), folder.displayName)
            }
        )

        return records
            .map { record in
                let fileName = URL(fileURLWithPath: record.filePath).lastPathComponent
                let sourceName = sourceDisplayName(
                    sourceFolderPath: record.sourceFolderPath,
                    sourceNamesByPath: sourceNamesByPath
                )
                let searchKey = [
                    record.track.title,
                    fileName,
                    sourceName,
                    record.track.format.rawValue,
                    record.track.bpm.map { String(Int($0.rounded())) },
                    record.missing ? "missing" : "ready"
                ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()

                return NativeLibraryBrowserTrack(
                    track: record.track,
                    filePath: record.filePath,
                    sourceFolderPath: record.sourceFolderPath,
                    fileFingerprint: record.fileFingerprint,
                    sourceDisplayName: sourceName,
                    missing: record.missing,
                    missingAt: record.missingAt,
                    searchKey: searchKey
                )
            }
            .sorted {
                $0.track.title.localizedStandardCompare($1.track.title) == .orderedAscending
            }
    }

    public static func filter(
        _ tracks: [NativeLibraryBrowserTrack],
        query: String
    ) -> [NativeLibraryBrowserTrack] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !terms.isEmpty else {
            return tracks
        }

        return tracks.filter { track in
            terms.allSatisfy { track.searchKey.contains($0) }
        }
    }

    private static func sourceDisplayName(
        sourceFolderPath: String?,
        sourceNamesByPath: [String: String]
    ) -> String {
        guard let sourceFolderPath, !sourceFolderPath.isEmpty else {
            return "Files"
        }
        let normalized = normalizedPath(sourceFolderPath)
        return sourceNamesByPath[normalized] ?? URL(fileURLWithPath: sourceFolderPath).lastPathComponent
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
