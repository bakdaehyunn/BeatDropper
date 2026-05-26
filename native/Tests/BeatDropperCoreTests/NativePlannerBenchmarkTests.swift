import BeatDropperCore
import Testing

struct NativePlannerBenchmarkTests {
    @Test func defaultPlannerBenchmarkSuiteHasNoFailures() {
        let summary = NativePlannerBenchmarkSuite.run()

        #expect(summary.failCount == 0)
        #expect(summary.passCount >= 4)
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
