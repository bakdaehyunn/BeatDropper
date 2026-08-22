import BeatDropperTestSupport
import Foundation

do {
    let options = try parseOptions(CommandLine.arguments.dropFirst())
    if options.showHelp {
        printUsage()
        exit(0)
    }

    do {
        let summary = try NativeLibraryStressSuite.run(trackCount: options.trackCount)
        printTextReport(status: "PASS", summary: summary, error: nil)
        if let jsonReportURL = options.jsonReportURL {
            try writeJSONReport(
                status: "PASS",
                requestedTrackCount: options.trackCount,
                summary: summary,
                error: nil,
                reportURL: jsonReportURL
            )
        }
    } catch {
        printTextReport(status: "FAIL", summary: nil, error: error)
        if let jsonReportURL = options.jsonReportURL {
            try writeJSONReport(
                status: "FAIL",
                requestedTrackCount: options.trackCount,
                summary: nil,
                error: error,
                reportURL: jsonReportURL
            )
        }
        exit(1)
    }
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private struct LibraryStressOptions {
    var trackCount = 1_200
    var jsonReportURL: URL?
    var showHelp = false
}

private struct LibraryStressReport: Encodable {
    var schemaVersion: Int
    var generatedAt: String
    var kind: String
    var status: String
    var stress: LibraryStressConfigReport
    var result: LibraryStressResultReport?
    var error: String?
}

private struct LibraryStressConfigReport: Encodable {
    var trackCount: Int
}

private struct LibraryStressResultReport: Encodable {
    var trackCount: Int
    var savedSetCount: Int
    var indexedCount: Int
    var searchHitCount: Int
    var missingCount: Int
    var relinkedCount: Int
    var stablePlaylistReferenceCount: Int
    var durationMs: Double
}

private enum LibraryStressCLIError: LocalizedError {
    case missingTracksValue
    case invalidTracksValue(String)
    case missingWriteJSONPath
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .missingTracksValue:
            "--tracks requires a count"
        case .invalidTracksValue(let value):
            "--tracks requires a positive integer, got \(value)"
        case .missingWriteJSONPath:
            "--write-json requires a report path"
        case .unknownOption(let option):
            "unknown option: \(option)"
        }
    }
}
private func parseOptions(_ arguments: ArraySlice<String>) throws -> LibraryStressOptions {
    var options = LibraryStressOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--help", "-h":
            options.showHelp = true
            index = arguments.index(after: index)
        case "--tracks":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw LibraryStressCLIError.missingTracksValue
            }
            let rawValue = arguments[valueIndex]
            guard let value = Int(rawValue), value > 0 else {
                throw LibraryStressCLIError.invalidTracksValue(rawValue)
            }
            options.trackCount = value
            index = arguments.index(after: valueIndex)
        case "--write-json":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw LibraryStressCLIError.missingWriteJSONPath
            }
            options.jsonReportURL = URL(
                fileURLWithPath: arguments[valueIndex],
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
            index = arguments.index(after: valueIndex)
        default:
            throw LibraryStressCLIError.unknownOption(argument)
        }
    }

    return options
}

private func printUsage() {
    print(
        """
        Usage: BeatDropperNativeLibraryStress [options]

        Options:
          --tracks <count>     Number of synthetic library tracks to stress. Defaults to 1200.
          --write-json <path>  Write durable library stress evidence.
          --help              Show this message.
        """
    )
}

private func printTextReport(status: String, summary: NativeLibraryStressSummary?, error: Error?) {
    print("# Native Library Stress")
    print("status \(status)")

    if let summary {
        print("tracks \(summary.trackCount)")
        print("savedSets \(summary.savedSetCount)")
        print("indexed \(summary.indexedCount)")
        print("searchHits \(summary.searchHitCount)")
        print("missing \(summary.missingCount)")
        print("relinked \(summary.relinkedCount)")
        print("stablePlaylistRefs \(summary.stablePlaylistReferenceCount)")
        print("durationMs \(format(summary.durationMs))")
    }

    if let error {
        print("error \(error.localizedDescription)")
    }
}

private func writeJSONReport(
    status: String,
    requestedTrackCount: Int,
    summary: NativeLibraryStressSummary?,
    error: Error?,
    reportURL: URL
) throws {
    let resolvedURL = reportURL.standardizedFileURL
    let directory = resolvedURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let report = LibraryStressReport(
        schemaVersion: 1,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        kind: "library-stress",
        status: status,
        stress: LibraryStressConfigReport(trackCount: requestedTrackCount),
        result: summary.map { LibraryStressResultReport(summary: $0) },
        error: error?.localizedDescription
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    try data.write(to: resolvedURL, options: .atomic)
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private extension LibraryStressResultReport {
    init(summary: NativeLibraryStressSummary) {
        self.init(
            trackCount: summary.trackCount,
            savedSetCount: summary.savedSetCount,
            indexedCount: summary.indexedCount,
            searchHitCount: summary.searchHitCount,
            missingCount: summary.missingCount,
            relinkedCount: summary.relinkedCount,
            stablePlaylistReferenceCount: summary.stablePlaylistReferenceCount,
            durationMs: summary.durationMs
        )
    }
}
