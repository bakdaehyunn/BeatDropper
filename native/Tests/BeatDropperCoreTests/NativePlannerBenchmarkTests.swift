import BeatDropperCore
import Testing

struct NativePlannerBenchmarkTests {
    @Test func defaultPlannerBenchmarkSuiteHasNoFailures() {
        let summary = NativePlannerBenchmarkSuite.run()

        #expect(summary.failCount == 0)
        #expect(summary.passCount >= 4)
        #expect(summary.results.allSatisfy { !$0.qualityComparisons.isEmpty })
        #expect(summary.results.allSatisfy { result in
            result.qualityComparisons.contains { $0.role == "ai_planner" }
        })
        #expect(summary.results.allSatisfy { result in
            result.qualityComparisons.contains { $0.role == "local_fallback" }
        })
        #expect(summary.results.allSatisfy { !$0.plannerDiagnostics.isEmpty })
        #expect(summary.results.allSatisfy { $0.acceptanceDecision != nil })
        #expect(summary.results.allSatisfy { $0.selectedPlan != nil })
        #expect(summary.results.allSatisfy { $0.selectedPlanRole != nil })
        #expect(summary.results.allSatisfy { result in
            result.qualityComparisons.filter(\.isSelected).count == 1
        })
        #expect(summary.results.contains { result in
            result.qualityComparisons.contains { !$0.isSelected }
        })
    }

    @Test func plannerBenchmarkComparesAIPlannerQualityAgainstLocalFallbackAndCandidateAlternatives() throws {
        let benchmark = NativePlannerBenchmarkSuite.defaultCases()
            .first { $0.name == "stale-tail-recommendation-balanced" }
        let result = NativePlannerBenchmarkSuite.runCase(try #require(benchmark))

        let ai = result.qualityComparisons.first { $0.role == "ai_planner" }
        let fallback = result.qualityComparisons.first { $0.role == "local_fallback" }
        let alternatives = result.qualityComparisons.filter { $0.role == "candidate_alternative" }

        #expect(result.aiPlannerPlan != nil)
        #expect(result.selectedPlanRole == .aiPlanner)
        #expect(result.acceptanceDecision?.selectedRole == .aiPlanner)
        #expect(result.acceptanceDecision?.rejectedRole == .localFallback)
        #expect(result.plannerDiagnostics.first?.currentTrackId == "native-bench-current-e")
        #expect(result.plannerDiagnostics.first?.nextTrackId == "native-bench-next-e")
        #expect(ai?.candidateId == "analysis-over-stale-tail")
        #expect(fallback?.candidateId == "analysis-over-stale-tail")
        #expect(alternatives.contains { $0.candidateId == "stale-tail-recommendation" })
        #expect(result.qualityComparisons.allSatisfy { !$0.renderedQuality.metrics.isEmpty })
        #expect(result.plannerDiagnostics.allSatisfy { $0.verdict != .missingFallback })
    }

    @Test func benchmarkCatchesWrongStylesAndLowConfidence() {
        var benchmark = NativePlannerBenchmarkSuite.defaultCases()[0]
        benchmark.expectation = NativePlannerBenchmarkExpectation(
            allowedStyles: [.hardCut],
            minConfidence: 0.99
        )

        let result = NativePlannerBenchmarkSuite.runCase(benchmark)

        #expect(result.grade == .fail)
        #expect(result.failures.contains { $0.contains("style") })
        #expect(result.failures.contains { $0.contains("confidence") })
    }

    @Test func benchmarkCatchesMissingRequiredEvidence() {
        var benchmark = NativePlannerBenchmarkSuite.defaultCases()[0]
        benchmark.expectation = NativePlannerBenchmarkExpectation(
            allowedStyles: [.smoothBlend],
            minConfidence: 0.5,
            expectedCandidateId: "cue-rich-analysis",
            requiredEvidence: ["nonexistent evidence marker"]
        )

        let result = NativePlannerBenchmarkSuite.runCase(benchmark)

        #expect(result.grade == .fail)
        #expect(result.failures.contains { $0.contains("evidence missing nonexistent evidence marker") })
    }
}
