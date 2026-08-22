import Foundation
import BeatDropperDomain

public struct NativeLibraryImportItem: Hashable, Sendable {
    public var track: Track
    public var filePath: String
    public var sourceFolderPath: String?
    public var fileFingerprint: String?

    public init(
        track: Track,
        filePath: String,
        sourceFolderPath: String? = nil,
        fileFingerprint: String? = nil
    ) {
        self.track = track
        self.filePath = filePath
        self.sourceFolderPath = sourceFolderPath
        self.fileFingerprint = fileFingerprint
    }
}

public struct NativeLibrarySourceFolderInput: Hashable, Sendable {
    public var path: String
    public var displayName: String

    public init(path: String, displayName: String) {
        self.path = path
        self.displayName = displayName
    }
}

public struct NativeLibraryUpsertResult: Hashable, Sendable {
    public var trackRecords: [NativeTrackRecord]
    public var sourceFolders: [NativeLibrarySourceFolder]
    public var resolvedTrackIdByImportId: [String: String]

    public init(
        trackRecords: [NativeTrackRecord],
        sourceFolders: [NativeLibrarySourceFolder],
        resolvedTrackIdByImportId: [String: String]
    ) {
        self.trackRecords = trackRecords
        self.sourceFolders = sourceFolders
        self.resolvedTrackIdByImportId = resolvedTrackIdByImportId
    }
}

public enum NativeLibraryReconciler {
    public static func upsert(
        existingRecords: [NativeTrackRecord],
        existingSourceFolders: [NativeLibrarySourceFolder],
        imported: [NativeLibraryImportItem],
        sourceFolder: NativeLibrarySourceFolderInput?,
        now: String
    ) -> NativeLibraryUpsertResult {
        var recordsById: [String: NativeTrackRecord] = [:]
        var orderedIds: [String] = []
        var pathToId: [String: String] = [:]
        var fingerprintToId: [String: String] = [:]
        for record in existingRecords {
            if recordsById[record.id] == nil {
                orderedIds.append(record.id)
            }
            recordsById[record.id] = record
            pathToId[normalizedPath(record.filePath)] = record.id
            if let fingerprint = normalizedOptional(record.fileFingerprint), fingerprintToId[fingerprint] == nil {
                fingerprintToId[fingerprint] = record.id
            }
        }

        var resolvedTrackIdByImportId: [String: String] = [:]
        var seenImportedIdsForSourceFolder = Set<String>()

        for item in imported {
            guard !item.track.id.isEmpty, !item.filePath.isEmpty else {
                continue
            }

            let originalImportId = item.track.id
            let normalizedFilePath = normalizedPath(item.filePath)
            let fingerprint = normalizedOptional(item.fileFingerprint)
            let resolvedId = pathToId[normalizedFilePath]
                ?? fingerprint.flatMap { fingerprintToId[$0] }
                ?? originalImportId

            var track = item.track
            track.id = resolvedId
            if track.bpm == nil, let existingBPM = recordsById[resolvedId]?.track.bpm {
                track.bpm = existingBPM
            }

            let existing = recordsById[resolvedId]
            let record = NativeTrackRecord(
                track: track,
                filePath: item.filePath,
                sourceFolderPath: item.sourceFolderPath ?? existing?.sourceFolderPath,
                fileFingerprint: fingerprint ?? existing?.fileFingerprint,
                missing: false,
                missingAt: nil,
                addedAt: existing?.addedAt ?? now,
                updatedAt: now,
                preparation: existing?.preparation ?? .empty
            )

            if existing == nil && !orderedIds.contains(resolvedId) {
                orderedIds.append(resolvedId)
            }
            recordsById[resolvedId] = record
            pathToId[normalizedFilePath] = resolvedId
            if let fingerprint {
                fingerprintToId[fingerprint] = resolvedId
            }
            resolvedTrackIdByImportId[originalImportId] = resolvedId
            if item.sourceFolderPath != nil {
                seenImportedIdsForSourceFolder.insert(resolvedId)
            }
        }

        if let sourceFolder {
            for id in orderedIds {
                guard var record = recordsById[id],
                      normalizedPath(record.sourceFolderPath ?? "") == normalizedPath(sourceFolder.path),
                      !seenImportedIdsForSourceFolder.contains(id)
                else {
                    continue
                }
                record.missing = true
                record.missingAt = record.missingAt ?? now
                record.updatedAt = now
                recordsById[id] = record
            }
        }

        var sourceFolders = upsertSourceFolder(
            existing: existingSourceFolders,
            sourceFolder: sourceFolder,
            trackCount: imported.count,
            now: now
        )

        let orderedRecords = orderedIds.compactMap { recordsById[$0] }
        sourceFolders = sourceFolders.filter { !$0.path.isEmpty }

        return NativeLibraryUpsertResult(
            trackRecords: orderedRecords,
            sourceFolders: sourceFolders,
            resolvedTrackIdByImportId: resolvedTrackIdByImportId
        )
    }

