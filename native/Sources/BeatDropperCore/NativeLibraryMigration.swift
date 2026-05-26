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
    public static func migrateElectronState(
        musicLibraryFileURL: URL,
        userPlaylistFileURL: URL
    ) throws -> NativeLibraryMigrationResult {
        let electronTracks = try loadElectronMusicLibrary(from: musicLibraryFileURL)
        let trackRecords = electronTracks.valid.map(\.record)
        let knownTrackIds = Set(trackRecords.map(\.id))
        let sourceFolders = buildSourceFolders(from: electronTracks.valid)
        let userPlaylists = try loadElectronUserPlaylists(
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
            skippedTrackCount: electronTracks.skippedCount
        )
    }

    private static func loadElectronMusicLibrary(from fileURL: URL) throws -> ElectronTrackLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ElectronTrackLoadResult(valid: [], skippedCount: 0)
        }

        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(ElectronMusicLibraryFile.self, from: data)
        var valid: [MigratedElectronTrack] = []
        var skippedCount = 0

        for candidate in file.tracks ?? [] {
            if let migrated = candidate.migratedRecord {
                valid.append(migrated)
            } else {
                skippedCount += 1
            }
        }

        return ElectronTrackLoadResult(valid: deduplicateTracks(valid), skippedCount: skippedCount)
    }

    private static func loadElectronUserPlaylists(
        from fileURL: URL,
        knownTrackIds: Set<String>
    ) throws -> [UserPlaylist] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(ElectronUserPlaylistFile.self, from: data)
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

            let createdAt = normalized(candidate.createdAt) ?? electronEpoch
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
        from tracks: [MigratedElectronTrack]
    ) -> [NativeLibrarySourceFolder] {
        var grouped: [String: [MigratedElectronTrack]] = [:]
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
            let addedAt = tracks.map(\.record.addedAt).min() ?? electronEpoch
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
        _ tracks: [MigratedElectronTrack]
    ) -> [MigratedElectronTrack] {
        var byId: [String: MigratedElectronTrack] = [:]
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

private struct ElectronTrackLoadResult {
    var valid: [MigratedElectronTrack]
    var skippedCount: Int
}

private struct MigratedElectronTrack: Hashable {
    var record: NativeTrackRecord
    var sourcePath: String
    var sourceLabel: String
}

private struct ElectronMusicLibraryFile: Decodable {
    var tracks: [ElectronStoredTrack]?
}

private struct ElectronStoredTrack: Decodable {
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

    var migratedRecord: MigratedElectronTrack? {
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

        let addedAt = normalized(addedAt) ?? electronEpoch
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

        return MigratedElectronTrack(
            record: record,
            sourcePath: sourcePath,
            sourceLabel: sourceLabel
        )
    }
}

private struct ElectronUserPlaylistFile: Decodable {
    var playlists: [ElectronStoredUserPlaylist]?
}

private struct ElectronStoredUserPlaylist: Decodable {
    var id: String?
    var name: String?
    var trackIds: [String]?
    var createdAt: String?
    var updatedAt: String?
}

private let electronEpoch = "1970-01-01T00:00:00.000Z"

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
