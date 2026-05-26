import BeatDropperCore
import Testing

struct NativeLibraryStressTests {
    @Test func stressSuitePreservesLargeLibraryTasteReferencesAcrossMovedFolder() throws {
        let summary = try NativeLibraryStressSuite.run(trackCount: 256)

        #expect(summary.trackCount == 256)
        #expect(summary.indexedCount == 256)
        #expect(summary.missingCount == 256)
        #expect(summary.relinkedCount == 256)
        #expect(summary.stablePlaylistReferenceCount == 64)
        #expect(summary.savedSetCount >= 3)
        #expect(summary.searchHitCount > 0)
    }
}
