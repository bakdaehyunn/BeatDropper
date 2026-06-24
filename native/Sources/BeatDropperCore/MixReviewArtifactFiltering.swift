import Foundation

public enum MixReviewArtifactPairExtractor {
    public static func trackPairs(content: String) -> [MixReviewArtifactTrackPair] {
        if let jsonPairs = jsonTrackPairs(content: content), !jsonPairs.isEmpty {
            return uniqued(jsonPairs)
        }
        return uniqued(markdownTrackPairs(content: content))
    }

    private static func jsonTrackPairs(content: String) -> [MixReviewArtifactTrackPair]? {
        guard let data = content.data(using: .utf8),
              let document = try? JSONDecoder().decode(MixReviewExportDocument.self, from: data)
        else {
            return nil
        }
        return document.events.map {
            MixReviewArtifactTrackPair(currentTrackId: $0.currentTrackId, nextTrackId: $0.nextTrackId)
        }
    }

    private static func markdownTrackPairs(content: String) -> [MixReviewArtifactTrackPair] {
        content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> MixReviewArtifactTrackPair? in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard trimmedLine.hasPrefix("## "),
                      let separatorRange = trimmedLine.range(of: " -> ")
                else {
                    return nil
                }

                let leftLabel = String(trimmedLine[..<separatorRange.lowerBound])
                    .replacingFirstMarkdownHeadingNumber()
                let rightLabel = String(trimmedLine[separatorRange.upperBound...])
                guard let currentTrackId = trackId(from: leftLabel),
                      let nextTrackId = trackId(from: rightLabel)
                else {
                    return nil
                }
                return MixReviewArtifactTrackPair(currentTrackId: currentTrackId, nextTrackId: nextTrackId)
            }
    }

    private static func trackId(from label: String) -> String? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        if trimmedLabel.hasSuffix(")"),
           let openParen = trimmedLabel.lastIndex(of: "(") {
            let id = trimmedLabel[trimmedLabel.index(after: openParen)..<trimmedLabel.index(before: trimmedLabel.endIndex)]
                .trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
        return trimmedLabel.isEmpty ? nil : trimmedLabel
    }

    private static func uniqued(_ pairs: [MixReviewArtifactTrackPair]) -> [MixReviewArtifactTrackPair] {
        var seen: Set<MixReviewArtifactTrackPair> = []
        var uniquePairs: [MixReviewArtifactTrackPair] = []
        for pair in pairs where !seen.contains(pair) {
            seen.insert(pair)
            uniquePairs.append(pair)
        }
        return uniquePairs
    }
}

public enum MixReviewArtifactPairFilter {
    public static func matches(
        trackPairs: [MixReviewArtifactTrackPair],
        currentTrackId: String,
        nextTrackId: String
    ) -> Bool {
        trackPairs.contains {
            $0.currentTrackId == currentTrackId && $0.nextTrackId == nextTrackId
        }
    }
}

public enum MixReviewArtifactSearch {
    public static func matches(
        fileName: String,
        format: String,
        reviewCount: Int,
        trackPairs: [MixReviewArtifactTrackPair],
        content: String,
        annotation: String = "",
        query: String
    ) -> Bool {
        let tokens = query
            .split { $0.isWhitespace }
            .map { $0.lowercased() }
        guard !tokens.isEmpty else {
            return true
        }

        let searchableText = [
            fileName,
            format,
            "\(reviewCount)",
            trackPairs.flatMap { [$0.currentTrackId, $0.nextTrackId, "\($0.currentTrackId) -> \($0.nextTrackId)"] }.joined(separator: " "),
            content,
            annotation
        ]
            .joined(separator: " ")
            .lowercased()

        return tokens.allSatisfy { searchableText.contains($0) }
    }
}

public struct MixReviewArtifactComparisonRow: Hashable, Sendable {
    public var label: String
    public var leftValue: String
    public var rightValue: String
    public var delta: String

    public init(label: String, leftValue: String, rightValue: String, delta: String) {
        self.label = label
        self.leftValue = leftValue
        self.rightValue = rightValue
        self.delta = delta
    }
}

public struct MixReviewArtifactPairComparison: Hashable, Sendable {
    public var currentTrackId: String
    public var nextTrackId: String
    public var leftDetail: MixReviewArtifactPairDetail?
    public var rightDetail: MixReviewArtifactPairDetail?
    public var aiRows: [MixReviewArtifactComparisonRow]
    public var fallbackRows: [MixReviewArtifactComparisonRow]

