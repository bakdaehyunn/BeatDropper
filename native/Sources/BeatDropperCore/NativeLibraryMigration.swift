import Foundation

public struct NativeLibraryMigrationResult: Hashable, Sendable {
    public var state: NativeLibraryState
    public var importedTrackCount: Int
    public var importedPlaylistCount: Int
    public var skippedTrackCount: Int

    public init(
        state: NativeLibraryState,
        importedTrackCount: Int,
        importedPlaylistCount: Int,
        skippedTrackCount: Int
    ) {
        self.state = state
        self.importedTrackCount = importedTrackCount
        self.importedPlaylistCount = importedPlaylistCount
        self.skippedTrackCount = skippedTrackCount
    }

    public var didImportAnything: Bool {
        importedTrackCount > 0 || importedPlaylistCount > 0
    }
}

public enum NativeLibraryMigration {
    public static func migrateLegacyDesktopState(
        musicLibraryFileURL: URL,
        userPlaylistFileURL: URL
    ) throws -> NativeLibraryMigrationResult {
        let legacyTracks = try loadLegacyDesktopMusicLibrary(from: musicLibraryFileURL)
        let trackRecords = legacyTracks.valid.map(\.record)
        let knownTrackIds = Set(trackRecords.map(\.id))
        let sourceFolders = buildSourceFolders(from: legacyTracks.valid)
        let userPlaylists = try loadLegacyDesktopUserPlaylists(
            from: userPlaylistFileURL,
            knownTrackIds: knownTrackIds
        )

        let selectedPlaylist = userPlaylists.first
        let state = NativeLibraryState(
            trackRecords: trackRecords,
            sourceFolders: sourceFolders,
            currentPlaylistTrackIds: selectedPlaylist?.trackIds ?? [],
            userPlaylists: userPlaylists,
            selectedUserPlaylistId: selectedPlaylist?.id ?? ""
        )

        return NativeLibraryMigrationResult(
            state: state,
            importedTrackCount: trackRecords.count,
            importedPlaylistCount: userPlaylists.count,
            skippedTrackCount: legacyTracks.skippedCount
        )
    }

    private static func loadLegacyDesktopMusicLibrary(from fileURL: URL) throws -> LegacyDesktopTrackLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LegacyDesktopTrackLoadResult(valid: [], skippedCount: 0)
        }

        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(LegacyMusicLibraryFile.self, from: data)
        var valid: [MigratedLegacyTrack] = []
        var skippedCount = 0

        for candidate in file.tracks ?? [] {
            if let migrated = candidate.migratedRecord {
                valid.append(migrated)
            } else {
                skippedCount += 1
            }
        }

        return LegacyDesktopTrackLoadResult(valid: deduplicateTracks(valid), skippedCount: skippedCount)
    }

    private static func loadLegacyDesktopUserPlaylists(
        from fileURL: URL,
        knownTrackIds: Set<String>
    ) throws -> [UserPlaylist] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(LegacyUserPlaylistFile.self, from: data)
        let playlists = (file.playlists ?? []).compactMap { candidate -> UserPlaylist? in
            guard let id = normalized(candidate.id),
                  let name = normalizedPlaylistName(candidate.name)
            else {
                return nil
            }

            let trackIds = deduplicatedStrings(candidate.trackIds ?? [])
                .filter { knownTrackIds.contains($0) }
            guard !trackIds.isEmpty else {
                return nil
            }

            let createdAt = normalized(candidate.createdAt) ?? legacyDesktopEpoch
            let updatedAt = normalized(candidate.updatedAt) ?? createdAt
            return UserPlaylist(
                id: id,
                name: name,
                trackIds: trackIds,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        return deduplicatePlaylists(playlists)
    }

    private static func buildSourceFolders(
        from tracks: [MigratedLegacyTrack]
    ) -> [NativeLibrarySourceFolder] {
        var grouped: [String: [MigratedLegacyTrack]] = [:]
        var orderedPaths: [String] = []

        for track in tracks {
            let path = track.sourcePath
            if grouped[path] == nil {
                orderedPaths.append(path)
            }
            grouped[path, default: []].append(track)
        }

        return orderedPaths.compactMap { path in
            guard let tracks = grouped[path], let first = tracks.first else {
                return nil
            }
            let addedAt = tracks.map(\.record.addedAt).min() ?? legacyDesktopEpoch
            let updatedAt = tracks.map(\.record.updatedAt).max() ?? addedAt
            let missing = tracks.allSatisfy(\.record.missing)
            let missingAt = missing ? tracks.compactMap(\.record.missingAt).min() : nil
            return NativeLibrarySourceFolder(
                path: path,
                displayName: first.sourceLabel,
                addedAt: addedAt,
                updatedAt: updatedAt,
                lastScannedAt: updatedAt,
                trackCount: tracks.count,
                missing: missing,
                missingAt: missingAt
            )
        }
    }

    private static func deduplicateTracks(
        _ tracks: [MigratedLegacyTrack]
    ) -> [MigratedLegacyTrack] {
        var byId: [String: MigratedLegacyTrack] = [:]
        var orderedIds: [String] = []

        for track in tracks {
            if byId[track.record.id] == nil {
                orderedIds.append(track.record.id)
            }
            byId[track.record.id] = track
        }

        return orderedIds.compactMap { byId[$0] }
    }

    private static func deduplicatePlaylists(_ playlists: [UserPlaylist]) -> [UserPlaylist] {
        var byId: [String: UserPlaylist] = [:]
        var orderedIds: [String] = []

        for playlist in playlists.sorted(by: playlistSort) {
            if byId[playlist.id] == nil {
                orderedIds.append(playlist.id)
                byId[playlist.id] = playlist
            }
        }

        return orderedIds.compactMap { byId[$0] }
    }

    private static func playlistSort(_ left: UserPlaylist, _ right: UserPlaylist) -> Bool {
        left.updatedAt > right.updatedAt || (left.updatedAt == right.updatedAt && left.name < right.name)
    }

    private static func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard let normalized = normalized(value), !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }
}

