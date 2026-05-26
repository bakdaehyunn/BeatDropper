import Foundation

public enum NativePlannerBenchmarkGrade: String, Codable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
}

public struct NativePlannerBenchmarkExpectation: Sendable {
    public var allowedStyles: [MixStyle]
    public var minConfidence: Double
    public var maxTransitionEndSec: Double?
    public var expectedNextOffsetSec: Double?
    public var nextOffsetToleranceSec: Double
    public var expectTempoSync: Bool?
    public var expectedCandidateId: String?
    public var requiredEvidence: [String]

    public init(
        allowedStyles: [MixStyle],
        minConfidence: Double,
        maxTransitionEndSec: Double? = nil,
        expectedNextOffsetSec: Double? = nil,
        nextOffsetToleranceSec: Double = 0.75,
        expectTempoSync: Bool? = nil,
        expectedCandidateId: String? = nil,
        requiredEvidence: [String] = []
    ) {
        self.allowedStyles = allowedStyles
        self.minConfidence = minConfidence
        self.maxTransitionEndSec = maxTransitionEndSec
        self.expectedNextOffsetSec = expectedNextOffsetSec
        self.nextOffsetToleranceSec = nextOffsetToleranceSec
        self.expectTempoSync = expectTempoSync
        self.expectedCandidateId = expectedCandidateId
        self.requiredEvidence = requiredEvidence
    }
}

public struct NativePlannerBenchmarkCase: Sendable {
    public var name: String
    public var request: PlannerRequest
    public var validationContext: MixPlanValidationContext
    public var expectation: NativePlannerBenchmarkExpectation

    public init(
        name: String,
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        expectation: NativePlannerBenchmarkExpectation
    ) {
        self.name = name
        self.request = request
        self.validationContext = validationContext
        self.expectation = expectation
    }
}

public struct NativePlannerBenchmarkResult: Sendable {
    public var name: String
    public var grade: NativePlannerBenchmarkGrade
    public var plan: MixPlan?
    public var failures: [String]
    public var warnings: [String]

    public init(
        name: String,
        grade: NativePlannerBenchmarkGrade,
        plan: MixPlan?,
        failures: [String],
        warnings: [String]
    ) {
        self.name = name
        self.grade = grade
        self.plan = plan
        self.failures = failures
        self.warnings = warnings
    }
}

public struct NativePlannerBenchmarkSummary: Sendable {
    public var results: [NativePlannerBenchmarkResult]

    public init(results: [NativePlannerBenchmarkResult]) {
        self.results = results
    }

    public var passCount: Int {
        results.filter { $0.grade == .pass }.count
    }

    public var warnCount: Int {
        results.filter { $0.grade == .warn }.count
    }

    public var failCount: Int {
        results.filter { $0.grade == .fail }.count
    }

    public var status: NativePlannerBenchmarkGrade {
        failCount > 0 ? .fail : warnCount > 0 ? .warn : .pass
    }
}

public enum NativePlannerBenchmarkSuite {
    public static func run(cases: [NativePlannerBenchmarkCase] = defaultCases()) -> NativePlannerBenchmarkSummary {
        NativePlannerBenchmarkSummary(results: cases.map(runCase))
    }