    public var hasStructuredDetails: Bool {
        leftDetail != nil && rightDetail != nil
    }

    public init(
        currentTrackId: String,
        nextTrackId: String,
        leftDetail: MixReviewArtifactPairDetail?,
        rightDetail: MixReviewArtifactPairDetail?,
        aiRows: [MixReviewArtifactComparisonRow],
        fallbackRows: [MixReviewArtifactComparisonRow]
    ) {
        self.currentTrackId = currentTrackId
        self.nextTrackId = nextTrackId
        self.leftDetail = leftDetail
        self.rightDetail = rightDetail
        self.aiRows = aiRows
        self.fallbackRows = fallbackRows
    }
}

public struct MixReviewArtifactComparisonSummarySide: Hashable, Sendable {
    public var label: String
    public var fileName: String
    public var format: String
    public var importedAt: String
    public var reviewCount: Int
    public var annotation: String

    public init(
        label: String,
        fileName: String,
        format: String,
        importedAt: String,
        reviewCount: Int,
        annotation: String
    ) {
        self.label = label
        self.fileName = fileName
        self.format = format
        self.importedAt = importedAt
        self.reviewCount = reviewCount
        self.annotation = annotation
    }
}

public struct MixReviewArtifactComparisonSummary: Hashable, Sendable {
    public var currentTrackId: String
    public var nextTrackId: String
    public var left: MixReviewArtifactComparisonSummarySide
    public var right: MixReviewArtifactComparisonSummarySide
    public var pairComparison: MixReviewArtifactPairComparison

    public init(
        currentTrackId: String,
        nextTrackId: String,
        left: MixReviewArtifactComparisonSummarySide,
        right: MixReviewArtifactComparisonSummarySide,
        pairComparison: MixReviewArtifactPairComparison
    ) {
        self.currentTrackId = currentTrackId
        self.nextTrackId = nextTrackId
        self.left = left
        self.right = right
        self.pairComparison = pairComparison
    }
}

public enum MixReviewArtifactComparisonSummaryRenderer {
    public static func markdown(_ summary: MixReviewArtifactComparisonSummary) -> String {
        var lines = [
            "# BeatDropper Imported Artifact Compare",
            "",
            "- Pair: \(escapeInline(summary.currentTrackId)) -> \(escapeInline(summary.nextTrackId))",
            "- Mode: Review-only imported artifact comparison",
            "",
            "## Artifacts",
            "",
            "| Field | Left | Right |",
            "| --- | --- | --- |",
            tableRow("Label", summary.left.label, summary.right.label),
            tableRow("File", summary.left.fileName, summary.right.fileName),
            tableRow("Format", summary.left.format, summary.right.format),
            tableRow("Imported", summary.left.importedAt, summary.right.importedAt),
            tableRow("Reviews", "\(summary.left.reviewCount)", "\(summary.right.reviewCount)"),
            tableRow("Annotation", summary.left.annotation, summary.right.annotation),
            ""
        ]

        appendRows(title: "AI Plan", rows: summary.pairComparison.aiRows, to: &lines)
        if !summary.pairComparison.fallbackRows.isEmpty {
            appendRows(title: "Fallback Plan", rows: summary.pairComparison.fallbackRows, to: &lines)
        }
        if !summary.pairComparison.hasStructuredDetails {
            lines.append("> Structured pair details are unavailable for one or both artifacts; compare is limited to matching metadata and annotations.")
            lines.append("")
        }
        lines.append("This summary is review-only and does not affect playback or planner behavior.")
        return lines.joined(separator: "\n")
    }

    private static func appendRows(
        title: String,
        rows: [MixReviewArtifactComparisonRow],
        to lines: inout [String]
    ) {
        lines.append("## \(title)")
        lines.append("")
        guard !rows.isEmpty else {
            lines.append("No structured \(title.lowercased()) details.")
            lines.append("")
            return
        }

        lines.append("| Field | Left | Right | Delta |")
        lines.append("| --- | --- | --- | --- |")
        for row in rows {
            lines.append(tableRow(row.label, row.leftValue, row.rightValue, row.delta))
        }
        lines.append("")
    }

    private static func tableRow(_ values: String...) -> String {
        "| \(values.map(escapeTableCell).joined(separator: " | ")) |"
    }

    private static func escapeTableCell(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackValue = trimmedValue.isEmpty ? "--" : trimmedValue
        return fallbackValue
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
    }

    private static func escapeInline(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
    }
}

