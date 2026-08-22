import Foundation
import BeatDropperDomain
import BeatDropperDSP

public let mixReviewExportSchemaVersion = 1

public struct MixReviewExportDocument: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: String
    public var events: [MixReviewExportEvent]

    public init(
        schemaVersion: Int = mixReviewExportSchemaVersion,
        generatedAt: String,
        events: [MixReviewExportEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.events = events
    }
}

public struct MixReviewExportEvent: Codable, Hashable, Sendable {
    public var createdAt: String
    public var currentTrackId: String
    public var currentTrackTitle: String?
    public var nextTrackId: String
    public var nextTrackTitle: String?
    public var aiPlan: MixReviewExportPlan
    public var fallbackPlan: MixReviewExportPlan?

    public init(
        createdAt: String,
        currentTrackId: String,
        currentTrackTitle: String? = nil,
        nextTrackId: String,
        nextTrackTitle: String? = nil,
        aiPlan: MixReviewExportPlan,
        fallbackPlan: MixReviewExportPlan? = nil
    ) {
        self.createdAt = createdAt
        self.currentTrackId = currentTrackId
        self.currentTrackTitle = currentTrackTitle
        self.nextTrackId = nextTrackId
        self.nextTrackTitle = nextTrackTitle
        self.aiPlan = aiPlan
        self.fallbackPlan = fallbackPlan
    }
}

public struct MixReviewExportPlan: Codable, Hashable, Sendable {
    public var source: String
    public var reason: String?
    public var transitionStartSec: Double
    public var transitionEndSec: Double
    public var nextTrackStartOffsetSec: Double
    public var style: MixStyle
    public var confidence: Double
    public var candidateId: String?
    public var renderedQuality: RenderedTransitionQualityReport

    public init(
        source: String,
        reason: String? = nil,
        transitionStartSec: Double,
        transitionEndSec: Double,
        nextTrackStartOffsetSec: Double,
        style: MixStyle,
        confidence: Double,
        candidateId: String?,
        renderedQuality: RenderedTransitionQualityReport
    ) {
        self.source = source
        self.reason = reason
        self.transitionStartSec = transitionStartSec
        self.transitionEndSec = transitionEndSec
        self.nextTrackStartOffsetSec = nextTrackStartOffsetSec
        self.style = style
        self.confidence = confidence
        self.candidateId = candidateId
        self.renderedQuality = renderedQuality
    }
}

public enum MixReviewExportRenderer {
    public static func json(document: MixReviewExportDocument) throws -> String {
        let data = try jsonData(document: document)
        return String(decoding: data, as: UTF8.self)
    }