    public static func runCase(_ benchmark: NativePlannerBenchmarkCase) -> NativePlannerBenchmarkResult {
        let plan = NativeFallbackMixPlanner.buildPlan(
            request: benchmark.request,
            validationContext: benchmark.validationContext,
            failureReason: "benchmark_planner_unavailable"
        )
        var failures: [String] = []
        var warnings: [String] = []

        guard let plan else {
            return NativePlannerBenchmarkResult(
                name: benchmark.name,
                grade: .fail,
                plan: nil,
                failures: ["planner returned no fallback plan"],
                warnings: []
            )
        }

        let expectation = benchmark.expectation
        if !expectation.allowedStyles.contains(plan.style) {
            failures.append("style \(plan.style.rawValue) not in allowed styles \(expectation.allowedStyles.map(\.rawValue).joined(separator: ","))")
        }
        if plan.confidence < expectation.minConfidence {
            failures.append("confidence \(format(plan.confidence)) below minimum \(format(expectation.minConfidence))")
        }
        if plan.transitionStartSec < benchmark.request.currentPlayback.elapsedSec {
            failures.append("transition starts before current playback elapsed")
        }
        if plan.transitionEndSec <= plan.transitionStartSec {
            failures.append("transition window is not positive")
        }
        if plan.transitionEndSec > benchmark.request.currentTrack.durationSec {
            failures.append("transition ends after current track duration")
        }
        if let maxTransitionEndSec = expectation.maxTransitionEndSec,
           plan.transitionEndSec > maxTransitionEndSec {
            failures.append("transition end \(format(plan.transitionEndSec)) exceeds expected max \(format(maxTransitionEndSec))")
        }
        if let expectedNextOffsetSec = expectation.expectedNextOffsetSec,
           abs(plan.nextTrackStartOffsetSec - expectedNextOffsetSec) > expectation.nextOffsetToleranceSec {
            failures.append("next offset \(format(plan.nextTrackStartOffsetSec)) differs from expected \(format(expectedNextOffsetSec))")
        }
        if let expectTempoSync = expectation.expectTempoSync,
           plan.tempoSync.enabled != expectTempoSync {
            failures.append("tempo sync \(plan.tempoSync.enabled) does not match expected \(expectTempoSync)")
        }
        if let expectedCandidateId = expectation.expectedCandidateId,
           plan.candidateId != expectedCandidateId {
            failures.append("candidate \(plan.candidateId ?? "--") does not match expected \(expectedCandidateId)")
        }
        for requiredEvidence in expectation.requiredEvidence
            where !plan.evidence.contains(where: { $0.localizedCaseInsensitiveContains(requiredEvidence) }) {
            failures.append("evidence missing \(requiredEvidence)")
        }
        if plan.evidence.isEmpty {
            warnings.append("plan has no evidence strings")
        }
        if plan.reasoningSummary?.isEmpty != false {
            warnings.append("plan has no reasoning summary")
        }

        let grade: NativePlannerBenchmarkGrade = failures.isEmpty
            ? (warnings.isEmpty ? .pass : .warn)
            : .fail
        return NativePlannerBenchmarkResult(
            name: benchmark.name,
            grade: grade,
            plan: plan,
            failures: failures,
            warnings: warnings
        )
    }

    public static func defaultCases() -> [NativePlannerBenchmarkCase] {
        [
            cueRichCloseBPMCase(mode: .safe),
            cueRichCloseBPMCase(mode: .adventurous),
            sparseBigGapCase(),
            partialCueMidGapCase(),
            staleTailRecommendationCase(),
            emergencyTailCase()
        ]
    }

    private static func cueRichCloseBPMCase(mode: AIDJMode) -> NativePlannerBenchmarkCase {
        let current = Track(id: "native-bench-current-a", title: "Cue Rich Current", durationSec: 210, format: .wav, bpm: 124)
        let next = Track(id: "native-bench-next-a", title: "Cue Rich Next", durationSec: 200, format: .wav, bpm: 126)
        let candidate = MixCandidate(
            id: "cue-rich-analysis",
            currentTrackId: current.id,
            nextTrackId: next.id,
            source: .analysis,
            evidenceLevel: .strong,
            requiresAnalysisUpgrade: false,
            currentMixOutSec: 188,
            nextMixInSec: mode == .adventurous ? 8 : 12,
            currentBarIndex: 88,
            nextBarIndex: mode == .adventurous ? 16 : 88,
            phraseAlignment: mode == .adventurous ? .aligned : .aligned,
            bpmDelta: 2,
            tempoSyncRate: 124 / 126,
            energyDelta: mode == .adventurous ? 0.34 : 0.1,
            style: mode == .adventurous ? .energySwap : .smoothBlend,
            score: mode == .adventurous ? 0.82 : 0.88,
            confidence: mode == .adventurous ? 0.82 : 0.88,
            reason: mode == .adventurous ? "phrase aligned energy lift" : "phrase aligned cue-rich overlap"
        )
        return benchmarkCase(
            name: "cue-rich-close-bpm-\(mode.rawValue)",
            current: current,
            next: next,
            elapsedSec: 176,
            mode: mode,
            fadeDurationSec: 8,
            candidates: [candidate],
            recommendedCandidateId: candidate.id,
            readiness: .ready,
            expectation: NativePlannerBenchmarkExpectation(
                allowedStyles: [mode == .adventurous ? .energySwap : .smoothBlend],
                minConfidence: 0.72,
                maxTransitionEndSec: 188,
                expectedNextOffsetSec: candidate.nextMixInSec,
                expectTempoSync: true,
                expectedCandidateId: candidate.id,
                requiredEvidence: [
                    "source analysis",
                    "evidence strong",
                    "phrase aligned",
                    "BPM delta"
                ]
            )
        )
    }

