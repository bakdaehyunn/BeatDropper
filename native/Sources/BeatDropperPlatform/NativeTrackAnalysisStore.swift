import Foundation
import BeatDropperDomain

public final class NativeTrackAnalysisStore: @unchecked Sendable {
    public let rootURL: URL

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func applicationSupport(
        appFolderName: String = "BeatDropper",
        folderName: String = "track-analysis-cache",
        fileManager: FileManager = .default
    ) -> NativeTrackAnalysisStore {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return NativeTrackAnalysisStore(
            rootURL: baseURL
                .appendingPathComponent(appFolderName, isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
        )
    }

    public func read(trackId: String) throws -> TrackAnalysis? {
        let fileURL = resolveFileURL(trackId: trackId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let analysis = try decoder.decode(TrackAnalysis.self, from: data)
        guard analysis.schemaVersion == trackAnalysisSchemaVersion else {
            return nil
        }
        return analysis.trackId == trackId ? analysis : nil
    }

    @discardableResult
    public func write(_ analysis: TrackAnalysis) throws -> TrackAnalysis {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(analysis)
        try data.write(to: resolveFileURL(trackId: analysis.trackId), options: [.atomic])
        return analysis
    }

    private func resolveFileURL(trackId: String) -> URL {
        rootURL.appendingPathComponent("\(encodedTrackId(trackId)).json")
    }

    private func encodedTrackId(_ trackId: String) -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~")
        return trackId.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? UUID().uuidString
    }
}
