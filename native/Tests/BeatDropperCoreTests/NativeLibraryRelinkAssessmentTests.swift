import BeatDropperCore
import Testing

struct NativeLibraryRelinkAssessmentTests {
    @Test func exactFingerprintMatchDoesNotRequireConfirmation() {
        let assessment = NativeLibraryRelinkAssessment.assess(
            existing: record(
                title: "Same Track",
                durationSec: 180,
                format: .wav,
                fingerprint: "same-track|wav|180000|123"
            ),
            replacement: item(
                title: "Same Track",
                durationSec: 180,
                format: .wav,
                fingerprint: "same-track|wav|180000|123"
            )
        )

        #expect(assessment.level == .exact)
        #expect(assessment.requiresUserConfirmation == false)
        #expect(assessment.reasons.contains("file fingerprint matches"))
    }

    @Test func closeTitleAndDurationIsStrongWithoutConfirmation() {
        let assessment = NativeLibraryRelinkAssessment.assess(
            existing: record(title: "Artist - Night Drive", durationSec: 241, format: .mp3),
            replacement: item(title: "Artist Night Drive", durationSec: 242, format: .mp3)
        )

        #expect(assessment.level >= .strong)
        #expect(assessment.requiresUserConfirmation == false)
    }

    @Test func mismatchedTitleAndDurationRequiresConfirmation() {
        let assessment = NativeLibraryRelinkAssessment.assess(
            existing: record(title: "Original Track", durationSec: 180, format: .wav),
            replacement: item(title: "Different Song", durationSec: 420, format: .mp3)
        )

        #expect(assessment.level == .conflict)
        #expect(assessment.requiresUserConfirmation == true)
        #expect(assessment.warnings.contains { $0.contains("title does not match") })
        #expect(assessment.warnings.contains { $0.contains("duration differs") })
    }

    @Test func folderRelinkWithExactMatchesDoesNotRequireConfirmation() {
        let records = [
            record(title: "One", durationSec: 180, format: .wav, fingerprint: "one|wav|180000|1"),
            record(title: "Two", durationSec: 181, format: .wav, fingerprint: "two|wav|181000|2")
        ]
        let imported = [
            item(title: "One", durationSec: 180, format: .wav, fingerprint: "one|wav|180000|1"),
            item(title: "Two", durationSec: 181, format: .wav, fingerprint: "two|wav|181000|2")
        ]

        let assessment = NativeLibraryRelinkAssessment.assessFolder(
            existingRecords: records,
            sourceFolderPath: "/Old",
            imported: imported
        )

        #expect(assessment.level == .exact)
        #expect(assessment.matchedTrackCount == 2)
        #expect(assessment.exactMatchCount == 2)
        #expect(assessment.requiresUserConfirmation == false)
    }

    @Test func folderRelinkWithWeakCoverageRequiresConfirmation() {
        let records = [
            record(title: "One", durationSec: 180, format: .wav),
            record(title: "Two", durationSec: 181, format: .wav),
            record(title: "Three", durationSec: 182, format: .wav)
        ]
        let imported = [
            item(title: "One", durationSec: 180, format: .wav),
            item(title: "Completely Different", durationSec: 360, format: .mp3)
        ]

        let assessment = NativeLibraryRelinkAssessment.assessFolder(
            existingRecords: records,
            sourceFolderPath: "/Old",
            imported: imported
        )

        #expect(assessment.level <= .likely)
        #expect(assessment.requiresUserConfirmation == true)
        #expect(assessment.warnings.contains { $0.contains("selected folder has 2 tracks") })
    }

    private func record(
        title: String,
        durationSec: Double,
        format: AudioFormat,
        fingerprint: String? = nil
    ) -> NativeTrackRecord {
        NativeTrackRecord(
            track: Track(id: "existing", title: title, durationSec: durationSec, format: format, bpm: 128),
            filePath: "/Old/\(title).\(format.rawValue)",
            sourceFolderPath: "/Old",
            fileFingerprint: fingerprint,
            missing: true,
            missingAt: "2026-05-25T00:00:00Z",
            addedAt: "2026-05-24T00:00:00Z",
            updatedAt: "2026-05-25T00:00:00Z"
        )
    }

    private func item(
        title: String,
        durationSec: Double,
        format: AudioFormat,
        fingerprint: String? = nil
    ) -> NativeLibraryImportItem {
        NativeLibraryImportItem(
            track: Track(id: "replacement", title: title, durationSec: durationSec, format: format),
            filePath: "/New/\(title).\(format.rawValue)",
            sourceFolderPath: "/New",
            fileFingerprint: fingerprint
        )
    }
}
