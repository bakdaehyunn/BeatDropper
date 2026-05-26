import BeatDropperCore
import Testing

struct NativeLibraryReconcilerTests {
    @Test func relinksMovedTrackByFingerprintAndKeepsSavedSetIdStable() {
        let existing = NativeTrackRecord(
            track: Track(id: "stable-track", title: "Same Song", durationSec: 180, format: .wav, bpm: 128),
            filePath: "/Music/Old/Same Song.wav",
            sourceFolderPath: "/Music/Old",
            fileFingerprint: "same-song|wav|180000|123456",
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z",
            preparation: TrackPreparation(
                bpmOverride: 127.5,
                hotCues: [TrackPreparationCue(id: "drop", kind: .drop, timeSec: 64, label: "Drop")]
            )
        )
        let imported = NativeLibraryImportItem(
            track: Track(id: "path-generated-new-id", title: "Same Song", durationSec: 180, format: .wav),
            filePath: "/Music/New/Same Song.wav",
            sourceFolderPath: "/Music/New",
            fileFingerprint: "same-song|wav|180000|123456"
        )

        let result = NativeLibraryReconciler.upsert(
            existingRecords: [existing],
            existingSourceFolders: [],
            imported: [imported],
            sourceFolder: NativeLibrarySourceFolderInput(path: "/Music/New", displayName: "New"),
            now: "2026-05-26T00:00:00Z"
        )

        #expect(result.trackRecords.count == 1)
        #expect(result.trackRecords.first?.id == "stable-track")
        #expect(result.trackRecords.first?.filePath == "/Music/New/Same Song.wav")
        #expect(result.trackRecords.first?.track.bpm == 128)
        #expect(result.trackRecords.first?.missing == false)
        #expect(result.trackRecords.first?.preparation.bpmOverride == 127.5)
        #expect(result.trackRecords.first?.preparation.hotCues.first?.id == "drop")
        #expect(result.resolvedTrackIdByImportId["path-generated-new-id"] == "stable-track")
    }

    @Test func rescanMarksSourceTracksMissingWhenTheyDisappear() {
        let first = NativeTrackRecord(
            track: Track(id: "kept", title: "Kept", durationSec: 180, format: .wav),
            filePath: "/Music/Set/Kept.wav",
            sourceFolderPath: "/Music/Set",
            fileFingerprint: "kept|wav|180000|1",
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z"
        )
        let missing = NativeTrackRecord(
            track: Track(id: "missing", title: "Missing", durationSec: 180, format: .wav),
            filePath: "/Music/Set/Missing.wav",
            sourceFolderPath: "/Music/Set",
            fileFingerprint: "missing|wav|180000|2",
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z"
        )
        let imported = NativeLibraryImportItem(
            track: Track(id: "kept-new-path-id", title: "Kept", durationSec: 180, format: .wav),
            filePath: "/Music/Set/Kept.wav",
            sourceFolderPath: "/Music/Set",
            fileFingerprint: "kept|wav|180000|1"
        )

        let result = NativeLibraryReconciler.upsert(
            existingRecords: [first, missing],
            existingSourceFolders: [],
            imported: [imported],
            sourceFolder: NativeLibrarySourceFolderInput(path: "/Music/Set", displayName: "Set"),
            now: "2026-05-26T00:00:00Z"
        )

        let recordsById = Dictionary(uniqueKeysWithValues: result.trackRecords.map { ($0.id, $0) })
        #expect(recordsById["kept"]?.missing == false)
        #expect(recordsById["missing"]?.missing == true)
        #expect(recordsById["missing"]?.missingAt == "2026-05-26T00:00:00Z")
        #expect(result.sourceFolders.first?.trackCount == 1)
        #expect(result.sourceFolders.first?.missing == false)
    }

    @Test func marksEntireSourceFolderMissingWithoutDroppingTasteReferences() {
        let record = NativeTrackRecord(
            track: Track(id: "track-1", title: "Track", durationSec: 180, format: .mp3),
            filePath: "/Music/Gone/Track.mp3",
            sourceFolderPath: "/Music/Gone",
            fileFingerprint: "track|mp3|180000|123",
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z"
        )
        let folder = NativeLibrarySourceFolder(
            path: "/Music/Gone",
            displayName: "Gone",
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z",
            lastScannedAt: "2026-05-25T00:00:00Z",
            trackCount: 1
        )

        let result = NativeLibraryReconciler.markSourceFolderMissing(
            existingRecords: [record],
            existingSourceFolders: [folder],
            sourceFolderPath: "/Music/Gone",
            now: "2026-05-26T00:00:00Z"
        )

        #expect(result.trackRecords.first?.id == "track-1")
        #expect(result.trackRecords.first?.missing == true)
        #expect(result.sourceFolders.first?.missing == true)
        #expect(result.sourceFolders.first?.missingAt == "2026-05-26T00:00:00Z")
    }

    @Test func explicitTrackRelinkPreservesTasteIdAndClearsMissingState() {
        let record = NativeTrackRecord(
            track: Track(id: "stable-track", title: "Original", durationSec: 180, format: .wav, bpm: 126),
            filePath: "/Music/Gone/Original.wav",
            sourceFolderPath: "/Music/Gone",
            fileFingerprint: "original|wav|180000|123",
            missing: true,
            missingAt: "2026-05-25T00:00:00Z",
            addedAt: "2026-05-24T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z",
            preparation: TrackPreparation(
                bpmOverride: 125.5,
                hotCues: [TrackPreparationCue(id: "intro", kind: .intro, timeSec: 8, label: "Intro")]
            )
        )
        let missingFolder = NativeLibrarySourceFolder(
            path: "/Music/Gone",
            displayName: "Gone",
            addedAt: "2026-05-24T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z",
            lastScannedAt: "2026-05-25T00:00:00Z",
            trackCount: 1,
            missing: true,
            missingAt: "2026-05-25T00:00:00Z"
        )
        let replacement = NativeLibraryImportItem(
            track: Track(id: "replacement-path-id", title: "Original", durationSec: 181, format: .wav),
            filePath: "/Music/Relinked/Original.wav",
            sourceFolderPath: "/Music/Relinked",
            fileFingerprint: "original|wav|181000|456"
        )

        let result = NativeLibraryReconciler.relinkTrack(
            existingRecords: [record],
            existingSourceFolders: [missingFolder],
            trackId: "stable-track",
            replacement: replacement,
            sourceFolder: NativeLibrarySourceFolderInput(path: "/Music/Relinked", displayName: "Relinked"),
            now: "2026-05-26T00:00:00Z"
        )

        #expect(result.trackRecords.count == 1)
        #expect(result.trackRecords.first?.id == "stable-track")
        #expect(result.trackRecords.first?.filePath == "/Music/Relinked/Original.wav")
        #expect(result.trackRecords.first?.sourceFolderPath == "/Music/Relinked")
        #expect(result.trackRecords.first?.track.bpm == 126)
        #expect(result.trackRecords.first?.missing == false)
        #expect(result.trackRecords.first?.missingAt == nil)
        #expect(result.trackRecords.first?.preparation.bpmOverride == 125.5)
        #expect(result.trackRecords.first?.preparation.hotCues.first?.kind == .intro)
        #expect(result.resolvedTrackIdByImportId["replacement-path-id"] == "stable-track")
        #expect(result.sourceFolders.map(\.path) == ["/Music/Relinked"])
        #expect(result.sourceFolders.first?.trackCount == 1)
        #expect(result.sourceFolders.first?.missing == false)
    }
}