private struct LegacyDesktopTrackLoadResult {
    var valid: [MigratedLegacyTrack]
    var skippedCount: Int
}

private struct MigratedLegacyTrack: Hashable {
    var record: NativeTrackRecord
    var sourcePath: String
    var sourceLabel: String
}

private struct LegacyMusicLibraryFile: Decodable {
    var tracks: [LegacyStoredTrack]?
}

private struct LegacyStoredTrack: Decodable {
    var id: String?
    var title: String?
    var durationSec: Double?
    var format: AudioFormat?
    var bpm: Double?
    var addedAt: String?
    var updatedAt: String?
    var sourcePath: String?
    var sourceLabel: String?
    var missing: Bool?
    var missingAt: String?
    var filePath: String?

    var migratedRecord: MigratedLegacyTrack? {
        guard let id = normalized(id),
              let title = normalized(title),
              let durationSec,
              durationSec.isFinite,
              let format,
              let filePath = normalized(filePath),
              let sourcePath = normalized(sourcePath)
        else {
            return nil
        }

        let addedAt = normalized(addedAt) ?? legacyDesktopEpoch
        let updatedAt = normalized(updatedAt) ?? addedAt
        let isMissing = missing ?? false
        let labelFallback = URL(fileURLWithPath: sourcePath).lastPathComponent
        let sourceLabel = normalized(sourceLabel) ?? (labelFallback.isEmpty ? sourcePath : labelFallback)
        let track = Track(
            id: id,
            title: title,
            durationSec: max(0, durationSec),
            format: format,
            bpm: bpm?.isFinite == true ? bpm : nil
        )
        let record = NativeTrackRecord(
            track: track,
            filePath: filePath,
            sourceFolderPath: sourcePath,
            fileFingerprint: nil,
            missing: isMissing,
            missingAt: isMissing ? normalized(missingAt) : nil,
            addedAt: addedAt,
            updatedAt: updatedAt
        )

        return MigratedLegacyTrack(
            record: record,
            sourcePath: sourcePath,
            sourceLabel: sourceLabel
        )
    }
}

private struct LegacyUserPlaylistFile: Decodable {
    var playlists: [LegacyStoredUserPlaylist]?
}

private struct LegacyStoredUserPlaylist: Decodable {
    var id: String?
    var name: String?
    var trackIds: [String]?
    var createdAt: String?
    var updatedAt: String?
}

private let legacyDesktopEpoch = "1970-01-01T00:00:00.000Z"

private func normalized(_ value: String?) -> String? {
    let result = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
}

private func normalizedPlaylistName(_ value: String?) -> String? {
    guard let value = normalized(value) else {
        return nil
    }
    let collapsed = value
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    let limited = String(collapsed.prefix(80))
    return limited.isEmpty ? nil : limited
}
