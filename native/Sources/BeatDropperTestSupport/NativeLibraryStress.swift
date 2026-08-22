import Foundation
import BeatDropperDomain
import BeatDropperLibrary
import BeatDropperPlatform

public struct NativeLibraryStressSummary: Sendable {
    public var trackCount: Int
    public var savedSetCount: Int
    public var indexedCount: Int
    public var searchHitCount: Int
    public var missingCount: Int
    public var relinkedCount: Int
    public var stablePlaylistReferenceCount: Int
    public var durationMs: Double

    public init(
        trackCount: Int,
        savedSetCount: Int,
        indexedCount: Int,
        searchHitCount: Int,
        missingCount: Int,
        relinkedCount: Int,
        stablePlaylistReferenceCount: Int,
        durationMs: Double
    ) {
        self.trackCount = trackCount
        self.savedSetCount = savedSetCount
        self.indexedCount = indexedCount
        self.searchHitCount = searchHitCount
        self.missingCount = missingCount
        self.relinkedCount = relinkedCount
        self.stablePlaylistReferenceCount = stablePlaylistReferenceCount
        self.durationMs = durationMs
    }
}

public enum NativeLibraryStressError: Error, LocalizedError {
    case persistenceMismatch(String)
    case indexMismatch(String)
    case missingMarkMismatch(String)
    case relinkMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .persistenceMismatch(let message):
            return "persistence mismatch: \(message)"
        case .indexMismatch(let message):
            return "index mismatch: \(message)"
        case .missingMarkMismatch(let message):
            return "missing mark mismatch: \(message)"
        case .relinkMismatch(let message):
            return "relink mismatch: \(message)"
        }
    }
}

public enum NativeLibraryStressSuite {
    public static func run(trackCount: Int = 1_200) throws -> NativeLibraryStressSummary {
        let startTime = DispatchTime.now().uptimeNanoseconds
        let safeTrackCount = max(64, trackCount)
        let timestamp = "2026-05-26T00:00:00Z"
        let oldFolderPath = "/Music/BeatDropper/Peak"
        let newFolderPath = "/Volumes/USB/BeatDropper/Peak"
        let oldFolder = NativeLibrarySourceFolder(
            path: oldFolderPath,
            displayName: "Peak",
            addedAt: timestamp,
            updatedAt: timestamp,
            lastScannedAt: timestamp,
            trackCount: safeTrackCount
        )
        let records = makeRecords(count: safeTrackCount, folderPath: oldFolderPath, timestamp: timestamp)
        let savedSets = makeSavedSets(records: records, timestamp: timestamp)
        let currentSetIds = Array(records.prefix(64).map(\.id))

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatDropperNativeLibraryStress-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = NativeLibraryStore(fileURL: rootURL.appendingPathComponent("native-library.json"))
        try store.save(NativeLibraryState(
            trackRecords: records,
            sourceFolders: [oldFolder],
            currentPlaylistTrackIds: currentSetIds,
            userPlaylists: savedSets,
            selectedUserPlaylistId: savedSets.first?.id ?? ""
        ))
        let loaded = try store.load()
        guard loaded.trackRecords.count == safeTrackCount,
              loaded.currentPlaylistTrackIds == currentSetIds,
              loaded.userPlaylists.count == savedSets.count
        else {
            throw NativeLibraryStressError.persistenceMismatch("saved native library state did not round-trip")
        }

        let index = NativeLibraryBrowserIndex.build(
            records: loaded.trackRecords,
            sourceFolders: loaded.sourceFolders
        )
        let searchHits = NativeLibraryBrowserIndex.filter(index, query: "peak 120")
        guard index.count == safeTrackCount, !searchHits.isEmpty else {
            throw NativeLibraryStressError.indexMismatch("large library index/search did not return expected rows")
        }

        let missingResult = NativeLibraryReconciler.markSourceFolderMissing(
            existingRecords: loaded.trackRecords,
            existingSourceFolders: loaded.sourceFolders,
            sourceFolderPath: oldFolderPath,
            now: timestamp
        )
        let missingCount = missingResult.trackRecords.filter(\.missing).count
        guard missingCount == safeTrackCount,
              missingResult.sourceFolders.first?.missing == true
        else {
            throw NativeLibraryStressError.missingMarkMismatch("source folder missing state was not applied to all records")
        }

        let movedImports = makeMovedImports(records: records, newFolderPath: newFolderPath)
        let assessment = NativeLibraryRelinkAssessment.assessFolder(
            existingRecords: missingResult.trackRecords,
            sourceFolderPath: oldFolderPath,
            imported: movedImports
        )
        guard assessment.level == .exact,
              assessment.exactMatchCount == safeTrackCount,
              !assessment.requiresUserConfirmation
        else {
            throw NativeLibraryStressError.relinkMismatch("folder relink assessment did not recognize exact moved library")
        }

        let relinkResult = NativeLibraryReconciler.upsert(
            existingRecords: missingResult.trackRecords,
            existingSourceFolders: missingResult.sourceFolders,
            imported: movedImports,
            sourceFolder: NativeLibrarySourceFolderInput(path: newFolderPath, displayName: "Peak"),
            now: timestamp
        )
        let relinkedRecordsById = Dictionary(uniqueKeysWithValues: relinkResult.trackRecords.map { ($0.id, $0) })
        let relinkedCount = relinkResult.trackRecords.filter {
            !$0.missing && $0.sourceFolderPath == newFolderPath
        }.count
        let stableReferenceCount = currentSetIds.filter { relinkedRecordsById[$0] != nil }.count
        guard relinkedCount == safeTrackCount,
              stableReferenceCount == currentSetIds.count,
              relinkResult.resolvedTrackIdByImportId.count == safeTrackCount
        else {
            throw NativeLibraryStressError.relinkMismatch("moved folder reconciliation did not preserve stable track ids")
        }

        let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000
        return NativeLibraryStressSummary(
            trackCount: safeTrackCount,
            savedSetCount: savedSets.count,
            indexedCount: index.count,
            searchHitCount: searchHits.count,
            missingCount: missingCount,
            relinkedCount: relinkedCount,
            stablePlaylistReferenceCount: stableReferenceCount,
            durationMs: durationMs
        )
    }

