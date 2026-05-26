import BeatDropperCore
import Darwin
import Foundation

struct BenchmarkOptions {
    var includeDefaultFixtures = true
    var fixtureDirs: [URL] = []
    var allowExpectedGrades = false
    var jsonReportURL: URL?
}

struct BenchmarkGateReport: Encodable {
    var schemaVersion: Int
    var generatedAt: String
    var status: String
    var allowExpectedGrades: Bool
    var fixtureDirCount: Int
    var suite: AnalysisBenchmarkSuiteResult
    var gradeMismatches: [BenchmarkGradeMismatch]
}

struct BenchmarkGradeMismatch: Encodable {
    var fixtureId: String
    var expectedGrade: AnalysisBenchmarkGrade?
    var actualGrade: AnalysisBenchmarkGrade
    var title: String
}

enum BenchmarkCLI {
    static func main() throws {
        let options = try parseArgs(Array(CommandLine.arguments.dropFirst()))
        var fixtureDirs: [URL] = []
        if options.includeDefaultFixtures {
            fixtureDirs.append(defaultFixtureDir())
        }
        fixtureDirs.append(contentsOf: options.fixtureDirs)
        let fixtures = try loadFixtures(fixtureDirs: fixtureDirs)
        let suite = AnalysisBenchmarkEvaluator.evaluateSuite(fixtures)
        let gradeMismatches = evaluateGradeMismatches(
            suite: suite,
            allowExpectedGrades: options.allowExpectedGrades
        )
        printReport(
            suite: suite,
            fixtureDirCount: fixtureDirs.count,
            allowExpectedGrades: options.allowExpectedGrades,
            gradeMismatches: gradeMismatches
        )
        if let jsonReportURL = options.jsonReportURL {
            try writeJSONReport(
                suite: suite,
                fixtureDirCount: fixtureDirs.count,
                allowExpectedGrades: options.allowExpectedGrades,
                gradeMismatches: gradeMismatches,
                reportURL: jsonReportURL
            )
        }
        if !gradeMismatches.isEmpty {
            exit(1)
        }
    }

    private static func parseArgs(_ args: [String]) throws -> BenchmarkOptions {
        var options = BenchmarkOptions()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--help", "-h":
                printUsage()
                exit(0)
            case "--no-default-fixtures":
                options.includeDefaultFixtures = false
            case "--allow-expected-grades":
                options.allowExpectedGrades = true
            case "--write-json":
                guard args.indices.contains(index + 1) else {
                    throw BenchmarkError.message("--write-json requires a path.")
                }
                options.jsonReportURL = URL(
                    fileURLWithPath: args[index + 1],
                    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                ).standardizedFileURL
                index += 1
            case "--fixture-dir":
                guard args.indices.contains(index + 1) else {
                    throw BenchmarkError.message("--fixture-dir requires a path.")
                }
                options.fixtureDirs.append(URL(fileURLWithPath: args[index + 1], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL)
                index += 1
            default:
                throw BenchmarkError.message("Unknown option: \(arg)")
            }
            index += 1
        }

        if let envFixtureDir = ProcessInfo.processInfo.environment["ANALYSIS_BENCHMARK_FIXTURE_DIR"],
           !envFixtureDir.isEmpty {
            options.fixtureDirs.append(URL(fileURLWithPath: envFixtureDir, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL)
        }
        return options
    }

    private static func printUsage() {
        print(
            """
            Usage: swift run --package-path native BeatDropperNativeAnalysisBenchmarks [options]

            Options:
              --fixture-dir <path>       Add a benchmark fixture directory. May be repeated.
              --no-default-fixtures      Skip tests/fixtures/analysis-benchmarks.
              --allow-expected-grades    Exit non-zero only when actual fixture grades differ from expectedGrade.
              --write-json <path>        Write a machine-readable benchmark gate report.
              --help                    Show this message.

            Fixture directories are scanned recursively for .json files.
            """
        )
    }

    private static func defaultFixtureDir() -> URL {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let rootCandidate = current.appendingPathComponent("tests/fixtures/analysis-benchmarks", isDirectory: true)
        if FileManager.default.fileExists(atPath: rootCandidate.path) {
            return rootCandidate
        }
        return current
            .deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/analysis-benchmarks", isDirectory: true)
    }

