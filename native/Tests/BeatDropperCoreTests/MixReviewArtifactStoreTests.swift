import BeatDropperCore
import Foundation
import Testing

struct MixReviewArtifactStoreTests {
    @Test func saveAndLoadPersistsImportedReviewArtifacts() throws {
        let store = MixReviewArtifactStore(fileURL: temporaryDirectory().appendingPathComponent("mix-review-artifacts.json"))
        let artifact = PersistedMixReviewArtifact(
            id: UUID().uuidString,
            importedAt: "2026-06-17T00:00:00Z",
            fileName: "BeatDropper-Mix-Review-Notes.json",
            format: "JSON",
            content: "{ \"schemaVersion\": 1 }",
            reviewCount: 2,
            schemaVersion: 1,
            trackPairs: [
                MixReviewArtifactTrackPair(currentTrackId: "current", nextTrackId: "next")
            ],
            reviewAnnotation: "Check the vocal handoff before using this pair again."
        )

        try store.save(MixReviewArtifactState(artifacts: [artifact]))
        let loaded = try store.load()

        #expect(loaded.schemaVersion == mixReviewArtifactStateSchemaVersion)
        #expect(loaded.artifacts == [artifact])
        #expect(loaded.artifacts.first?.trackPairs.first?.currentTrackId == "current")
        #expect(loaded.artifacts.first?.reviewAnnotation == "Check the vocal handoff before using this pair again.")
        #expect(FileManager.default.fileExists(atPath: store.backupFileURL.path))
    }

    @Test func loadFallsBackToBackupWhenPrimaryIsMissing() throws {
        let store = MixReviewArtifactStore(fileURL: temporaryDirectory().appendingPathComponent("mix-review-artifacts.json"))
        let artifact = PersistedMixReviewArtifact(
            id: UUID().uuidString,
            importedAt: "2026-06-17T00:00:00Z",
            fileName: "BeatDropper-Mix-Review-Notes.md",
            format: "Markdown",
            content: "# BeatDropper Mix Review Notes",
            reviewCount: 1,
            schemaVersion: 1
        )

        try store.save(MixReviewArtifactState(artifacts: [artifact]))
        try FileManager.default.removeItem(at: store.fileURL)

        let loaded = try store.load()

        #expect(loaded.artifacts == [artifact])
    }

    @Test func sanitizeCapsArtifactsAtRecentTwelve() {
        let artifacts = (0..<14).map { index in
            PersistedMixReviewArtifact(
                id: UUID().uuidString,
                importedAt: "2026-06-17T00:00:00Z",
                fileName: "notes-\(index).json",
                format: "JSON",
                content: "{}",
                reviewCount: index,
                schemaVersion: 1
            )
        }

        let sanitized = MixReviewArtifactStore.sanitized(
            MixReviewArtifactState(schemaVersion: 99, artifacts: artifacts)
        )

        #expect(sanitized.schemaVersion == mixReviewArtifactStateSchemaVersion)
        #expect(sanitized.artifacts.count == 12)
        #expect(sanitized.artifacts.first?.fileName == "notes-0.json")
    }

    @Test func sanitizeCapsReviewAnnotations() {
        let annotation = String(repeating: "a", count: mixReviewArtifactAnnotationCharacterLimit + 8)
        let artifact = PersistedMixReviewArtifact(
            id: UUID().uuidString,
            importedAt: "2026-06-17T00:00:00Z",
            fileName: "notes.json",
            format: "JSON",
            content: "{}",
            reviewCount: 1,
            reviewAnnotation: annotation
        )

        let sanitized = MixReviewArtifactStore.sanitized(MixReviewArtifactState(artifacts: [artifact]))

        #expect(sanitized.artifacts.first?.reviewAnnotation.count == mixReviewArtifactAnnotationCharacterLimit)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperMixReviewArtifactStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
