import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct NativeLibraryStoreTests {
    @Test func missingLibraryFileLoadsEmptyState() throws {
        let fileURL = temporaryLibraryURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = NativeLibraryStore(fileURL: fileURL)
        let state = try store.load()

        #expect(state.schemaVersion == nativeLibraryStateSchemaVersion)
        #expect(state.trackRecords.isEmpty)
        #expect(state.currentPlaylistTrackIds.isEmpty)
        #expect(state.userPlaylists.isEmpty)
        #expect(state.selectedUserPlaylistId.isEmpty)
    }

    @Test func savesAndLoadsCurrentPlaylistAndSavedSets() throws {
        let fileURL = temporaryLibraryURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let firstRecord = trackRecord(id: "track-1", title: "First Track", path: "/Music/first.wav")
        let secondRecord = trackRecord(id: "track-2", title: "Second Track", path: "/Music/second.mp3")
        let savedSet = UserPlaylist(
            id: "set-1",
            name: "Peak Hour",
            trackIds: ["track-2", "track-1"],
            createdAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z"
        )
        let folder = NativeLibrarySourceFolder(
            path: "/Music",
            displayName: "Music",
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z",
            lastScannedAt: "2026-05-25T00:00:00Z",
            trackCount: 2
        )
        let state = NativeLibraryState(
            trackRecords: [firstRecord, secondRecord],
            sourceFolders: [folder],
            currentPlaylistTrackIds: ["track-1", "track-2"],
            userPlaylists: [savedSet],
            selectedUserPlaylistId: "set-1"
        )

        let store = NativeLibraryStore(fileURL: fileURL)
        try store.save(state)
        let loaded = try store.load()

        #expect(loaded.trackRecords.map(\.id) == ["track-1", "track-2"])
        #expect(loaded.sourceFolders.map(\.path) == ["/Music"])
        #expect(loaded.sourceFolders.first?.trackCount == 2)
        #expect(loaded.currentPlaylistTrackIds == ["track-1", "track-2"])
        #expect(loaded.userPlaylists.first?.name == "Peak Hour")
        #expect(loaded.userPlaylists.first?.trackIds == ["track-2", "track-1"])
        #expect(loaded.selectedUserPlaylistId == "set-1")
    }

    @Test func savesAndLoadsTrackPreparationMetadata() throws {
        let fileURL = temporaryLibraryURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        var record = trackRecord(id: "track-1", title: "Prepared Track", path: "/Music/prepared.wav")
        record.preparation = TrackPreparation(
            bpmOverride: 126.44,
            hotCues: [
                TrackPreparationCue(id: "cue-drop", kind: .drop, timeSec: 64.2, label: "Drop"),
                TrackPreparationCue(id: "cue-intro", kind: .intro, timeSec: 4.8, label: "Intro")
            ]
        )
        let state = NativeLibraryState(trackRecords: [record], currentPlaylistTrackIds: ["track-1"])

        let store = NativeLibraryStore(fileURL: fileURL)
        try store.save(state)
        let loaded = try store.load()

        let preparation = try #require(loaded.trackRecords.first?.preparation)
        #expect(preparation.bpmOverride == 126.4)
        #expect(preparation.hotCues.map(\.id) == ["cue-intro", "cue-drop"])
        #expect(preparation.hotCues.map(\.kind) == [.intro, .drop])
    }

    @Test func saveRemovesPlaylistReferencesToMissingLibraryTracks() throws {
        let fileURL = temporaryLibraryURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let state = NativeLibraryState(
            trackRecords: [trackRecord(id: "track-1", title: "First Track", path: "/Music/first.wav")],
            currentPlaylistTrackIds: ["track-1", "missing-track"],
            userPlaylists: [
                UserPlaylist(
                    id: "set-1",
                    name: "  Warmup  ",
                    trackIds: ["missing-track", "track-1"],
                    createdAt: "2026-05-25T00:00:00Z",
                    updatedAt: "2026-05-25T00:00:00Z"
                )
            ],
            selectedUserPlaylistId: "set-1"
        )

        let store = NativeLibraryStore(fileURL: fileURL)
        try store.save(state)
        let loaded = try store.load()

        #expect(loaded.currentPlaylistTrackIds == ["track-1"])
        #expect(loaded.userPlaylists.first?.name == "Warmup")
        #expect(loaded.userPlaylists.first?.trackIds == ["track-1"])
    }

    @Test func loadsOlderStateWithoutSourceFolderFields() throws {
        let fileURL = temporaryLibraryURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let json = """
        {
          "schemaVersion": 1,
          "trackRecords": [
            {
              "track": {
                "id": "track-1",
                "title": "Legacy",
                "durationSec": 180,
                "format": "wav"
              },
              "filePath": "/Music/legacy.wav",
              "addedAt": "2026-05-25T00:00:00Z",
              "updatedAt": "2026-05-25T00:00:00Z"
            }
          ],
          "currentPlaylistTrackIds": ["track-1"],
          "userPlaylists": [],
          "selectedUserPlaylistId": ""
        }
        """
        try Data(json.utf8).write(to: fileURL)

        let loaded = try NativeLibraryStore(fileURL: fileURL).load()

        #expect(loaded.trackRecords.first?.id == "track-1")
        #expect(loaded.trackRecords.first?.missing == false)
        #expect(loaded.trackRecords.first?.sourceFolderPath == nil)
        #expect(loaded.trackRecords.first?.preparation == .empty)
        #expect(loaded.sourceFolders.isEmpty)
        #expect(loaded.currentPlaylistTrackIds == ["track-1"])
    }

    @Test func saveWritesBackupAndLoadFallsBackWhenPrimaryIsCorrupt() throws {
        let fileURL = temporaryLibraryURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let savedSet = UserPlaylist(
            id: "set-1",
            name: "Late Night",
            trackIds: ["track-1"],
            createdAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z"
        )
        let state = NativeLibraryState(
            trackRecords: [trackRecord(id: "track-1", title: "Recovered Track", path: "/Music/recovered.wav")],
            currentPlaylistTrackIds: ["track-1"],
            userPlaylists: [savedSet],
            selectedUserPlaylistId: "set-1"
        )

        let store = NativeLibraryStore(fileURL: fileURL)
        try store.save(state)
        #expect(FileManager.default.fileExists(atPath: store.backupFileURL.path))

        try Data("{not-json".utf8).write(to: fileURL)
        let loaded = try store.load()

        #expect(loaded.trackRecords.map(\.id) == ["track-1"])
        #expect(loaded.currentPlaylistTrackIds == ["track-1"])
        #expect(loaded.userPlaylists.first?.name == "Late Night")
        #expect(loaded.selectedUserPlaylistId == "set-1")
    }

    @Test func loadFallsBackToBackupWhenPrimaryIsMissing() throws {
        let fileURL = temporaryLibraryURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let state = NativeLibraryState(
            trackRecords: [trackRecord(id: "track-1", title: "Backup Only", path: "/Music/backup-only.wav")],
            currentPlaylistTrackIds: ["track-1"]
        )
        let store = NativeLibraryStore(fileURL: fileURL)
        try store.save(state)

        try FileManager.default.removeItem(at: fileURL)
        let loaded = try store.load()

        #expect(loaded.trackRecords.first?.track.title == "Backup Only")
        #expect(loaded.currentPlaylistTrackIds == ["track-1"])
    }

    private func temporaryLibraryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("native-library.json")
    }

    private func trackRecord(id: String, title: String, path: String) -> NativeTrackRecord {
        NativeTrackRecord(
            track: Track(
                id: id,
                title: title,
                durationSec: 180,
                format: path.hasSuffix(".mp3") ? .mp3 : .wav,
                bpm: 128
            ),
            filePath: path,
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z"
        )
    }
}