    private static func loadFixtures(fixtureDirs: [URL]) throws -> [AnalysisBenchmarkFixture] {
        let decoder = JSONDecoder()
        let fixtureFiles = try fixtureDirs
            .flatMap(collectFixtureFiles)
            .reduce(into: [String: URL]()) { filesByPath, file in
                filesByPath[file.standardizedFileURL.path] = file
            }
            .values
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        return try fixtureFiles.map { fileURL in
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AnalysisBenchmarkFixture.self, from: data)
        }
    }

    private static func collectFixtureFiles(fixtureDir: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fixtureDir.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw BenchmarkError.message("Fixture path is not a directory: \(fixtureDir.path)")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: fixtureDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "json" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }

    private static func printReport(
        suite: AnalysisBenchmarkSuiteResult,
        fixtureDirCount: Int,
        allowExpectedGrades: Bool,
        gradeMismatches: [BenchmarkGradeMismatch]
    ) {
        print("# Native Analysis Benchmarks")
        print("fixture dirs \(fixtureDirCount)")
        print("fixtures \(suite.results.count)")
        print("grade \(suite.grade.rawValue)")
        print(String(format: "score %.3f", suite.score))
        print("pass \(suite.passed)")
        print("warn \(suite.warned)")
        print("fail \(suite.failed)")
        print("allow expected grades \(allowExpectedGrades)")
        print("grade mismatches \(gradeMismatches.count)")
        print("")

        if !suite.byKind.isEmpty {
            print("## Fixture Kinds")
            for summary in suite.byKind {
                print("\(summary.kind.rawValue): \(summary.grade.rawValue.uppercased()) | fixtures \(summary.total) | score \(String(format: "%.3f", summary.score)) | pass \(summary.passed) warn \(summary.warned) fail \(summary.failed)")
            }
            print("")
        }

        for result in suite.results {
            let benchmark = result.result
            print("## \(result.fixtureId)")
            print("\(benchmark.grade.rawValue.uppercased()) | score \(String(format: "%.3f", benchmark.score)) | \(result.title)")
            print("Kind: \(result.kind.rawValue)")
            print("BPM error: \(formatMetric(benchmark.bpmError))")
            print("First downbeat: \(formatDistanceMetric(benchmark.firstDownbeat))")
            print("Outro cue: \(formatDistanceMetric(benchmark.outro))")
            print("Bar grid: checked \(benchmark.barGrid.checkedCount), avg drift \(formatMetric(benchmark.barGrid.averageDistanceSec, suffix: "s")), max drift \(formatMetric(benchmark.barGrid.maxDistanceSec, suffix: "s"))")
            print("Phrase: checked \(benchmark.phraseBoundaries.checkedCount), avg distance \(formatMetric(benchmark.phraseBoundaries.averageDistanceSec, suffix: "s")), max distance \(formatMetric(benchmark.phraseBoundaries.maxDistanceSec, suffix: "s"))")
            print("Planner ready match: \(benchmark.plannerReadyMatch.map(String.init(describing:)) ?? "--")")
            if benchmark.issues.isEmpty {
                print("- no issues")
            } else {
                for issue in benchmark.issues {
                    print("- \(issue.grade.rawValue.uppercased()) \(issue.code): \(issue.message)")
                }
            }
            print("")
        }
    }

    private static func evaluateGradeMismatches(
        suite: AnalysisBenchmarkSuiteResult,
        allowExpectedGrades: Bool
    ) -> [BenchmarkGradeMismatch] {
        suite.results.compactMap { result in
            if allowExpectedGrades, let expectedGrade = result.expectedGrade {
                return result.result.grade == expectedGrade
                    ? nil
                    : BenchmarkGradeMismatch(
                        fixtureId: result.fixtureId,
                        expectedGrade: expectedGrade,
                        actualGrade: result.result.grade,
                        title: result.title
                    )
            }
            if result.result.grade == .fail {
                return BenchmarkGradeMismatch(
                    fixtureId: result.fixtureId,
                    expectedGrade: result.expectedGrade,
                    actualGrade: result.result.grade,
                    title: result.title
                )
            }
            return nil
        }
    }

    private static func writeJSONReport(
        suite: AnalysisBenchmarkSuiteResult,
        fixtureDirCount: Int,
        allowExpectedGrades: Bool,
        gradeMismatches: [BenchmarkGradeMismatch],
        reportURL: URL
    ) throws {
        let report = BenchmarkGateReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: gradeMismatches.isEmpty ? "PASS" : "FAIL",
            allowExpectedGrades: allowExpectedGrades,
            fixtureDirCount: fixtureDirCount,
            suite: suite,
            gradeMismatches: gradeMismatches
        )
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL)
    }

    private static func formatMetric(_ value: Double?, suffix: String = "") -> String {
        guard let value, value.isFinite else {
            return "--"
        }
        return String(format: "%.2f%@", value, suffix)
    }

    private static func formatMetric(_ value: Double, suffix: String = "") -> String {
        formatMetric(Optional(value), suffix: suffix)
    }

    private static func formatDistanceMetric(_ metric: AnalysisBenchmarkDistanceMetric?) -> String {
        guard let metric else {
            return "--"
        }
        return [
            "expected \(formatMetric(metric.expectedSec, suffix: "s"))",
            "actual \(formatMetric(metric.actualSec, suffix: "s"))",
            "distance \(formatMetric(metric.distanceSec, suffix: "s"))"
        ].joined(separator: ", ")
    }
}

enum BenchmarkError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

do {
    try BenchmarkCLI.main()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