public enum MixReviewArtifactComparisonBuilder {
    public static func isEligible(
        trackPairs: [MixReviewArtifactTrackPair],
        currentTrackId: String,
        nextTrackId: String
    ) -> Bool {
        MixReviewArtifactPairFilter.matches(
            trackPairs: trackPairs,
            currentTrackId: currentTrackId,
            nextTrackId: nextTrackId
        )
    }

    public static func pairDetail(
        in details: [MixReviewArtifactPairDetail],
        currentTrackId: String,
        nextTrackId: String
    ) -> MixReviewArtifactPairDetail? {
        details.first {
            $0.currentTrackId == currentTrackId && $0.nextTrackId == nextTrackId
        }
    }

    public static func compare(
        leftDetails: [MixReviewArtifactPairDetail],
        rightDetails: [MixReviewArtifactPairDetail],
        currentTrackId: String,
        nextTrackId: String
    ) -> MixReviewArtifactPairComparison {
        let leftDetail = pairDetail(in: leftDetails, currentTrackId: currentTrackId, nextTrackId: nextTrackId)
        let rightDetail = pairDetail(in: rightDetails, currentTrackId: currentTrackId, nextTrackId: nextTrackId)
        return MixReviewArtifactPairComparison(
            currentTrackId: currentTrackId,
            nextTrackId: nextTrackId,
            leftDetail: leftDetail,
            rightDetail: rightDetail,
            aiRows: comparisonRows(left: leftDetail?.aiPlan, right: rightDetail?.aiPlan),
            fallbackRows: comparisonRows(left: leftDetail?.fallbackPlan, right: rightDetail?.fallbackPlan)
        )
    }

    public static func comparisonRows(
        left: MixReviewExportPlan?,
        right: MixReviewExportPlan?
    ) -> [MixReviewArtifactComparisonRow] {
        guard left != nil || right != nil else {
            return []
        }

        return [
            MixReviewArtifactComparisonRow(
                label: "Window",
                leftValue: left.map { "\(formatDuration($0.transitionStartSec)) -> \(formatDuration($0.transitionEndSec))" } ?? "--",
                rightValue: right.map { "\(formatDuration($0.transitionStartSec)) -> \(formatDuration($0.transitionEndSec))" } ?? "--",
                delta: windowDelta(left: left, right: right)
            ),
            MixReviewArtifactComparisonRow(
                label: "Duration",
                leftValue: left.map { formatDuration(transitionDuration($0)) } ?? "--",
                rightValue: right.map { formatDuration(transitionDuration($0)) } ?? "--",
                delta: timingDelta(left.map(transitionDuration), right.map(transitionDuration))
            ),
            MixReviewArtifactComparisonRow(
                label: "Next In",
                leftValue: left.map { formatDuration($0.nextTrackStartOffsetSec) } ?? "--",
                rightValue: right.map { formatDuration($0.nextTrackStartOffsetSec) } ?? "--",
                delta: timingDelta(left?.nextTrackStartOffsetSec, right?.nextTrackStartOffsetSec)
            ),
            MixReviewArtifactComparisonRow(
                label: "Candidate",
                leftValue: left?.candidateId ?? "--",
                rightValue: right?.candidateId ?? "--",
                delta: optionalTextDelta(left?.candidateId, right?.candidateId)
            ),
            MixReviewArtifactComparisonRow(
                label: "Style",
                leftValue: left.map { styleLabel($0.style) } ?? "--",
                rightValue: right.map { styleLabel($0.style) } ?? "--",
                delta: optionalTextDelta(left.map { styleLabel($0.style) }, right.map { styleLabel($0.style) })
            ),
            MixReviewArtifactComparisonRow(
                label: "Confidence",
                leftValue: left.map { percent($0.confidence) } ?? "--",
                rightValue: right.map { percent($0.confidence) } ?? "--",
                delta: pointDelta(left?.confidence, right?.confidence)
            ),
            MixReviewArtifactComparisonRow(
                label: "Quality",
                leftValue: left.map { qualityLabel($0.renderedQuality) } ?? "--",
                rightValue: right.map { qualityLabel($0.renderedQuality) } ?? "--",
                delta: pointDelta(left?.renderedQuality.score, right?.renderedQuality.score)
            )
        ] + metricRows(left: left, right: right)
    }

