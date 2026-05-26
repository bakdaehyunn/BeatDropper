import BeatDropperCore
import Foundation
import Testing

struct NativeLibraryMigrationTests {
    @Test func migratesElectronLibraryAndSavedPlaylists() throws {
        let folderURL = temporaryFolderURL()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let musicLibraryURL = folderURL.appendingPathComponent("music-library.json")
        let playlistsURL = folderURL.appendingPathComponent("user-playlists.json")
        try Data(
            """
            {
              "schemaVersion": 1,
              "tracks": [
                {
                  "id": "track-1",
                  "title": "First Track",
                  "durationSec": 180,
                  "format": "wav",
                  "bpm": 128,
                  "addedAt": "2026-05-20T00:00:00Z",
                  "updatedAt": "2026-05-21T00:00:00Z",
                  "sourcePath": "\(folderURL.path)",
                  "sourceLabel": "Crate A",
                  "missing": false,
                  "missingAt": null,
                  "filePath": "\(folderURL.appendingPathComponent("first.wav").path)"
                },
                {
                  "id": "track-2",
                  "title": "Second Track",
                  "durationSec": 240,
                  "format": "mp3",
                  "addedAt": "2026-05-22T00:00:00Z",
                  "updatedAt": "2026-05-23T00:00:00Z",
                  "sourcePath": "\(folderURL.path)",
                  "sourceLabel": "Crate A",
                  "missing": true,
                  "missingAt": "2026-05-24T00:00:00Z",
                  "filePath": "\(folderURL.appendingPathComponent("second.mp3").path)"
                },
                {
                  "id": "",
                  "title": "Invalid",
                  "durationSec": 10,
                  "format": "wav",
                  "sourcePath": "\(folderURL.path)",
                  "filePath": "\(folderURL.appendingPathComponent("invalid.wav").path)"
                }
              ]
            }
            """.utf8
        ).write(to: musicLibraryURL)
        try Data(
            """
            {
              "schemaVersion": 1,
              "playlists": [
                {
                  "id": "set-old",
                  "name": " Warmup   Set ",
                  "trackIds": ["track-1", "missing-track", "track-1"],
                  "createdAt": "2026-05-20T00:00:00Z",
                  "updatedAt": "2026-05-21T00:00:00Z"
                },
                {
                  "id": "set-new",
                  "name": "Peak Hour",
                  "trackIds": ["track-2", "track-1"],
                  "createdAt": "2026-05-22T00:00:00Z",
                  "updatedAt": "2026-05-24T00:00:00Z"
                }
              ]
            }
            """.utf8
        ).write(to: playlistsURL)

        let migration = try NativeLibraryMigration.migrateElectronState(
            musicLibraryFileURL: musicLibraryURL,
            userPlaylistFileURL: playlistsURL
        )

        #expect(migration.importedTrackCount == 2)
        #expect(migration.importedPlaylistCount == 2)
        #expect(migration.skippedTrackCount == 1)
        #expect(migration.state.trackRecords.map(\.id) == ["track-1", "track-2"])
        #expect(migration.state.trackRecords[1].missing == true)
        #expect(migration.state.sourceFolders.map(\.displayName) == ["Crate A"])
        #expect(migration.state.sourceFolders.first?.trackCount == 2)
        #expect(migration.state.userPlaylists.map(\.id) == ["set-new", "set-old"])
        #expect(migration.state.userPlaylists[1].name == "Warmup Set")
        #expect(migration.state.userPlaylists[1].trackIds == ["track-1"])
        #expect(migration.state.selectedUserPlaylistId == "set-new")
        #expect(migration.state.currentPlaylistTrackIds == ["track-2", "track-1"])
    }

    @Test func storeAutoMigratesElectronStateWhenNativeStateIsMissing() throws {
        let folderURL = temporaryFolderURL()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try Data(
            """
            {
              "schemaVersion": 1,
              "tracks": [
                {
                  "id": "track-1",
                  "title": "Legacy Track",
                  "durationSec": 180,
                  "format": "wav",
                  "addedAt": "2026-05-20T00:00:00Z",
                  "updatedAt": "2026-05-21T00:00:00Z",
                  "sourcePath": "\(folderURL.path)",
                  "sourceLabel": "Legacy",
                  "missing": false,
                  "missingAt": null,
                  "filePath": "\(folderURL.appendingPathComponent("legacy.wav").path)"
                }
              ]
            }
            """.utf8
        ).write(to: folderURL.appendingPathComponent("music-library.json"))
        try Data(
            """
            {
              "schemaVersion": 1,
              "playlists": [
                {
                  "id": "set-1",
                  "name": "Legacy Set",
                  "trackIds": ["track-1"],
                  "createdAt": "2026-05-20T00:00:00Z",
                  "updatedAt": "2026-05-21T00:00:00Z"
                }
              ]
            }
            """.utf8
        ).write(to: folderURL.appendingPathComponent("user-playlists.json"))

        let nativeURL = folderURL.appendingPathComponent("native-library.json")
        let store = NativeLibraryStore(fileURL: nativeURL)
        let loaded = try store.loadMigratingElectronStateIfNeeded()

        #expect(FileManager.default.fileExists(atPath: nativeURL.path))
        #expect(loaded.trackRecords.map(\.id) == ["track-1"])
        #expect(loaded.userPlaylists.map(\.id) == ["set-1"])
        #expect(loaded.currentPlaylistTrackIds == ["track-1"])
    }

    private func temporaryFolderURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
