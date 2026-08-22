import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct MixReviewArtifactFilteringTests {
    @Test func extractsUniqueTrackPairsFromJSONExport() throws {
        let document = MixReviewExportDocument(
            generatedAt: "2026-06-17T00:00:00Z",
            events: [
                event(currentTrackId: "current-a", nextTrackId: "next-a"),
                event(currentTrackId: "current-b", nextTrackId: "next-b"),
                event(currentTrackId: "current-a", nextTrackId: "next-a")
            ]
        )
        let json = try MixReviewExportRenderer.json(document: document)

        let pairs = MixReviewArtifactPairExtractor.trackPairs(content: json)

        #expect(pairs == [
            MixReviewArtifactTrackPair(currentTrackId: "current-a", nextTrackId: "next-a"),
            MixReviewArtifactTrackPair(currentTrackId: "current-b", nextTrackId: "next-b")
        ])
    }

    @Test func extractsTrackPairsFromMarkdownExportHeadings() {
        let markdown = """
        # BeatDropper Mix Review Notes

        - Schema: 1
        - Reviews: 2

        ## 1. Current Track (current-a) -> Next Track (next-a)

        | Field | AI planner | Local fallback | Delta |

        ## 2. current-b -> next-b
        """

        let pairs = MixReviewArtifactPairExtractor.trackPairs(content: markdown)

        #expect(pairs == [
            MixReviewArtifactTrackPair(currentTrackId: "current-a", nextTrackId: "next-a"),
            MixReviewArtifactTrackPair(currentTrackId: "current-b", nextTrackId: "next-b")
        ])
    }

    @Test func oldPersistedArtifactDecodesWithNoTrackPairs() throws {
        let json = """
        {
          "id": "32CE6541-F2D3-444B-89B9-317B09056970",
          "importedAt": "2026-06-17T00:00:00Z",
          "fileName": "BeatDropper-Mix-Review-Notes.json",
          "format": "JSON",
          "content": "{}",
          "reviewCount": 1,
          "schemaVersion": 1
        }
        """

        let artifact = try JSONDecoder().decode(PersistedMixReviewArtifact.self, from: Data(json.utf8))

        #expect(artifact.trackPairs.isEmpty)
        #expect(artifact.reviewAnnotation.isEmpty)
    }

    @Test func pairFilterMatchesOnlyExactCurrentToNextPair() {
        let pairs = [
            MixReviewArtifactTrackPair(currentTrackId: "current-a", nextTrackId: "next-a"),
            MixReviewArtifactTrackPair(currentTrackId: "current-b", nextTrackId: "next-b")
        ]

        #expect(MixReviewArtifactPairFilter.matches(
            trackPairs: pairs,
            currentTrackId: "current-a",
            nextTrackId: "next-a"
        ))
        #expect(!MixReviewArtifactPairFilter.matches(
            trackPairs: pairs,
            currentTrackId: "next-a",
            nextTrackId: "current-a"
        ))
    }

    @Test func comparisonEligibilityMatchesOnlySelectedPair() {
        let pairs = [
            MixReviewArtifactTrackPair(currentTrackId: "current-a", nextTrackId: "next-a"),
            MixReviewArtifactTrackPair(currentTrackId: "current-b", nextTrackId: "next-b")
        ]

        #expect(MixReviewArtifactComparisonBuilder.isEligible(
            trackPairs: pairs,
            currentTrackId: "current-b",
            nextTrackId: "next-b"
        ))
        #expect(!MixReviewArtifactComparisonBuilder.isEligible(
            trackPairs: pairs,
            currentTrackId: "current-b",
            nextTrackId: "next-a"
        ))
    }

    @Test func artifactSearchMatchesMetadataPairsAndContent() {
        let pairs = [
            MixReviewArtifactTrackPair(currentTrackId: "current-a", nextTrackId: "next-a")
        ]

        #expect(MixReviewArtifactSearch.matches(
            fileName: "BeatDropper-Mix-Review-Notes.json",
            format: "JSON",
            reviewCount: 2,
            trackPairs: pairs,
            content: "Peak jump stayed controlled on the second phrase.",
            query: "beatdropper json"
        ))
        #expect(MixReviewArtifactSearch.matches(
            fileName: "BeatDropper-Mix-Review-Notes.json",
            format: "JSON",
            reviewCount: 2,
            trackPairs: pairs,
            content: "Peak jump stayed controlled on the second phrase.",
            query: "current-a next-a"
        ))
        #expect(MixReviewArtifactSearch.matches(
            fileName: "BeatDropper-Mix-Review-Notes.json",
            format: "JSON",
            reviewCount: 2,
            trackPairs: pairs,
            content: "Peak jump stayed controlled on the second phrase.",
            annotation: "Keep this for late-night warmup sets.",
            query: "late-night warmup"
        ))
        #expect(MixReviewArtifactSearch.matches(
            fileName: "BeatDropper-Mix-Review-Notes.json",
            format: "JSON",
            reviewCount: 2,
            trackPairs: pairs,
            content: "Peak jump stayed controlled on the second phrase.",
            query: "peak controlled"
        ))
        #expect(!MixReviewArtifactSearch.matches(
            fileName: "BeatDropper-Mix-Review-Notes.json",
            format: "JSON",
            reviewCount: 2,
            trackPairs: pairs,
            content: "Peak jump stayed controlled on the second phrase.",
            query: "missing-pair"
        ))
    }

    @Test func pairDetailExtractorBuildsReadOnlyDetailsFromJSONExport() throws {
        let document = MixReviewExportDocument(
            generatedAt: "2026-06-17T00:00:00Z",
            events: [
                MixReviewExportEvent(
                    createdAt: "2026-06-17T00:01:00Z",
                    currentTrackId: "current-a",
                    currentTrackTitle: "Current A",
                    nextTrackId: "next-a",
                    nextTrackTitle: "Next A",
                    aiPlan: plan(source: "AI planner", candidateId: "ai-cue", score: 0.86),
                    fallbackPlan: plan(source: "Local fallback", candidateId: "tail", score: 0.62)
                )
            ]
        )
        let json = try MixReviewExportRenderer.json(document: document)

        let details = MixReviewArtifactPairDetailExtractor.pairDetails(content: json)

        #expect(details.count == 1)
        #expect(details.first?.currentTrackTitle == "Current A")
        #expect(details.first?.nextTrackId == "next-a")
        #expect(details.first?.aiPlan.candidateId == "ai-cue")
        #expect(details.first?.fallbackPlan?.candidateId == "tail")
    }

    @Test func pairDetailExtractorReturnsEmptyForMarkdown() {
        let markdown = """
        # BeatDropper Mix Review Notes

        ## 1. Current Track (current-a) -> Next Track (next-a)
        """

        #expect(MixReviewArtifactPairDetailExtractor.pairDetails(content: markdown).isEmpty)
    }

    @Test func comparisonBuilderUsesSelectedPairDetail() throws {
        let leftDocument = MixReviewExportDocument(
            generatedAt: "2026-06-17T00:00:00Z",
            events: [
                MixReviewExportEvent(
                    createdAt: "2026-06-17T00:01:00Z",
                    currentTrackId: "current-a",
                    nextTrackId: "next-a",
                    aiPlan: plan(source: "AI planner", candidateId: "left-other", score: 0.74)
                ),
                MixReviewExportEvent(
                    createdAt: "2026-06-17T00:02:00Z",
                    currentTrackId: "current-b",
                    nextTrackId: "next-b",
                    aiPlan: plan(source: "AI planner", candidateId: "left-selected", score: 0.86)
                )
            ]
        )
        let rightDocument = MixReviewExportDocument(
            generatedAt: "2026-06-17T00:03:00Z",
            events: [
                MixReviewExportEvent(
                    createdAt: "2026-06-17T00:04:00Z",
                    currentTrackId: "current-b",
                    nextTrackId: "next-b",
                    aiPlan: plan(source: "AI planner", candidateId: "right-selected", score: 0.64)
                )
            ]
        )

        let comparison = MixReviewArtifactComparisonBuilder.compare(
            leftDetails: MixReviewArtifactPairDetailExtractor.pairDetails(content: try MixReviewExportRenderer.json(document: leftDocument)),
            rightDetails: MixReviewArtifactPairDetailExtractor.pairDetails(content: try MixReviewExportRenderer.json(document: rightDocument)),
            currentTrackId: "current-b",
            nextTrackId: "next-b"
        )

        #expect(comparison.hasStructuredDetails)
        #expect(comparison.leftDetail?.createdAt == "2026-06-17T00:02:00Z")
        #expect(comparison.rightDetail?.createdAt == "2026-06-17T00:04:00Z")
        #expect(comparison.aiRows.first { $0.label == "Candidate" }?.leftValue == "left-selected")
        #expect(comparison.aiRows.first { $0.label == "Candidate" }?.rightValue == "right-selected")
    }

    @Test func comparisonRowsFormatTimingConfidenceAndQualityDeltas() {
        let rows = MixReviewArtifactComparisonBuilder.comparisonRows(
            left: plan(
                source: "AI planner",
                candidateId: "left-cue",
                score: 0.86,
                transitionStartSec: 120,
                transitionEndSec: 128,
                nextTrackStartOffsetSec: 16,
                confidence: 0.82
            ),
            right: plan(
                source: "AI planner",
                candidateId: "right-cue",
                score: 0.64,
                transitionStartSec: 116,
                transitionEndSec: 124,
                nextTrackStartOffsetSec: 12,
                confidence: 0.72
            )
        )

        #expect(rows.first { $0.label == "Window" }?.delta == "start +0:04 end +0:04")
        #expect(rows.first { $0.label == "Duration" }?.delta == "same")
        #expect(rows.first { $0.label == "Next In" }?.delta == "+0:04")
        #expect(rows.first { $0.label == "Candidate" }?.delta == "diff")
        #expect(rows.first { $0.label == "Confidence" }?.delta == "+10")
        #expect(rows.first { $0.label == "Quality" }?.delta == "+22")
    }

    @Test func comparisonRowsReportSameStartDifferentEndAndDuration() {
        let rows = MixReviewArtifactComparisonBuilder.comparisonRows(
            left: plan(
                source: "AI planner",
                candidateId: "left-cue",
                score: 0.86,
                transitionStartSec: 120,
                transitionEndSec: 132
            ),
            right: plan(
                source: "AI planner",
                candidateId: "right-cue",
                score: 0.86,
                transitionStartSec: 120,
                transitionEndSec: 128
            )
        )

        #expect(rows.first { $0.label == "Window" }?.delta == "end +0:04 dur +0:04")
        #expect(rows.first { $0.label == "Duration" }?.leftValue == "0:12")
        #expect(rows.first { $0.label == "Duration" }?.rightValue == "0:08")
        #expect(rows.first { $0.label == "Duration" }?.delta == "+0:04")
    }

    @Test func comparisonRowsIncludeRenderedMetricDeltas() {
        let rows = MixReviewArtifactComparisonBuilder.comparisonRows(
            left: plan(
                source: "AI planner",
                candidateId: "left-cue",
                score: 0.86,
                metrics: [
                    metric("estimated_peak", score: 0.90, summary: "max -4.0 dB"),
                    metric("peak_jump", score: 0.80, summary: "jump 2.0 dB"),
                    metric("rms_jump", score: 0.70, summary: "jump 3.0 dB"),
                    metric("spectral_masking", score: 0.60, summary: "risk 40%")
                ]
            ),
            right: plan(
                source: "AI planner",
                candidateId: "right-cue",
                score: 0.64,
                metrics: [
                    metric("estimated_peak", score: 0.70, summary: "max -1.0 dB"),
                    metric("peak_jump", score: 0.50, summary: "jump 5.0 dB"),
                    metric("rms_jump", score: 0.60, summary: "jump 4.0 dB"),
                    metric("spectral_masking", score: 0.30, summary: "risk 70%")
                ]
            )
        )

        #expect(rows.first { $0.label == "Estimated Peak" }?.leftValue == "max -4.0 dB")
        #expect(rows.first { $0.label == "Estimated Peak" }?.rightValue == "max -1.0 dB")
        #expect(rows.first { $0.label == "Estimated Peak" }?.delta == "+20")
        #expect(rows.first { $0.label == "Peak Jump" }?.delta == "+30")
        #expect(rows.first { $0.label == "RMS Jump" }?.delta == "+10")
        #expect(rows.first { $0.label == "Spectral Masking" }?.delta == "+30")
    }

    @Test func comparisonRowsHandleMissingMetrics() {
        let rows = MixReviewArtifactComparisonBuilder.comparisonRows(
            left: plan(
                source: "AI planner",
                candidateId: "left-cue",
                score: 0.86,
                metrics: [metric("estimated_peak", score: 0.90, summary: "max -4.0 dB")]
            ),
            right: plan(
                source: "AI planner",
                candidateId: "right-cue",
                score: 0.64,
                metrics: []
            )
        )

        #expect(rows.first { $0.label == "Estimated Peak" }?.leftValue == "max -4.0 dB")
        #expect(rows.first { $0.label == "Estimated Peak" }?.rightValue == "--")
        #expect(rows.first { $0.label == "Estimated Peak" }?.delta == "--")
        #expect(rows.first { $0.label == "Peak Jump" }?.leftValue == "--")
        #expect(rows.first { $0.label == "Peak Jump" }?.rightValue == "--")
        #expect(rows.first { $0.label == "Peak Jump" }?.delta == "--")
    }

    @Test func comparisonRowsIncludeFullWindowDeltaWhenStartEndAndDurationChange() {
        let rows = MixReviewArtifactComparisonBuilder.comparisonRows(
            left: plan(
                source: "AI planner",
                candidateId: "left-cue",
                score: 0.86,
                transitionStartSec: 124,
                transitionEndSec: 136
            ),
            right: plan(
                source: "AI planner",
                candidateId: "right-cue",
                score: 0.86,
                transitionStartSec: 120,
                transitionEndSec: 128
            )
        )

        #expect(rows.first { $0.label == "Window" }?.delta == "start +0:04 end +0:08 dur +0:04")
    }

    @Test func comparisonSummaryIncludesMetadataRowsAndAnnotations() {
        let summary = comparisonSummary(
            leftAnnotation: "left review note",
            rightAnnotation: "right review note"
        )
        let markdown = MixReviewArtifactComparisonSummaryRenderer.markdown(summary)

        #expect(markdown.contains("# BeatDropper Imported Artifact Compare"))
        #expect(markdown.contains("- Pair: current-b -> next-b"))
        #expect(markdown.contains("| File | left.json | right.json |"))
        #expect(markdown.contains("| Format | JSON | Markdown |"))
        #expect(markdown.contains("| Reviews | 2 | 3 |"))
        #expect(markdown.contains("| Annotation | left review note | right review note |"))
        #expect(markdown.contains("This summary is review-only and does not affect playback or planner behavior."))
    }

    @Test func comparisonSummaryIncludesPlanRowsMetricsAndMissingMetricFallback() {
        let summary = comparisonSummary(
            leftPlan: plan(
                source: "AI planner",
                candidateId: "left-cue",
                score: 0.86,
                transitionStartSec: 124,
                transitionEndSec: 136,
                metrics: [metric("estimated_peak", score: 0.90, summary: "max -4.0 dB")]
            ),
            rightPlan: plan(
                source: "AI planner",
                candidateId: "right-cue",
                score: 0.64,
                transitionStartSec: 120,
                transitionEndSec: 128,
                metrics: []
            )
        )
        let markdown = MixReviewArtifactComparisonSummaryRenderer.markdown(summary)

        #expect(markdown.contains("## AI Plan"))
        #expect(markdown.contains("| Window | 2:04 -> 2:16 | 2:00 -> 2:08 | start +0:04 end +0:08 dur +0:04 |"))
        #expect(markdown.contains("| Estimated Peak | max -4.0 dB | -- | -- |"))
        #expect(markdown.contains("| Peak Jump | -- | -- | -- |"))
    }

    @Test func comparisonSummaryEscapesMarkdownTablePipesAndNewlines() {
        let summary = comparisonSummary(
            leftFileName: "left | export.json",
            rightFileName: "right.md",
            leftAnnotation: "left | note",
            rightAnnotation: "right\nnote"
        )
        let markdown = MixReviewArtifactComparisonSummaryRenderer.markdown(summary)

        #expect(markdown.contains("| File | left \\| export.json | right.md |"))
        #expect(markdown.contains("| Annotation | left \\| note | right<br>note |"))
    }

    @Test func plannerDiagnosticsClassifyTimingAndQualityWorseThanFallback() {
        let diagnostic = MixReviewPlannerDiagnostics.diagnose(
            currentTrackId: "current-b",
            nextTrackId: "next-b",
            aiPlan: plan(
                source: "AI planner",
                candidateId: "shared-cue",
                score: 0.60,
                transitionStartSec: 124,
                transitionEndSec: 136,
                nextTrackStartOffsetSec: 20,
                metrics: completeMetrics(score: 0.60)
            ),
            fallbackPlan: plan(
                source: "Local fallback",
                candidateId: "shared-cue",
                score: 0.88,
                transitionStartSec: 120,
                transitionEndSec: 128,
                nextTrackStartOffsetSec: 16,
                metrics: completeMetrics(score: 0.88)
            )
        )

        #expect(diagnostic.verdict == .fallbackStronger)
        #expect(diagnostic.findings.contains { $0.kind == .qualityWorse })
        #expect(diagnostic.findings.contains { $0.kind == .timingWorse && $0.delta.contains("start +0:04") })
        #expect(diagnostic.findings.contains { $0.kind == .metricWorse && $0.field == "spectral_masking" })
    }

    @Test func plannerDiagnosticsClassifyCandidateMismatchWhenFallbackRendersStronger() {
        let diagnostic = MixReviewPlannerDiagnostics.diagnose(
            currentTrackId: "current-b",
            nextTrackId: "next-b",
            aiPlan: plan(
                source: "AI planner",
                candidateId: "stale-tail",
                score: 0.58,
                metrics: completeMetrics(score: 0.58)
            ),
            fallbackPlan: plan(
                source: "Local fallback",
                candidateId: "analysis-cue",
                score: 0.86,
                metrics: completeMetrics(score: 0.86)
            )
        )

        #expect(diagnostic.verdict == .fallbackStronger)
        #expect(diagnostic.findings.contains {
            $0.kind == .candidateMismatch &&
                $0.aiValue == "stale-tail" &&
                $0.fallbackValue == "analysis-cue"
        })
    }

    @Test func plannerDiagnosticsClassifyConfidenceWeakness() {
        let diagnostic = MixReviewPlannerDiagnostics.diagnose(
            currentTrackId: "current-b",
            nextTrackId: "next-b",
            aiPlan: plan(
                source: "AI planner",
                candidateId: "shared-cue",
                score: 0.88,
                confidence: 0.52,
                metrics: completeMetrics(score: 0.88)
            ),
            fallbackPlan: plan(
                source: "Local fallback",
                candidateId: "shared-cue",
                score: 0.88,
                confidence: 0.72,
                metrics: completeMetrics(score: 0.88)
            )
        )

        #expect(diagnostic.verdict == .mixed)
        #expect(diagnostic.findings.contains {
            $0.kind == .confidenceWorse &&
                $0.aiValue == "52%" &&
                $0.fallbackValue == "72%"
        })
    }

    @Test func plannerDiagnosticsReportMissingMetricEvidence() {
        let diagnostic = MixReviewPlannerDiagnostics.diagnose(
            currentTrackId: "current-b",
            nextTrackId: "next-b",
            aiPlan: plan(
                source: "AI planner",
                candidateId: "shared-cue",
                score: 0.88,
                metrics: []
            ),
            fallbackPlan: plan(
                source: "Local fallback",
                candidateId: "shared-cue",
                score: 0.88,
                metrics: completeMetrics(score: 0.88)
            )
        )

        #expect(diagnostic.verdict == .incompleteEvidence)
        #expect(diagnostic.weaknessCount == 0)
        #expect(diagnostic.findings.contains { $0.kind == .missingMetric && $0.field == "estimated_peak" })
    }

    @Test func comparisonBuilderFallsBackWhenOneArtifactHasNoStructuredDetails() {
        let comparison = MixReviewArtifactComparisonBuilder.compare(
            leftDetails: [],
            rightDetails: [
                MixReviewArtifactPairDetail(
                    createdAt: "2026-06-17T00:04:00Z",
                    currentTrackId: "current-b",
                    nextTrackId: "next-b",
                    aiPlan: plan(source: "AI planner", candidateId: "right-selected", score: 0.64)
                )
            ],
            currentTrackId: "current-b",
            nextTrackId: "next-b"
        )

        #expect(!comparison.hasStructuredDetails)
        #expect(comparison.leftDetail == nil)
        #expect(comparison.rightDetail?.aiPlan.candidateId == "right-selected")
        #expect(comparison.aiRows.first { $0.label == "Candidate" }?.leftValue == "--")
        #expect(comparison.aiRows.first { $0.label == "Candidate" }?.rightValue == "right-selected")
        #expect(comparison.aiRows.first { $0.label == "Quality" }?.delta == "--")
    }

    private func event(currentTrackId: String, nextTrackId: String) -> MixReviewExportEvent {
        MixReviewExportEvent(
            createdAt: "2026-06-17T00:01:00Z",
            currentTrackId: currentTrackId,
            currentTrackTitle: nil,
            nextTrackId: nextTrackId,
            nextTrackTitle: nil,
            aiPlan: MixReviewExportPlan(
                source: "AI planner",
                transitionStartSec: 100,
                transitionEndSec: 108,
                nextTrackStartOffsetSec: 16,
                style: .smoothBlend,
                confidence: 0.82,
                candidateId: "cue",
                renderedQuality: quality(score: 0.86)
            )
        )
    }

    private func plan(
        source: String,
        candidateId: String,
        score: Double,
        transitionStartSec: Double = 100,
        transitionEndSec: Double = 108,
        nextTrackStartOffsetSec: Double = 16,
        confidence: Double = 0.82,
        metrics: [RenderedTransitionQualityMetric] = []
    ) -> MixReviewExportPlan {
        MixReviewExportPlan(
            source: source,
            transitionStartSec: transitionStartSec,
            transitionEndSec: transitionEndSec,
            nextTrackStartOffsetSec: nextTrackStartOffsetSec,
            style: .smoothBlend,
            confidence: confidence,
            candidateId: candidateId,
            renderedQuality: quality(score: score, metrics: metrics)
        )
    }

    private func quality(
        score: Double,
        metrics: [RenderedTransitionQualityMetric] = []
    ) -> RenderedTransitionQualityReport {
        RenderedTransitionQualityReport(
            score: score,
            grade: score >= 0.8 ? .pass : .warn,
            shouldApply: true,
            issues: [],
            metrics: metrics,
            summary: "quality \(score)"
        )
    }

    private func metric(_ name: String, score: Double, summary: String) -> RenderedTransitionQualityMetric {
        RenderedTransitionQualityMetric(name: name, value: score, score: score, summary: summary)
    }

    private func completeMetrics(score: Double) -> [RenderedTransitionQualityMetric] {
        [
            metric("estimated_peak", score: score, summary: "max -4.0 dB"),
            metric("peak_jump", score: score, summary: "jump 2.0 dB"),
            metric("rms_jump", score: score, summary: "jump 3.0 dB"),
            metric("spectral_masking", score: score, summary: "risk 40%")
        ]
    }

    private func comparisonSummary(
        leftFileName: String = "left.json",
        rightFileName: String = "right.json",
        leftAnnotation: String = "",
        rightAnnotation: String = "",
        leftPlan: MixReviewExportPlan? = nil,
        rightPlan: MixReviewExportPlan? = nil
    ) -> MixReviewArtifactComparisonSummary {
        let leftPlan = leftPlan ?? plan(source: "AI planner", candidateId: "left-cue", score: 0.86)
        let rightPlan = rightPlan ?? plan(source: "AI planner", candidateId: "right-cue", score: 0.64)
        let pairComparison = MixReviewArtifactComparisonBuilder.compare(
            leftDetails: [
                MixReviewArtifactPairDetail(
                    createdAt: "2026-06-17T00:02:00Z",
                    currentTrackId: "current-b",
                    nextTrackId: "next-b",
                    aiPlan: leftPlan
                )
            ],
            rightDetails: [
                MixReviewArtifactPairDetail(
                    createdAt: "2026-06-17T00:04:00Z",
                    currentTrackId: "current-b",
                    nextTrackId: "next-b",
                    aiPlan: rightPlan
                )
            ],
            currentTrackId: "current-b",
            nextTrackId: "next-b"
        )
        return MixReviewArtifactComparisonSummary(
            currentTrackId: "current-b",
            nextTrackId: "next-b",
            left: MixReviewArtifactComparisonSummarySide(
                label: "Left",
                fileName: leftFileName,
                format: "JSON",
                importedAt: "2026-06-17T00:10:00Z",
                reviewCount: 2,
                annotation: leftAnnotation
            ),
            right: MixReviewArtifactComparisonSummarySide(
                label: "Right",
                fileName: rightFileName,
                format: "Markdown",
                importedAt: "2026-06-17T00:20:00Z",
                reviewCount: 3,
                annotation: rightAnnotation
            ),
            pairComparison: pairComparison
        )
    }
}
