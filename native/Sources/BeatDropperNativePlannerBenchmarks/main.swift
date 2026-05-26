import BeatDropperCore
import Foundation

do {
    let options = try parseOptions(CommandLine.arguments.dropFirst())
    if options.showHelp {
        printUsage()
        exit(0)
    }

    let summary = NativePlannerBenchmarkSuite.run()
    printTextReport(summary)

    if let jsonReportURL = options.jsonReportURL {
        try writeJSONReport(summary: summary, reportURL: jsonReportURL)
    }

    if summary.failCount > 0 {
        exit(1)
    }
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private struct BenchmarkOptions {
    var jsonReportURL: URL?
    var showHelp = false
}

private struct PlannerBenchmarkReport: Encodable {
    var schemaVersion: Int
    var generatedAt: String
    var status: String
    var summary: PlannerBenchmarkSummaryReport
    var results: [PlannerBenchmarkResultReport]
}

private struct PlannerBenchmarkSummaryReport: Encodable {
    var passCount: Int
    var warnCount: Int
    var failCount: Int
    var totalCount: Int
}

private struct PlannerBenchmarkResultReport: Encodable {
    var name: String
    var grade: String
    var failures: [String]
    var warnings: [String]
    var plan: PlannerBenchmarkPlanReport?
}

private struct PlannerBenchmarkPlanReport: Encodable {
    var style: String
    var transitionStartSec: Double
    var transitionEndSec: Double
    var nextTrackStartOffsetSec: Double
    var confidence: Double
    var reasoningSummary: String?
    var tempoSyncEnabled: Bool
    var tempoSyncTargetRate: Double?
    var candidateId: String?
    var currentBarIndex: Int?
    var nextBarIndex: Int?
    var phraseAlignment: String?
    var energyStrategy: String?
    var evidence: [String]
}

private enum BenchmarkCLIError: LocalizedError {
    case missingWriteJSONPath
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .missingWriteJSONPath:
            "--write-json requires a report path"
        case .unknownOption(let option):
            "unknown option: \(option)"
        }
    }
}

private func parseOptions(_ arguments: ArraySlice<String>) throws -> BenchmarkOptions {
    var options = BenchmarkOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--help", "-h":
            options.showHelp = true
            index = arguments.index(after: index)
        case "--write-json":
            let pathIndex = arguments.index(after: index)
            guard pathIndex < arguments.endIndex else {
                throw BenchmarkCLIError.missingWriteJSONPath
            }
            options.jsonReportURL = URL(
                fileURLWithPath: arguments[pathIndex],
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
            index = arguments.index(after: pathIndex)
        default:
            throw BenchmarkCLIError.unknownOption(argument)
        }
    }

    return options
}

private func printUsage() {
    print(
        """
        Usage: BeatDropperNativePlannerBenchmarks [options]

        Options:
          --write-json <path>  Write a durable planner benchmark JSON report.
          --help              Show this message.
        """
    )
}

private func printTextReport(_ summary: NativePlannerBenchmarkSummary) {
    print("# Native Planner Benchmark")
    print("status \(summary.status.rawValue)")
    print("pass \(summary.passCount)")
    print("warn \(summary.warnCount)")
    print("fail \(summary.failCount)")

    for result in summary.results {
        print("")
        print("## \(result.name)")
        print("grade \(result.grade.rawValue)")
        if let plan = result.plan {
            print("style \(plan.style.rawValue)")
            print("window \(format(plan.transitionStartSec)) -> \(format(plan.transitionEndSec))")
            print("next offset \(format(plan.nextTrackStartOffsetSec))")
            print("confidence \(format(plan.confidence))")
            print("tempo \(plan.tempoSync.enabled ? format(plan.tempoSync.targetRate ?? 0) : "off")")
            print("candidate \(plan.candidateId ?? "--")")
            if !plan.evidence.isEmpty {
                print("evidence \(plan.evidence.joined(separator: " | "))")
            }
        }
        for warning in result.warnings {
            print("WARN \(warning)")
        }
        for failure in result.failures {
            print("FAIL \(failure)")
        }
    }
}

private func writeJSONReport(summary: NativePlannerBenchmarkSummary, reportURL: URL) throws {
    let resolvedURL = reportURL.standardizedFileURL
    let directory = resolvedURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let report = PlannerBenchmarkReport(
        schemaVersion: 1,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        status: summary.status.rawValue,
        summary: PlannerBenchmarkSummaryReport(
            passCount: summary.passCount,
            warnCount: summary.warnCount,
            failCount: summary.failCount,
            totalCount: summary.results.count
        ),
        results: summary.results.map(PlannerBenchmarkResultReport.init)
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    try data.write(to: resolvedURL, options: .atomic)
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private extension PlannerBenchmarkResultReport {
    init(result: NativePlannerBenchmarkResult) {
        self.init(
            name: result.name,
            grade: result.grade.rawValue,
            failures: result.failures,
            warnings: result.warnings,
            plan: result.plan.map(PlannerBenchmarkPlanReport.init)
        )
    }
}

private extension PlannerBenchmarkPlanReport {
    init(plan: MixPlan) {
        self.init(
            style: plan.style.rawValue,
            transitionStartSec: plan.transitionStartSec,
            transitionEndSec: plan.transitionEndSec,
            nextTrackStartOffsetSec: plan.nextTrackStartOffsetSec,
            confidence: plan.confidence,
            reasoningSummary: plan.reasoningSummary,
            tempoSyncEnabled: plan.tempoSync.enabled,
            tempoSyncTargetRate: plan.tempoSync.targetRate,
            candidateId: plan.candidateId,
            currentBarIndex: plan.currentBarIndex,
            nextBarIndex: plan.nextBarIndex,
            phraseAlignment: plan.phraseAlignment?.rawValue,
            energyStrategy: plan.energyStrategy?.rawValue,
            evidence: plan.evidence
        )
    }
}