    public static func relinkTrack(
        existingRecords: [NativeTrackRecord],
        existingSourceFolders: [NativeLibrarySourceFolder],
        trackId: String,
        replacement: NativeLibraryImportItem,
        sourceFolder: NativeLibrarySourceFolderInput?,
        now: String
    ) -> NativeLibraryUpsertResult {
        guard let recordIndex = existingRecords.firstIndex(where: { $0.id == trackId }) else {
            return upsert(
                existingRecords: existingRecords,
                existingSourceFolders: existingSourceFolders,
                imported: [replacement],
                sourceFolder: sourceFolder,
                now: now
            )
        }

        var records = existingRecords
        let existing = records[recordIndex]
        var track = replacement.track
        track.id = existing.id
        if track.bpm == nil {
            track.bpm = existing.track.bpm
        }

        let replacementSourceFolderPath = replacement.sourceFolderPath ?? sourceFolder?.path
        records[recordIndex] = NativeTrackRecord(
            track: track,
            filePath: replacement.filePath,
            sourceFolderPath: replacementSourceFolderPath,
            fileFingerprint: normalizedOptional(replacement.fileFingerprint) ?? existing.fileFingerprint,
            missing: false,
            missingAt: nil,
            addedAt: existing.addedAt,
            updatedAt: now,
            preparation: existing.preparation
        )

        var sourceFolders = existingSourceFolders
        if let sourceFolder {
            let trackCount = records.filter {
                normalizedPath($0.sourceFolderPath ?? "") == normalizedPath(sourceFolder.path) &&
                    !$0.missing
            }.count
            sourceFolders = upsertSourceFolder(
                existing: sourceFolders,
                sourceFolder: sourceFolder,
                trackCount: trackCount,
                now: now
            )
        }
        sourceFolders = pruneUnreferencedMissingSourceFolders(sourceFolders, records: records)

        return NativeLibraryUpsertResult(
            trackRecords: records,
            sourceFolders: sourceFolders,
            resolvedTrackIdByImportId: [replacement.track.id: existing.id]
        )
    }

    public static func markSourceFolderMissing(
        existingRecords: [NativeTrackRecord],
        existingSourceFolders: [NativeLibrarySourceFolder],
        sourceFolderPath: String,
        now: String
    ) -> NativeLibraryUpsertResult {
        let normalizedSourcePath = normalizedPath(sourceFolderPath)
        let records = existingRecords.map { record in
            guard normalizedPath(record.sourceFolderPath ?? "") == normalizedSourcePath else {
                return record
            }
            var missingRecord = record
            missingRecord.missing = true
            missingRecord.missingAt = missingRecord.missingAt ?? now
            missingRecord.updatedAt = now
            return missingRecord
        }
        let sourceFolders = existingSourceFolders.map { folder in
            guard normalizedPath(folder.path) == normalizedSourcePath else {
                return folder
            }
            var missingFolder = folder
            missingFolder.missing = true
            missingFolder.missingAt = missingFolder.missingAt ?? now
            missingFolder.updatedAt = now
            return missingFolder
        }

        return NativeLibraryUpsertResult(
            trackRecords: records,
            sourceFolders: sourceFolders,
            resolvedTrackIdByImportId: [:]
        )
    }

    private static func upsertSourceFolder(
        existing: [NativeLibrarySourceFolder],
        sourceFolder: NativeLibrarySourceFolderInput?,
        trackCount: Int,
        now: String
    ) -> [NativeLibrarySourceFolder] {
        guard let sourceFolder else {
            return existing
        }

        var foldersById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var orderedIds = existing.map(\.id)
        let id = sourceFolder.path
        let existingFolder = foldersById[id]
        let folder = NativeLibrarySourceFolder(
            path: sourceFolder.path,
            displayName: sourceFolder.displayName,
            addedAt: existingFolder?.addedAt ?? now,
            updatedAt: now,
            lastScannedAt: now,
            trackCount: trackCount,
            missing: false,
            missingAt: nil
        )
        if existingFolder == nil {
            orderedIds.append(id)
        }
        foldersById[id] = folder
        return orderedIds.compactMap { foldersById[$0] }
    }

    private static func pruneUnreferencedMissingSourceFolders(
        _ sourceFolders: [NativeLibrarySourceFolder],
        records: [NativeTrackRecord]
    ) -> [NativeLibrarySourceFolder] {
        let referencedSourcePaths = Set(records.compactMap { record -> String? in
            guard let sourceFolderPath = normalizedOptional(record.sourceFolderPath) else {
                return nil
            }
            return normalizedPath(sourceFolderPath)
        })
        return sourceFolders.filter { folder in
            !folder.missing || referencedSourcePaths.contains(normalizedPath(folder.path))
        }
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
