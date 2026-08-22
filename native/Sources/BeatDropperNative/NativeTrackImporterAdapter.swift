import BeatDropperApplication
import BeatDropperPlatform
import Foundation

struct NativeTrackImporter: TrackImporting {
    func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
    @MainActor func openAudioFiles() -> [URL] { NativeFileImporter.openAudioFiles() }
    @MainActor func openReplacementAudioFile() -> URL? { NativeFileImporter.openReplacementAudioFile() }
    @MainActor func openMusicFolder() -> URL? { NativeFileImporter.openMusicFolder() }
    func importTracks(from urls: [URL]) async -> [ImportedTrack] { await NativeFileImporter.importTracks(from: urls) }
    func importFolder(_ folderURL: URL) async -> [ImportedTrack] { await NativeFileImporter.importFolder(folderURL) }
    func classifyOpenURLs(_ urls: [URL]) -> NativeOpenImportSelection { NativeFileImporter.classifyOpenURLs(urls) }
    func importTrack(from url: URL) async -> ImportedTrack? { await NativeFileImporter.importTrack(from: url) }
}

struct NativeTrackAnalysisService: TrackAnalyzing {
    func analyze(track: Track, url: URL) async throws -> TrackAnalysis {
        try await Task.detached(priority: .utility) {
            try NativeTrackAnalyzer.analyze(track: track, url: url)
        }.value
    }

    func currentFileRevision(for url: URL) throws -> TrackFileRevision {
        try NativeTrackAnalyzer.currentFileRevision(for: url)
    }
}