    private static func sparseBigGapCase() -> NativePlannerBenchmarkCase {
        let current = Track(id: "native-bench-current-b", title: "Sparse Current", durationSec: 198, format: .wav, bpm: 100)
        let next = Track(id: "native-bench-next-b", title: "Sparse Next", durationSec: 214, format: .wav, bpm: 136)
        let candidate = MixCandidate(
            id: "sparse-hard-cut",
            currentTrackId: current.id,
            nextTrackId: next.id,
            source: .tailFallback,
            evidenceLevel: .fallback,
            requiresAnalysisUpgrade: true,
            currentMixOutSec: 190,
            nextMixInSec: 0,
            currentBarIndex: nil,
            nextBarIndex: nil,
            phraseAlignment: .free,
            bpmDelta: 36,
            tempoSyncRate: 0.85,
            energyDelta: 0.06,
            style: .hardCut,
            score: 0.34,
            confidence: 0.34,
            reason: "fallback hard cut for sparse cues and large bpm gap"
        )
        return benchmarkCase(
            name: "sparse-big-gap-adventurous",
            current: current,
            next: next,
            elapsedSec: 183,
            mode: .adventurous,
            fadeDurationSec: 8,
            candidates: [candidate],
            recommendedCandidateId: nil,
            readiness: .fallbackOnly,
            expectation: NativePlannerBenchmarkExpectation(
                allowedStyles: [.hardCut],
                minConfidence: 0.28,
                maxTransitionEndSec: 198,
                expectedNextOffsetSec: 0,
                expectTempoSync: false,
                expectedCandidateId: candidate.id,
                requiredEvidence: [
                    "source tail_fallback",
                    "evidence fallback",
                    "phrase free",
                    "planner failure"
                ]
            )
        )
    }

    private static func partialCueMidGapCase() -> NativePlannerBenchmarkCase {
        let current = Track(id: "native-bench-current-c", title: "Partial Cue Current", durationSec: 232, format: .wav, bpm: 118)
        let next = Track(id: "native-bench-next-c", title: "Partial Cue Next", durationSec: 205, format: .wav, bpm: 123)
        let cueCandidate = MixCandidate(
            id: "partial-cue",
            currentTrackId: current.id,
            nextTrackId: next.id,
            source: .cue,
            evidenceLevel: .partial,
            requiresAnalysisUpgrade: false,
            currentMixOutSec: 216,
            nextMixInSec: 0,
            currentBarIndex: 52,
            nextBarIndex: 0,
            phraseAlignment: .near,
            bpmDelta: 5,
            tempoSyncRate: 118 / 123,
            energyDelta: 0.12,
            style: .smoothBlend,
            score: 0.64,
            confidence: 0.64,
            reason: "partial cue with moderate bpm gap"
        )
        return benchmarkCase(
            name: "partial-cue-mid-gap-balanced",
            current: current,
            next: next,
            elapsedSec: 207,
            mode: .balanced,
            fadeDurationSec: 7,
            candidates: [cueCandidate],
            recommendedCandidateId: cueCandidate.id,
            readiness: .ready,
            expectation: NativePlannerBenchmarkExpectation(
                allowedStyles: [.smoothBlend, .energySwap],
                minConfidence: 0.5,
                maxTransitionEndSec: 216,
                expectedNextOffsetSec: 0,
                expectTempoSync: true,
                expectedCandidateId: cueCandidate.id,
                requiredEvidence: [
                    "source cue",
                    "evidence partial",
                    "phrase near",
                    "BPM delta"
                ]
            )
        )
    }

    private static func emergencyTailCase() -> NativePlannerBenchmarkCase {
        let current = Track(id: "native-bench-current-d", title: "Emergency Current", durationSec: 160, format: .wav, bpm: nil)
        let next = Track(id: "native-bench-next-d", title: "Emergency Next", durationSec: 180, format: .wav, bpm: nil)
        return benchmarkCase(
            name: "emergency-tail-no-candidates",
            current: current,
            next: next,
            elapsedSec: 151,
            mode: .safe,
            fadeDurationSec: 8,
            candidates: [],
            recommendedCandidateId: nil,
            readiness: .fallbackOnly,
            expectation: NativePlannerBenchmarkExpectation(
                allowedStyles: [.smoothBlend],
                minConfidence: 0.18,
                maxTransitionEndSec: 160,
                expectedNextOffsetSec: 0,
                expectTempoSync: false,
                expectedCandidateId: "native-emergency-tail",
                requiredEvidence: [
                    "local fallback",
                    "emergency tail mix",
                    "planner failure"
                ]
            )
        )
    }