    private static func metricRows(
        left: MixReviewExportPlan?,
        right: MixReviewExportPlan?
    ) -> [MixReviewArtifactComparisonRow] {
        ["estimated_peak", "peak_jump", "rms_jump", "spectral_masking"].map { metricName in
            MixReviewArtifactComparisonRow(
                label: metricLabel(metricName),
                leftValue: left.map { metricSummary($0.renderedQuality, metricName) } ?? "--",
                rightValue: right.map { metricSummary($0.renderedQuality, metricName) } ?? "--",
                delta: pointDelta(
                    left.flatMap { metricScore($0.renderedQuality, metricName) },
                    right.flatMap { metricScore($0.renderedQuality, metricName) }
                )
            )
        }
    }

    private static func optionalTextDelta(_ left: String?, _ right: String?) -> String {
        guard let left, let right else {
            return "--"
        }
        return left == right ? "same" : "diff"
    }

    private static func windowDelta(left: MixReviewExportPlan?, right: MixReviewExportPlan?) -> String {
        guard let left, let right else {
            return "--"
        }
        let start = timingDelta(left.transitionStartSec, right.transitionStartSec, label: "start")
        let end = timingDelta(left.transitionEndSec, right.transitionEndSec, label: "end")
        let duration = timingDelta(transitionDuration(left), transitionDuration(right), label: "dur")
        let deltas = [start, end, duration].filter { $0 != nil }.compactMap { $0 }
        return deltas.isEmpty ? "same" : deltas.joined(separator: " ")
    }

    private static func timingDelta(_ left: Double?, _ right: Double?) -> String {
        guard let left, let right else {
            return "--"
        }
        let delta = left - right
        if abs(delta) < 0.05 {
            return "same"
        }
        let sign = delta >= 0 ? "+" : "-"
        return "\(sign)\(formatDuration(abs(delta)))"
    }

    private static func timingDelta(_ left: Double, _ right: Double, label: String) -> String? {
        let delta = left - right
        guard abs(delta) >= 0.05 else {
            return nil
        }
        let sign = delta >= 0 ? "+" : "-"
        return "\(label) \(sign)\(formatDuration(abs(delta)))"
    }

    private static func pointDelta(_ left: Double?, _ right: Double?) -> String {
        guard let left, let right else {
            return "--"
        }
        let delta = left - right
        if abs(delta) < 0.005 {
            return "same"
        }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Int((delta * 100).rounded()))"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
    }

    private static func transitionDuration(_ plan: MixReviewExportPlan) -> Double {
        max(0, plan.transitionEndSec - plan.transitionStartSec)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func qualityLabel(_ report: RenderedTransitionQualityReport) -> String {
        "\(report.grade.rawValue) \(percent(report.score))"
    }

    private static func styleLabel(_ style: MixStyle) -> String {
        style.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private static func metricLabel(_ name: String) -> String {
        name
            .split(separator: "_")
            .map { part in
                let value = String(part)
                return value.lowercased() == "rms" ? "RMS" : value.prefix(1).uppercased() + value.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func metricSummary(_ report: RenderedTransitionQualityReport, _ metricName: String) -> String {
        report.metrics.first { $0.name == metricName }?.summary ?? "--"
    }

    private static func metricScore(_ report: RenderedTransitionQualityReport, _ metricName: String) -> Double? {
        report.metrics.first { $0.name == metricName }?.score
    }
}

public struct MixReviewArtifactPairDetail: Hashable, Identifiable, Sendable {
    public var id: String {
        [createdAt, currentTrackId, nextTrackId, aiPlan.candidateId ?? ""].joined(separator: "|")
    }

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

public enum MixReviewArtifactPairDetailExtractor {
    public static func pairDetails(content: String) -> [MixReviewArtifactPairDetail] {
        guard let data = content.data(using: .utf8),
              let document = try? JSONDecoder().decode(MixReviewExportDocument.self, from: data)
        else {
            return []
        }
        return document.events.map {
            MixReviewArtifactPairDetail(
                createdAt: $0.createdAt,
                currentTrackId: $0.currentTrackId,
                currentTrackTitle: $0.currentTrackTitle,
                nextTrackId: $0.nextTrackId,
                nextTrackTitle: $0.nextTrackTitle,
                aiPlan: $0.aiPlan,
                fallbackPlan: $0.fallbackPlan
            )
        }
    }
}

private extension String {
    func replacingFirstMarkdownHeadingNumber() -> String {
        let withoutHeading = replacingOccurrences(of: "## ", with: "", options: [.anchored])
        guard let dotRange = withoutHeading.range(of: ". ") else {
            return withoutHeading.trimmingCharacters(in: .whitespaces)
        }
        return String(withoutHeading[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