    public static func jsonData(document: MixReviewExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func markdown(document: MixReviewExportDocument) -> String {
        var lines: [String] = [
            "# BeatDropper Mix Review Notes",
            "",
            "- Schema: \(document.schemaVersion)",
            "- Exported: \(document.generatedAt)",
            "- Reviews: \(document.events.count)",
            ""
        ]

        if document.events.isEmpty {
            lines.append("No recent mix review events.")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        for (index, event) in document.events.enumerated() {
            lines.append("## \(index + 1). \(trackLabel(title: event.currentTrackTitle, id: event.currentTrackId)) -> \(trackLabel(title: event.nextTrackTitle, id: event.nextTrackId))")
            lines.append("")
            lines.append("- Planned: \(event.createdAt)")
            lines.append("")
            lines.append("| Field | AI planner | Local fallback | Delta |")
            lines.append("| --- | --- | --- | --- |")
            appendPlanRows(event: event, lines: &lines)
            lines.append("")
            appendQualityIssues(title: "AI issues", issues: event.aiPlan.renderedQuality.issues, lines: &lines)
            if let fallbackPlan = event.fallbackPlan {
                appendQualityIssues(title: "Fallback issues", issues: fallbackPlan.renderedQuality.issues, lines: &lines)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func appendPlanRows(event: MixReviewExportEvent, lines: inout [String]) {
        let ai = event.aiPlan
        let fallback = event.fallbackPlan
        lines.append(row(
            "Source",
            ai: sourceLabel(ai),
            fallback: fallback.map(sourceLabel) ?? "--",
            delta: fallback == nil ? "--" : "compare"
        ))
        lines.append(row(
            "Window",
            ai: "\(formatDuration(ai.transitionStartSec)) -> \(formatDuration(ai.transitionEndSec))",
            fallback: fallback.map { "\(formatDuration($0.transitionStartSec)) -> \(formatDuration($0.transitionEndSec))" } ?? "--",
            delta: fallback.map { formatSignedDuration(ai.transitionStartSec - $0.transitionStartSec) } ?? "--"
        ))
        lines.append(row(
            "Next In",
            ai: formatDuration(ai.nextTrackStartOffsetSec),
            fallback: fallback.map { formatDuration($0.nextTrackStartOffsetSec) } ?? "--",
            delta: fallback.map { formatSignedDuration(ai.nextTrackStartOffsetSec - $0.nextTrackStartOffsetSec) } ?? "--"
        ))
        lines.append(row(
            "Candidate",
            ai: ai.candidateId ?? "--",
            fallback: fallback?.candidateId ?? "--",
            delta: fallback.map { ai.candidateId == $0.candidateId ? "same" : "diff" } ?? "--"
        ))
        lines.append(row(
            "Style",
            ai: ai.style.rawValue,
            fallback: fallback?.style.rawValue ?? "--",
            delta: fallback.map { ai.style == $0.style ? "same" : "diff" } ?? "--"
        ))
        lines.append(row(
            "Confidence",
            ai: formatPercent(ai.confidence),
            fallback: fallback.map { formatPercent($0.confidence) } ?? "--",
            delta: fallback.map { formatSignedPoints(ai.confidence - $0.confidence) } ?? "--"
        ))
        lines.append(row(
            "Quality",
            ai: qualityLabel(ai.renderedQuality),
            fallback: fallback.map { qualityLabel($0.renderedQuality) } ?? "--",
            delta: fallback.map { formatSignedPoints(ai.renderedQuality.score - $0.renderedQuality.score) } ?? "--"
        ))
        for metricName in ["estimated_peak", "peak_jump", "rms_jump", "spectral_masking"] {
            lines.append(row(
                metricLabel(metricName),
                ai: metricSummary(ai.renderedQuality, metricName),
                fallback: fallback.map { metricSummary($0.renderedQuality, metricName) } ?? "--",
                delta: fallback.map {
                    formatSignedPoints(metricScore(ai.renderedQuality, metricName) - metricScore($0.renderedQuality, metricName))
                } ?? "--"
            ))
        }
    }

    private static func appendQualityIssues(
        title: String,
        issues: [RenderedTransitionQualityIssue],
        lines: inout [String]
    ) {
        lines.append("### \(title)")
        if issues.isEmpty {
            lines.append("")
            lines.append("- None")
            return
        }
        lines.append("")
        for issue in issues {
            lines.append("- \(issue.severity.rawValue): \(issue.code.rawValue) - \(issue.message)")
        }
    }

    private static func row(_ field: String, ai: String, fallback: String, delta: String) -> String {
        "| \(escape(field)) | \(escape(ai)) | \(escape(fallback)) | \(escape(delta)) |"
    }

    private static func sourceLabel(_ plan: MixReviewExportPlan) -> String {
        if let reason = plan.reason, !reason.isEmpty {
            return "\(plan.source) (\(reason))"
        }
        return plan.source
    }

    private static func trackLabel(title: String?, id: String) -> String {
        guard let title, !title.isEmpty else {
            return id
        }
        return "\(title) (\(id))"
    }

    private static func qualityLabel(_ report: RenderedTransitionQualityReport) -> String {
        "\(report.grade.rawValue) \(formatPercent(report.score))"
    }

    private static func metricLabel(_ name: String) -> String {
        name
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func metricSummary(_ report: RenderedTransitionQualityReport, _ metricName: String) -> String {
        report.metrics.first { $0.name == metricName }?.summary ?? "--"
    }

    private static func metricScore(_ report: RenderedTransitionQualityReport, _ metricName: String) -> Double {
        report.metrics.first { $0.name == metricName }?.score ?? 0
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
    }

    private static func formatSignedDuration(_ seconds: Double) -> String {
        if abs(seconds) < 0.05 {
            return "same"
        }
        let sign = seconds >= 0 ? "+" : "-"
        return "\(sign)\(formatDuration(abs(seconds)))"
    }

    private static func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func formatSignedPoints(_ value: Double) -> String {
        if abs(value) < 0.005 {
            return "same"
        }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int((value * 100).rounded()))"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}