    private static func staleTailRecommendationCase() -> NativePlannerBenchmarkCase {
        let current = Track(id: "native-bench-current-e", title: "Stale Recommendation Current", durationSec: 210, format: .wav, bpm: 124)
        let next = Track(id: "native-bench-next-e", title: "Stale Recommendation Next", durationSec: 200, format: .wav, bpm: 126)
        let analysisCandidate = MixCandidate(
            id: "analysis-over-stale-tail",
            currentTrackId: current.id,
            nextTrackId: next.id,
            source: .analysis,
            evidenceLevel: .strong,
            requiresAnalysisUpgrade: false,
            currentMixOutSec: 188,
            nextMixInSec: 16,
            currentBarIndex: 88,
            nextBarIndex: 8,
            phraseAlignment: .aligned,
            bpmDelta: 2,
            tempoSyncRate: 124 / 126,
            energyDelta: 0.14,
            style: .smoothBlend,
            score: 0.72,
            confidence: 0.72,
            reason: "analysis phrase boundary"
        )
        let staleTailCandidate = MixCandidate(
            id: "stale-tail-recommendation",
            currentTrackId: current.id,
            nextTrackId: next.id,
            source: .tailFallback,
            evidenceLevel: .fallback,
            requiresAnalysisUpgrade: true,
            currentMixOutSec: 194,
            nextMixInSec: 0,
            currentBarIndex: nil,
            nextBarIndex: nil,
            phraseAlignment: .free,
            bpmDelta: 2,
            tempoSyncRate: 124 / 126,
            energyDelta: 0,
            style: .hardCut,
            score: 0.99,
            confidence: 0.99,
            reason: "stale recommended tail fallback"
        )
        return benchmarkCase(
            name: "stale-tail-recommendation-balanced",
            current: current,
            next: next,
            elapsedSec: 176,
            mode: .balanced,
            fadeDurationSec: 8,
            candidates: [staleTailCandidate, analysisCandidate],
            recommendedCandidateId: staleTailCandidate.id,
            readiness: .ready,
            expectation: NativePlannerBenchmarkExpectation(
                allowedStyles: [.smoothBlend],
                minConfidence: 0.62,
                maxTransitionEndSec: 188,
                expectedNextOffsetSec: 16,
                expectTempoSync: true,
                expectedCandidateId: analysisCandidate.id,
                requiredEvidence: [
                    "source analysis",
                    "evidence strong",
                    "phrase aligned",
                    "BPM delta"
                ]
            )
        )
    }

    private static func benchmarkCase(
        name: String,
        current: Track,
        next: Track,
        elapsedSec: Double,
        mode: AIDJMode,
        fadeDurationSec: Double,
        candidates: [MixCandidate],
        recommendedCandidateId: String?,
        readiness: MixPairReadiness,
        expectation: NativePlannerBenchmarkExpectation
    ) -> NativePlannerBenchmarkCase {
        let request = PlannerRequest(
            currentTrack: PlannerTrackSnapshot(track: current),
            nextTrack: PlannerTrackSnapshot(track: next),
            currentPlayback: PlannerPlaybackSnapshot(
                elapsedSec: elapsedSec,
                remainingSec: max(0, current.durationSec - elapsedSec)
            ),
            analysis: PlannerAnalysisPair(current: nil, next: nil),
            analysisSummary: nil,
            pairContext: MixPairContext(
                currentTrackId: current.id,
                nextTrackId: next.id,
                candidates: candidates,
                recommendedCandidateId: recommendedCandidateId,
                readiness: readiness
            ),
            settings: PlannerSettingsSnapshot(fadeDurationSec: fadeDurationSec, aiDjMode: mode)
        )
        return NativePlannerBenchmarkCase(
            name: name,
            request: request,
            validationContext: MixPlanValidationContext(
                currentPlaybackElapsedSec: elapsedSec,
                currentTrackDurationSec: current.durationSec,
                nextTrackDurationSec: next.durationSec,
                maxFadeDurationSec: fadeDurationSec
            ),
            expectation: expectation
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
