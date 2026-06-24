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
    var selectedPlan: PlannerBenchmarkPlanReport?
    var rejectedPlan: PlannerBenchmarkPlanReport?
    var selectedPlanRole: String?
    var aiPlannerPlan: PlannerBenchmarkPlanReport?
    var acceptanceDecision: PlannerBenchmarkAcceptanceDecisionReport?
    var qualityComparisons: [PlannerBenchmarkQualityComparisonReport]
    var plannerDiagnostics: [PlannerBenchmarkDiagnosticReport]
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

private struct PlannerBenchmarkQualityComparisonReport: Encodable {
    var role: String
    var candidateId: String?
    var source: String?
    var isSelected: Bool
    var style: String
    var transitionStartSec: Double
    var transitionEndSec: Double
    var nextTrackStartOffsetSec: Double
    var quality: PlannerBenchmarkRenderedQualityReport
}

private struct PlannerBenchmarkRenderedQualityReport: Encodable {
    var score: Double
    var grade: String
    var shouldApply: Bool
    var summary: String
    var issues: [String]
    var metrics: [PlannerBenchmarkRenderedQualityMetricReport]
}

private struct PlannerBenchmarkRenderedQualityMetricReport: Encodable {
    var name: String
    var value: Double
    var score: Double
    var summary: String
}

private struct PlannerBenchmarkDiagnosticReport: Encodable {
    var currentTrackId: String
    var nextTrackId: String
    var verdict: String
    var weaknessCount: Int
    var findings: [PlannerBenchmarkDiagnosticFindingReport]
}

private struct PlannerBenchmarkDiagnosticFindingReport: Encodable {
    var kind: String
    var field: String
    var summary: String
    var aiValue: String
    var fallbackValue: String
    var delta: String
}

private struct PlannerBenchmarkAcceptanceDecisionReport: Encodable {
    var selectedRole: String
    var rejectedRole: String?
    var reason: String
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
        if let selectedPlanRole = result.selectedPlanRole {
            print("selected \(selectedPlanRole.rawValue)")
        }
        if let acceptanceDecision = result.acceptanceDecision {
            print("acceptance \(acceptanceDecision.reason.rawValue)")
        }
        if !result.qualityComparisons.isEmpty {
            let ai = result.qualityComparisons.first { $0.role == "ai_planner" }
            let fallback = result.qualityComparisons.first { $0.role == "local_fallback" }
            if let ai {
                print("quality ai \(ai.renderedQuality.grade.rawValue) \(format(ai.renderedQuality.score)) \(ai.renderedQuality.summary)")
            }
            if let fallback {
                let delta = ai.map { $0.renderedQuality.score - fallback.renderedQuality.score } ?? 0
                print("quality fallback \(fallback.renderedQuality.grade.rawValue) \(format(fallback.renderedQuality.score)) delta \(format(delta)) \(fallback.renderedQuality.summary)")
            }
            for comparison in result.qualityComparisons where comparison.role == "candidate_alternative" {
                print("quality candidate \(comparison.candidateId ?? "--") \(comparison.renderedQuality.grade.rawValue) \(format(comparison.renderedQuality.score)) \(comparison.renderedQuality.summary)")
            }
        }
        for diagnostic in result.plannerDiagnostics {
            print("diagnostic \(diagnostic.verdict.rawValue) weaknesses \(diagnostic.weaknessCount)")
            for finding in diagnostic.findings {
                print("diagnostic \(finding.kind.rawValue) \(finding.field): \(finding.summary) [AI \(finding.aiValue) | fallback \(finding.fallbackValue) | delta \(finding.delta)]")
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
        schemaVersion: 2,
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
            plan: result.plan.map(PlannerBenchmarkPlanReport.init),
            selectedPlan: result.selectedPlan.map(PlannerBenchmarkPlanReport.init),
            rejectedPlan: result.rejectedPlan.map(PlannerBenchmarkPlanReport.init),
            selectedPlanRole: result.selectedPlanRole?.rawValue,
            aiPlannerPlan: result.aiPlannerPlan.map(PlannerBenchmarkPlanReport.init),
            acceptanceDecision: result.acceptanceDecision.map {
                PlannerBenchmarkAcceptanceDecisionReport(decision: $0)
            },
            qualityComparisons: result.qualityComparisons.map {
                PlannerBenchmarkQualityComparisonReport(comparison: $0)
            },
            plannerDiagnostics: result.plannerDiagnostics.map {
                PlannerBenchmarkDiagnosticReport(diagnostic: $0)
            }
        )
    }
}

private extension PlannerBenchmarkAcceptanceDecisionReport {
    init(decision: MixPlanAcceptanceDecision) {
        self.init(
            selectedRole: decision.selectedRole.rawValue,
            rejectedRole: decision.rejectedRole?.rawValue,
            reason: decision.reason.rawValue
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

private extension PlannerBenchmarkQualityComparisonReport {
    init(comparison: NativePlannerQualityComparison) {
        self.init(
            role: comparison.role,
            candidateId: comparison.candidateId,
            source: comparison.source?.rawValue,
            isSelected: comparison.isSelected,
            style: comparison.style.rawValue,
            transitionStartSec: comparison.transitionStartSec,
            transitionEndSec: comparison.transitionEndSec,
            nextTrackStartOffsetSec: comparison.nextTrackStartOffsetSec,
            quality: PlannerBenchmarkRenderedQualityReport(report: comparison.renderedQuality)
        )
    }
}

private extension PlannerBenchmarkRenderedQualityReport {
    init(report: RenderedTransitionQualityReport) {
        self.init(
            score: report.score,
            grade: report.grade.rawValue,
            shouldApply: report.shouldApply,
            summary: report.summary,
            issues: report.issues.map { "\($0.severity.rawValue): \($0.code.rawValue) - \($0.message)" },
            metrics: report.metrics.map { PlannerBenchmarkRenderedQualityMetricReport(metric: $0) }
        )
    }
}

private extension PlannerBenchmarkRenderedQualityMetricReport {
    init(metric: RenderedTransitionQualityMetric) {
        self.init(
            name: metric.name,
            value: metric.value,
            score: metric.score,
            summary: metric.summary
        )
    }
}

private extension PlannerBenchmarkDiagnosticReport {
    init(diagnostic: MixReviewPlannerDiagnosticSummary) {
        self.init(
            currentTrackId: diagnostic.currentTrackId,
            nextTrackId: diagnostic.nextTrackId,
            verdict: diagnostic.verdict.rawValue,
            weaknessCount: diagnostic.weaknessCount,
            findings: diagnostic.findings.map {
                PlannerBenchmarkDiagnosticFindingReport(finding: $0)
            }
        )
    }
}

private extension PlannerBenchmarkDiagnosticFindingReport {
    init(finding: MixReviewPlannerDiagnosticFinding) {
        self.init(
            kind: finding.kind.rawValue,
            field: finding.field,
            summary: finding.summary,
            aiValue: finding.aiValue,
            fallbackValue: finding.fallbackValue,
            delta: finding.delta
        )
    }
}
