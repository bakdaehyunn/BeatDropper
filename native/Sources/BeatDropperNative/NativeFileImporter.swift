import AppKit
import AVFoundation
import BeatDropperCore
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct ImportedTrack: Identifiable, Hashable, Sendable {
    var id: String { track.id }
    var track: Track
    var url: URL
    var sourceFolderPath: String?
    var fileFingerprint: String?
    var missing: Bool
    var missingAt: String?
}

struct NativeOpenImportSelection: Sendable {
    var audioFileURLs: [URL]
    var folderURLs: [URL]
    var unsupportedURLs: [URL]

    var supportedItemCount: Int {
        audioFileURLs.count + folderURLs.count
    }
}

extension ImportedTrack {
    init(record: NativeTrackRecord) {
        self.track = record.track
        self.url = URL(fileURLWithPath: record.filePath)
        self.sourceFolderPath = record.sourceFolderPath
        self.fileFingerprint = record.fileFingerprint
        self.missing = record.missing
        self.missingAt = record.missingAt
    }

    func record(addedAt: String, updatedAt: String) -> NativeTrackRecord {
        NativeTrackRecord(
            track: track,
            filePath: url.path,
            sourceFolderPath: sourceFolderPath,
            fileFingerprint: fileFingerprint,
            missing: missing,
            missingAt: missingAt,
            addedAt: addedAt,
            updatedAt: updatedAt
        )
    }
}

enum NativeFileImporter {
    @MainActor
    static func openAudioFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Select audio tracks"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mp3, .wav, .audio]

        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor
    static func openReplacementAudioFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select replacement audio track"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mp3, .wav, .audio]

        return panel.runModal() == .OK ? panel.urls.first : nil
    }

    @MainActor
    static func openMusicFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select music folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        return panel.runModal() == .OK ? panel.urls.first : nil
    }

    static func importTracks(from urls: [URL]) async -> [ImportedTrack] {
        var imported: [ImportedTrack] = []
        for url in urls {
            if let track = await importTrack(from: url) {
                imported.append(track)
            }
        }
        return imported
    }

    static func importFolder(_ folderURL: URL) async -> [ImportedTrack] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let urls = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else {
                return nil
            }
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            return url
        }

        let imported = await importTracks(from: urls)
        return imported.sorted {
            $0.track.title.localizedStandardCompare($1.track.title) == .orderedAscending
        }
    }

    private static let supportedExtensions = Set(["mp3", "wav"])

    static func classifyOpenURLs(_ urls: [URL]) -> NativeOpenImportSelection {
        var audioFileURLs: [URL] = []
        var folderURLs: [URL] = []
        var unsupportedURLs: [URL] = []

        for url in urls {
            if isDirectory(url) {
                folderURLs.append(url)
            } else if isSupportedAudioFile(url) {
                audioFileURLs.append(url)
            } else {
                unsupportedURLs.append(url)
            }
        }

        return NativeOpenImportSelection(
            audioFileURLs: audioFileURLs,
            folderURLs: folderURLs,
            unsupportedURLs: unsupportedURLs
        )
    }

    static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func importTrack(from url: URL) async -> ImportedTrack? {
        guard isSupportedAudioFile(url) else {
            return nil
        }

        let asset = AVURLAsset(url: url)
        let durationTime = try? await asset.load(.duration)
        let rawDuration = durationTime?.seconds ?? 0
        let duration = rawDuration.isFinite ? max(0, rawDuration) : 0
        let format = AudioFormat(rawValue: url.pathExtension.lowercased()) ?? .wav
        let title = url.deletingPathExtension().lastPathComponent
        let id = stableTrackID(for: url)

        return ImportedTrack(
            track: Track(
                id: id,
                title: title,
                durationSec: duration,
                format: format,
                bpm: nil
            ),
            url: url,
            sourceFolderPath: nil,
            fileFingerprint: nil,
            missing: false,
            missingAt: nil
        )
    }

    private static func stableTrackID(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           let isDirectory = values.isDirectory {
            return isDirectory
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