    private static func makeRecords(
        count: Int,
        folderPath: String,
        timestamp: String
    ) -> [NativeTrackRecord] {
        (0..<count).map { index in
            let number = String(format: "%04d", index)
            let format: AudioFormat = index.isMultiple(of: 3) ? .mp3 : .wav
            let duration = 180 + Double(index % 96)
            return NativeTrackRecord(
                track: Track(
                    id: "stress-track-\(number)",
                    title: "Peak Track \(number)",
                    durationSec: duration,
                    format: format,
                    bpm: 120 + Double(index % 12)
                ),
                filePath: "\(folderPath)/Peak Track \(number).\(format.rawValue)",
                sourceFolderPath: folderPath,
                fileFingerprint: fingerprint(index: index, duration: duration, format: format),
                addedAt: timestamp,
                updatedAt: timestamp
            )
        }
    }

    private static func makeMovedImports(
        records: [NativeTrackRecord],
        newFolderPath: String
    ) -> [NativeLibraryImportItem] {
        records.enumerated().map { index, record in
            let fileName = URL(fileURLWithPath: record.filePath).lastPathComponent
            return NativeLibraryImportItem(
                track: Track(
                    id: "moved-path-id-\(index)",
                    title: record.track.title,
                    durationSec: record.track.durationSec,
                    format: record.track.format,
                    bpm: nil
                ),
                filePath: "\(newFolderPath)/\(fileName)",
                sourceFolderPath: newFolderPath,
                fileFingerprint: record.fileFingerprint
            )
        }
    }

    private static func makeSavedSets(records: [NativeTrackRecord], timestamp: String) -> [UserPlaylist] {
        stride(from: 0, to: records.count, by: 80).enumerated().map { setIndex, startIndex in
            let ids = records.dropFirst(startIndex).prefix(32).map(\.id)
            return UserPlaylist(
                id: "stress-set-\(setIndex)",
                name: "Stress Set \(setIndex + 1)",
                trackIds: Array(ids),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
    }

    private static func fingerprint(index: Int, duration: Double, format: AudioFormat) -> String {
        let durationMs = Int((duration * 1_000).rounded())
        return "peak-track-\(index)|\(format.rawValue)|\(durationMs)|\(1_000_000 + index)"
    }
}
