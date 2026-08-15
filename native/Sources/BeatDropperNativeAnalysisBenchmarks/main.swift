import BeatDropperCore
import Darwin
import Foundation

struct BenchmarkOptions {
    var includeDefaultFixtures = true
    var fixtureDirs: [URL] = []
    var allowExpectedGrades = false
    var jsonReportURL: URL?
    var corpusGateURL: URL?
    var enforceApprovedCorpusGate = false
}

struct BenchmarkGateReport: Encodable {
    var schemaVersion: Int
    var generatedAt: String
    var status: String
    var allowExpectedGrades: Bool
    var fixtureDirCount: Int
    var suite: AnalysisBenchmarkSuiteResult
    var gradeMismatches: [BenchmarkGradeMismatch]
    var corpus: AnalysisBenchmarkCorpusReport
    var corpusGate: AnalysisBenchmarkCorpusGateResult?
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
        let corpus = AnalysisBenchmarkCorpusEvaluator.evaluate(fixtures)
        let gateConfiguration = try options.corpusGateURL.map(loadCorpusGate)
        let corpusGate = gateConfiguration.map {
            AnalysisBenchmarkCorpusGateEvaluator.evaluate(report: corpus, configuration: $0)
        }
        if options.enforceApprovedCorpusGate, gateConfiguration?.status != .approved {
            throw BenchmarkError.message("--enforce-approved-corpus-gate requires a gate configuration with status=approved.")
        }
        let gradeMismatches = evaluateGradeMismatches(
            suite: suite,
            allowExpectedGrades: options.allowExpectedGrades
        )
        printReport(
            suite: suite,
            fixtureDirCount: fixtureDirs.count,
            allowExpectedGrades: options.allowExpectedGrades,
            gradeMismatches: gradeMismatches,
            corpus: corpus,
            corpusGate: corpusGate
        )
        if let jsonReportURL = options.jsonReportURL {
            try writeJSONReport(
                suite: suite,
                fixtureDirCount: fixtureDirs.count,
                allowExpectedGrades: options.allowExpectedGrades,
                gradeMismatches: gradeMismatches,
                corpus: corpus,
                corpusGate: corpusGate,
                reportURL: jsonReportURL
            )
        }
        if !gradeMismatches.isEmpty {
            exit(1)
        }
        if options.enforceApprovedCorpusGate, corpusGate?.meetsThresholds != true {
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
            case "--enforce-approved-corpus-gate":
                options.enforceApprovedCorpusGate = true
            case "--corpus-gate":
                guard args.indices.contains(index + 1) else {
                    throw BenchmarkError.message("--corpus-gate requires a path.")
                }
                options.corpusGateURL = URL(
                    fileURLWithPath: args[index + 1],
                    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                ).standardizedFileURL
                index += 1
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
              --corpus-gate <path>       Evaluate a candidate or approved corpus gate configuration.
              --enforce-approved-corpus-gate
                                         Exit non-zero when an approved corpus gate is unmet.
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

    private static func loadCorpusGate(_ url: URL) throws -> AnalysisBenchmarkCorpusGateConfiguration {
        try JSONDecoder().decode(
            AnalysisBenchmarkCorpusGateConfiguration.self,
            from: Data(contentsOf: url)
        )
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
        gradeMismatches: [BenchmarkGradeMismatch],
        corpus: AnalysisBenchmarkCorpusReport,
        corpusGate: AnalysisBenchmarkCorpusGateResult?
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
        print("## Real-Audio Corpus")
        print("real fixtures \(corpus.realAudioFixtureCount)")
        print("integrity issues \(corpus.integrityIssues.count)")
        for split in AnalysisBenchmarkCorpusSplit.allCases {
            print("split \(split.rawValue) \(corpus.splitCounts[split] ?? 0)")
        }
        for summary in corpus.conceptSummaries {
            let calibration = summary.calibration.map { metric in
                let ece = String(format: "%.3f", metric.expectedCalibrationError)
                let brier = String(format: "%.3f", metric.brierScore)
                return "calibration n=\(metric.sampleCount) ECE=\(ece) Brier=\(brier)"
            } ?? "calibration --"
            let accuracy = String(format: "%.3f", summary.accuracy)
            print("\(summary.concept.rawValue): labels \(summary.labeledCount) accuracy \(accuracy) p50 \(formatMetric(summary.errorP50)) p95 \(formatMetric(summary.errorP95)) | \(calibration)")
        }
        if let corpusGate {
            print("gate status \(corpusGate.status.rawValue) enforceable \(corpusGate.enforceable) meets thresholds \(corpusGate.meetsThresholds)")
            for issue in corpusGate.issues {
                print("- \(issue.code): \(issue.message)")
            }
        }
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
            let downbeatAverage = formatMetric(benchmark.downbeats.averageDistanceSec, suffix: "s")
            let downbeatMaximum = formatMetric(benchmark.downbeats.maxDistanceSec, suffix: "s")
            print("Downbeats: checked \(benchmark.downbeats.checkedCount), avg distance \(downbeatAverage), max distance \(downbeatMaximum)")
            print("Outro cue: \(formatDistanceMetric(benchmark.outro))")
            print("Bar grid: checked \(benchmark.barGrid.checkedCount), avg drift \(formatMetric(benchmark.barGrid.averageDistanceSec, suffix: "s")), max drift \(formatMetric(benchmark.barGrid.maxDistanceSec, suffix: "s"))")
            print("Phrase: checked \(benchmark.phraseBoundaries.checkedCount), avg distance \(formatMetric(benchmark.phraseBoundaries.averageDistanceSec, suffix: "s")), max distance \(formatMetric(benchmark.phraseBoundaries.maxDistanceSec, suffix: "s"))")
            print("Planner ready match: \(benchmark.plannerReadyMatch.map(String.init(describing:)) ?? "--")")
            print("Key: \(formatKeyMetric(benchmark.musicalKey))")
            print("Loudness: \(formatLoudnessMetric(benchmark.loudness))")
            print("Stereo: \(formatStereoMetric(benchmark.stereo))")
            print("Cue calibration: \(formatCueMetrics(benchmark.cueCandidates))")
            print("Mix readiness: \(formatMixReadinessMetric(benchmark.mixReadiness))")
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
        corpus: AnalysisBenchmarkCorpusReport,
        corpusGate: AnalysisBenchmarkCorpusGateResult?,
        reportURL: URL
    ) throws {
        let report = BenchmarkGateReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: gradeMismatches.isEmpty ? "PASS" : "FAIL",
            allowExpectedGrades: allowExpectedGrades,
            fixtureDirCount: fixtureDirCount,
            suite: suite,
            gradeMismatches: gradeMismatches,
            corpus: corpus,
            corpusGate: corpusGate
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

    private static func formatKeyMetric(_ metric: AnalysisBenchmarkKeyMetric?) -> String {
        guard let metric else {
            return "--"
        }
        let expected = [metric.expectedTonic, metric.expectedMode?.rawValue].compactMap { $0 }.joined(separator: " ")
        let actual = [metric.actualTonic, metric.actualMode?.rawValue].compactMap { $0 }.joined(separator: " ")
        return "expected \(expected.isEmpty ? "--" : expected), actual \(actual.isEmpty ? "--" : actual), confidence \(formatMetric(metric.confidence)), matched \(metric.matched.map(String.init(describing:)) ?? "--")"
    }

    private static func formatLoudnessMetric(_ metric: AnalysisBenchmarkLoudnessMetric?) -> String {
        guard let metric else {
            return "--"
        }
        return [
            "RMS \(formatMetric(metric.actualIntegratedRMSDb, suffix: " dB")) delta \(formatMetric(metric.integratedRMSDeltaDb, suffix: " dB"))",
            "LUFS \(formatMetric(metric.actualIntegratedLUFS, suffix: " LUFS")) delta \(formatMetric(metric.integratedLUFSDelta, suffix: " LU"))",
            "peak \(formatMetric(metric.actualPeakDb, suffix: " dB")) delta \(formatMetric(metric.peakDeltaDb, suffix: " dB"))",
            "true peak \(formatMetric(metric.actualTruePeakDb, suffix: " dBTP")) delta \(formatMetric(metric.truePeakDeltaDb, suffix: " dB"))",
            "headroom \(formatMetric(metric.headroomDb, suffix: " dB"))",
            "LRA \(formatMetric(metric.loudnessRangeLU, suffix: " LU"))",
            "measurement \(metric.measurement ?? "--")",
            "confidence \(formatMetric(metric.confidence))"
        ].joined(separator: ", ")
    }

    private static func formatStereoMetric(_ metric: AnalysisBenchmarkStereoMetric?) -> String {
        guard let metric else {
            return "--"
        }
        return [
            "channels \(metric.actualChannelCount.map(String.init) ?? "--")",
            "width \(formatMetric(metric.stereoWidth))",
            "phase \(formatMetric(metric.phaseCorrelation))",
            "mid/side \(formatMetric(metric.midSideBalance))",
            "confidence \(formatMetric(metric.confidence))"
        ].joined(separator: ", ")
    }

    private static func formatCueMetrics(_ metrics: [AnalysisBenchmarkCueMetric]) -> String {
        guard !metrics.isEmpty else {
            return "--"
        }
        return metrics.map {
            "\($0.type.rawValue) expected \(formatMetric($0.expectedSec, suffix: "s")) actual \(formatMetric($0.actualSec, suffix: "s")) distance \(formatMetric($0.distanceSec, suffix: "s")) confidence \(formatMetric($0.confidence)) origin \($0.origin?.rawValue ?? "--")"
        }.joined(separator: " | ")
    }

    private static func formatMixReadinessMetric(_ metric: AnalysisBenchmarkMixReadinessMetric?) -> String {
        guard let metric else {
            return "--"
        }
        let warnings = metric.forbiddenWarningsPresent.map(\.rawValue).joined(separator: ",")
        return "analysis \(formatMetric(metric.analysisConfidence)), harmonic \(formatMetric(metric.harmonicKeyQuality)), loudness \(formatMetric(metric.loudnessConfidence)), forbidden warnings \(warnings.isEmpty ? "--" : warnings)"
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
