import BeatDropperCore
import Testing

struct NativeLibraryBrowserIndexTests {
    @Test func buildsSortedRowsWithCachedSourceNamesAndSearchKeys() {
        let folder = NativeLibrarySourceFolder(
            path: "/Music/Peak",
            displayName: "Peak Hour",
            addedAt: "2026-05-25T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z",
            lastScannedAt: "2026-05-25T00:00:00Z",
            trackCount: 2
        )
        let records = [
            NativeTrackRecord(
                track: Track(id: "b", title: "Zulu", durationSec: 180, format: .wav, bpm: 130),
                filePath: "/Music/Peak/Zulu.wav",
                sourceFolderPath: "/Music/Peak",
                fileFingerprint: "zulu|wav|180000|2",
                addedAt: "2026-05-25T00:00:00Z",
                updatedAt: "2026-05-25T00:00:00Z"
            ),
            NativeTrackRecord(
                track: Track(id: "a", title: "Alpha", durationSec: 210, format: .mp3, bpm: 126),
                filePath: "/Loose/Alpha.mp3",
                addedAt: "2026-05-25T00:00:00Z",
                updatedAt: "2026-05-25T00:00:00Z"
            )
        ]

        let rows = NativeLibraryBrowserIndex.build(records: records, sourceFolders: [folder])

        #expect(rows.map(\.id) == ["a", "b"])
        #expect(rows[0].sourceDisplayName == "Files")
        #expect(rows[1].sourceDisplayName == "Peak Hour")
        #expect(rows[1].searchKey.contains("zulu.wav"))
        #expect(rows[1].searchKey.contains("130"))
    }

    @Test func filtersRowsByMultipleCachedTerms() {
        let rows = [
            NativeLibraryBrowserTrack(
                track: Track(id: "one", title: "First", durationSec: 180, format: .wav),
                filePath: "/Music/First.wav",
                sourceFolderPath: "/Music",
                fileFingerprint: nil,
                sourceDisplayName: "Warmup",
                missing: false,
                missingAt: nil,
                searchKey: "first first.wav warmup wav ready"
            ),
            NativeLibraryBrowserTrack(
                track: Track(id: "two", title: "Second", durationSec: 180, format: .wav),
                filePath: "/Music/Second.wav",
                sourceFolderPath: "/Music",
                fileFingerprint: nil,
                sourceDisplayName: "Peak",
                missing: true,
                missingAt: "2026-05-25T00:00:00Z",
                searchKey: "second second.wav peak wav missing"
            )
        ]

        #expect(NativeLibraryBrowserIndex.filter(rows, query: "peak missing").map(\.id) == ["two"])
        #expect(NativeLibraryBrowserIndex.filter(rows, query: "wav").map(\.id) == ["one", "two"])
        #expect(NativeLibraryBrowserIndex.filter(rows, query: "third").isEmpty)
    }
}
