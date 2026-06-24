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
    public var aiPlannerPlan: MixPlan?

    public init(
        name: String,
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        expectation: NativePlannerBenchmarkExpectation,
        aiPlannerPlan: MixPlan? = nil
    ) {
        self.name = name
        self.request = request
        self.validationContext = validationContext
        self.expectation = expectation
        self.aiPlannerPlan = aiPlannerPlan
    }
}

public struct NativePlannerBenchmarkResult: Sendable {
    public var name: String
    public var grade: NativePlannerBenchmarkGrade
    public var plan: MixPlan?
    public var selectedPlan: MixPlan?
    public var rejectedPlan: MixPlan?
    public var selectedPlanRole: MixPlanAcceptanceSelectedRole?
    public var aiPlannerPlan: MixPlan?
    public var acceptanceDecision: MixPlanAcceptanceDecision?
    public var qualityComparisons: [NativePlannerQualityComparison]
    public var plannerDiagnostics: [MixReviewPlannerDiagnosticSummary]
    public var failures: [String]
    public var warnings: [String]

    public init(
        name: String,
        grade: NativePlannerBenchmarkGrade,
        plan: MixPlan?,
        selectedPlan: MixPlan? = nil,
        rejectedPlan: MixPlan? = nil,
        selectedPlanRole: MixPlanAcceptanceSelectedRole? = nil,
        aiPlannerPlan: MixPlan? = nil,
        acceptanceDecision: MixPlanAcceptanceDecision? = nil,
        qualityComparisons: [NativePlannerQualityComparison] = [],
        plannerDiagnostics: [MixReviewPlannerDiagnosticSummary] = [],
        failures: [String],
        warnings: [String]
    ) {
        self.name = name
        self.grade = grade
        self.plan = plan
        self.selectedPlan = selectedPlan
        self.rejectedPlan = rejectedPlan
        self.selectedPlanRole = selectedPlanRole
        self.aiPlannerPlan = aiPlannerPlan
        self.acceptanceDecision = acceptanceDecision
        self.qualityComparisons = qualityComparisons
        self.plannerDiagnostics = plannerDiagnostics
        self.failures = failures
        self.warnings = warnings
    }
}

public struct NativePlannerQualityComparison: Sendable {
    public var role: String
    public var candidateId: String?
    public var source: MixCandidateSource?
    public var isSelected: Bool
    public var style: MixStyle
    public var transitionStartSec: Double
    public var transitionEndSec: Double
    public var nextTrackStartOffsetSec: Double
    public var renderedQuality: RenderedTransitionQualityReport

    public init(
        role: String,
        candidateId: String?,
        source: MixCandidateSource?,
        isSelected: Bool,
        style: MixStyle,
        transitionStartSec: Double,
        transitionEndSec: Double,
        nextTrackStartOffsetSec: Double,
        renderedQuality: RenderedTransitionQualityReport
    ) {
        self.role = role
        self.candidateId = candidateId
        self.source = source
        self.isSelected = isSelected
        self.style = style
        self.transitionStartSec = transitionStartSec
        self.transitionEndSec = transitionEndSec
        self.nextTrackStartOffsetSec = nextTrackStartOffsetSec
        self.renderedQuality = renderedQuality
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
        let aiPlannerPlan = benchmark.aiPlannerPlan
            .flatMap { MixPlanValidator.validateAndClamp($0, context: benchmark.validationContext).plan }
        let qualityComparisons = buildQualityComparisons(
            localFallbackPlan: plan,
            aiPlannerPlan: aiPlannerPlan,
            benchmark: benchmark,
            selectedRole: nil
        )
        let acceptanceDecision = buildAcceptanceDecision(
            localFallbackPlan: plan,
            aiPlannerPlan: aiPlannerPlan,
            qualityComparisons: qualityComparisons,
            benchmark: benchmark
        )
        let selectedRole = acceptanceDecision?.selectedRole ?? .localFallback
        let selectedPlan = selectedRole == .aiPlanner ? aiPlannerPlan : plan
        let rejectedPlan = selectedRole == .aiPlanner ? plan : aiPlannerPlan
        let selectedQualityComparisons = buildQualityComparisons(
            localFallbackPlan: plan,
            aiPlannerPlan: aiPlannerPlan,
            benchmark: benchmark,
            selectedRole: selectedRole
        )
        let plannerDiagnostics = acceptanceDecision.map { [$0.diagnostics] } ?? []

        let grade: NativePlannerBenchmarkGrade = failures.isEmpty
            ? (warnings.isEmpty ? .pass : .warn)
            : .fail
        return NativePlannerBenchmarkResult(
            name: benchmark.name,
            grade: grade,
            plan: plan,
            selectedPlan: selectedPlan,
            rejectedPlan: rejectedPlan,
            selectedPlanRole: selectedRole,
            aiPlannerPlan: aiPlannerPlan,
            acceptanceDecision: acceptanceDecision,
            qualityComparisons: selectedQualityComparisons,
            plannerDiagnostics: plannerDiagnostics,
            failures: failures,
            warnings: warnings
        )
    }

    private static func buildAcceptanceDecision(
        localFallbackPlan: MixPlan,
        aiPlannerPlan: MixPlan?,
        qualityComparisons: [NativePlannerQualityComparison],
        benchmark: NativePlannerBenchmarkCase
    ) -> MixPlanAcceptanceDecision? {
        guard let aiPlannerPlan,
              let aiQuality = qualityComparisons.first(where: { $0.role == "ai_planner" })?.renderedQuality,
              let fallbackQuality = qualityComparisons.first(where: { $0.role == "local_fallback" })?.renderedQuality
        else {
            return nil
        }

        return MixPlanAcceptanceGate.decide(
            currentTrackId: benchmark.request.currentTrack.id,
            nextTrackId: benchmark.request.nextTrack.id,
            aiPlan: diagnosticPlan(source: "ai_planner", plan: aiPlannerPlan, quality: aiQuality),
            fallbackPlan: diagnosticPlan(source: "local_fallback", plan: localFallbackPlan, quality: fallbackQuality)
        )
    }

    private static func diagnosticPlan(
        source: String,
        plan: MixPlan,
        quality: RenderedTransitionQualityReport
    ) -> MixReviewExportPlan {
        MixReviewExportPlan(
            source: source,
            reason: plan.reasoningSummary,
            transitionStartSec: plan.transitionStartSec,
            transitionEndSec: plan.transitionEndSec,
            nextTrackStartOffsetSec: plan.nextTrackStartOffsetSec,
            style: plan.style,
            confidence: plan.confidence,
            candidateId: plan.candidateId,
            renderedQuality: quality
        )
    }

    private static func buildQualityComparisons(
        localFallbackPlan: MixPlan,
        aiPlannerPlan: MixPlan?,
        benchmark: NativePlannerBenchmarkCase,
        selectedRole: MixPlanAcceptanceSelectedRole?
    ) -> [NativePlannerQualityComparison] {
        let currentTrack = Track(
            id: benchmark.request.currentTrack.id,
            title: benchmark.request.currentTrack.title,
            durationSec: benchmark.request.currentTrack.durationSec,
            format: .wav,
            bpm: benchmark.request.currentTrack.bpm
        )
        let nextTrack = Track(
            id: benchmark.request.nextTrack.id,
            title: benchmark.request.nextTrack.title,
            durationSec: benchmark.request.nextTrack.durationSec,
            format: .wav,
            bpm: benchmark.request.nextTrack.bpm
        )
        let candidatesById = (benchmark.request.pairContext?.candidates ?? [])
            .reduce(into: [String: MixCandidate]()) { values, candidate in
                values[candidate.id] = values[candidate.id] ?? candidate
            }
        let selectedSource = localFallbackPlan.candidateId.flatMap { candidatesById[$0]?.source }
        var comparisons: [NativePlannerQualityComparison] = []
        if let aiPlannerPlan {
            comparisons.append(qualityComparison(
                role: "ai_planner",
                plan: aiPlannerPlan,
                source: aiPlannerPlan.candidateId.flatMap { candidatesById[$0]?.source },
                isSelected: selectedRole == .aiPlanner,
                currentTrack: currentTrack,
                nextTrack: nextTrack,
                currentAnalysis: benchmark.request.analysis.current,
                nextAnalysis: benchmark.request.analysis.next
            ))
        }
        comparisons.append(qualityComparison(
            role: "local_fallback",
            plan: localFallbackPlan,
            source: selectedSource,
            isSelected: selectedRole == nil || selectedRole == .localFallback,
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: benchmark.request.analysis.current,
            nextAnalysis: benchmark.request.analysis.next
        ))

        for candidate in benchmark.request.pairContext?.candidates ?? [] where candidate.id != localFallbackPlan.candidateId {
            guard let plan = benchmarkPlan(for: candidate, benchmark: benchmark) else {
                continue
            }
            comparisons.append(qualityComparison(
                role: "candidate_alternative",
                plan: plan,
                source: candidate.source,
                isSelected: false,
                currentTrack: currentTrack,
                nextTrack: nextTrack,
                currentAnalysis: benchmark.request.analysis.current,
                nextAnalysis: benchmark.request.analysis.next
            ))
        }

        return comparisons.sorted {
            if roleRank($0.role) != roleRank($1.role) {
                return roleRank($0.role) < roleRank($1.role)
            }
            return $0.renderedQuality.score > $1.renderedQuality.score
        }
    }

    private static func roleRank(_ role: String) -> Int {
        switch role {
        case "ai_planner":
            return 0
        case "local_fallback":
            return 1
        default:
            return 2
        }
    }

    private static func qualityComparison(
        role: String,
        plan: MixPlan,
        source: MixCandidateSource?,
        isSelected: Bool,
        currentTrack: Track,
        nextTrack: Track,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?
    ) -> NativePlannerQualityComparison {
        let report = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan,
            currentTrack: currentTrack,
            nextTrack: nextTrack,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis
        )
        return NativePlannerQualityComparison(
            role: role,
            candidateId: plan.candidateId,
            source: source,
            isSelected: isSelected,
            style: plan.style,
            transitionStartSec: plan.transitionStartSec,
            transitionEndSec: plan.transitionEndSec,
            nextTrackStartOffsetSec: plan.nextTrackStartOffsetSec,
            renderedQuality: report
        )
    }

    private static func benchmarkPlan(
        for candidate: MixCandidate,
        benchmark: NativePlannerBenchmarkCase
    ) -> MixPlan? {
        let transitionDurationSec = benchmarkTransitionDuration(
            candidate: candidate,
            mode: benchmark.request.settings.aiDjMode,
            maxFadeDurationSec: max(0.25, benchmark.request.settings.fadeDurationSec)
        )
        let transitionEndSec = benchmarkMixOutTime(
            candidate: candidate,
            request: benchmark.request,
            transitionDurationSec: transitionDurationSec
        )
        let transitionStartSec = max(
            benchmark.request.currentPlayback.elapsedSec,
            transitionEndSec - transitionDurationSec
        )
        let plan = MixPlan(
            transitionStartSec: transitionStartSec,
            transitionEndSec: transitionEndSec,
            nextTrackStartOffsetSec: candidate.nextMixInSec,
            style: candidate.style,
            confidence: candidate.confidence,
            reasoningSummary: "Benchmark candidate comparison: \(candidate.reason)",
            tempoSync: MixTempoSyncPlan(
                enabled: candidate.tempoSyncRate != nil && (candidate.bpmDelta ?? 0) <= 10,
                targetRate: candidate.tempoSyncRate
            ),
            candidateId: candidate.id,
            currentBarIndex: candidate.currentBarIndex,
            nextBarIndex: candidate.nextBarIndex,
            phraseAlignment: candidate.phraseAlignment,
            energyStrategy: energyStrategy(for: candidate.energyDelta),
            evidence: ["benchmark quality comparison", "source \(candidate.source.rawValue)", candidate.reason],
            mixControls: .conservativeDefaults
        )
        return MixPlanValidator.validateAndClamp(plan, context: benchmark.validationContext).plan
    }

    private static func benchmarkTransitionDuration(
        candidate: MixCandidate,
        mode: AIDJMode,
        maxFadeDurationSec: Double
    ) -> Double {
        switch candidate.style {
        case .hardCut:
            switch mode {
            case .safe:
                return min(maxFadeDurationSec, 3)
            case .balanced:
                return min(maxFadeDurationSec, 2)
            case .adventurous:
                return min(maxFadeDurationSec, 1.25)
            }
        case .energySwap:
            return min(maxFadeDurationSec, max(2.5, maxFadeDurationSec * 0.65))
        case .smoothBlend:
            return maxFadeDurationSec
        }
    }

    private static func benchmarkMixOutTime(
        candidate: MixCandidate,
        request: PlannerRequest,
        transitionDurationSec: Double
    ) -> Double {
        if candidate.currentMixOutSec > request.currentPlayback.elapsedSec + 0.25 {
            return min(candidate.currentMixOutSec, request.currentTrack.durationSec)
        }
        return min(
            request.currentTrack.durationSec,
            max(
                request.currentPlayback.elapsedSec + min(transitionDurationSec, 2),
                request.currentTrack.durationSec - transitionDurationSec * 0.5
            )
        )
    }

    private static func energyStrategy(for energyDelta: Double?) -> EnergyStrategy {
        guard let energyDelta else {
            return .maintain
        }
        if energyDelta > 0.08 {
            return .lift
        }
        if energyDelta < -0.08 {
            return .drop
        }
        return .maintain
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
        let candidateMixOutTimes = candidates.map(\.currentMixOutSec)
        let candidateMixInTimes = candidates.map(\.nextMixInSec)
        let currentAnalysis = benchmarkAnalysis(
            track: current,
            cueTimes: [elapsedSec] + candidateMixOutTimes,
            introCueSec: nil,
            outroCueSec: candidateMixOutTimes.min(),
            peak: mode == .adventurous ? 0.58 : 0.5,
            rms: mode == .adventurous ? 0.32 : 0.26,
            spectral: mode == .adventurous ? (0.7, 0.62, 0.44) : (0.44, 0.38, 0.28)
        )
        let nextAnalysis = benchmarkAnalysis(
            track: next,
            cueTimes: candidateMixInTimes + candidateMixInTimes.map { $0 + fadeDurationSec },
            introCueSec: candidateMixInTimes.min(),
            outroCueSec: nil,
            peak: mode == .adventurous ? 0.56 : 0.46,
            rms: mode == .adventurous ? 0.31 : 0.24,
            spectral: mode == .adventurous ? (0.68, 0.6, 0.42) : (0.28, 0.34, 0.26)
        )
        let request = PlannerRequest(
            currentTrack: PlannerTrackSnapshot(track: current),
            nextTrack: PlannerTrackSnapshot(track: next),
            currentPlayback: PlannerPlaybackSnapshot(
                elapsedSec: elapsedSec,
                remainingSec: max(0, current.durationSec - elapsedSec)
            ),
            analysis: PlannerAnalysisPair(current: currentAnalysis, next: nextAnalysis),
            analysisSummary: PlannerEvidenceBuilder.buildPlannerAnalysisSummary(
                currentTrack: current,
                nextTrack: next,
                currentAnalysis: currentAnalysis,
                nextAnalysis: nextAnalysis
            ),
            pairContext: MixPairContext(
                currentTrackId: current.id,
                nextTrackId: next.id,
                candidates: candidates,
                recommendedCandidateId: recommendedCandidateId,
                readiness: readiness
            ),
            settings: PlannerSettingsSnapshot(fadeDurationSec: fadeDurationSec, aiDjMode: mode)
        )
        let validationContext = MixPlanValidationContext(
            currentPlaybackElapsedSec: elapsedSec,
            currentTrackDurationSec: current.durationSec,
            nextTrackDurationSec: next.durationSec,
            maxFadeDurationSec: fadeDurationSec
        )
        return NativePlannerBenchmarkCase(
            name: name,
            request: request,
            validationContext: validationContext,
            expectation: expectation,
            aiPlannerPlan: benchmarkAIPlannerPlan(
                request: request,
                validationContext: validationContext
            )
        )
    }

    private static func benchmarkAIPlannerPlan(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext
    ) -> MixPlan? {
        let candidates = request.pairContext?.candidates ?? []
        if let candidate = candidates.first(where: { $0.source != .tailFallback }) ?? candidates.first,
           var plan = benchmarkPlan(
            for: candidate,
            benchmark: NativePlannerBenchmarkCase(
                name: "ai-fixture",
                request: request,
                validationContext: validationContext,
                expectation: NativePlannerBenchmarkExpectation(allowedStyles: [.smoothBlend, .energySwap, .hardCut], minConfidence: 0)
            )
           ) {
            plan.reasoningSummary = "AI fixture: \(candidate.reason)"
            plan.evidence = ["ai planner fixture", "source \(candidate.source.rawValue)", candidate.reason]
            return MixPlanValidator.validateAndClamp(plan, context: validationContext).plan
        }

        guard var plan = NativeFallbackMixPlanner.buildPlan(
            request: request,
            validationContext: validationContext,
            failureReason: "ai_fixture_no_candidates"
        ) else {
            return nil
        }
        plan.reasoningSummary = "AI fixture: emergency tail mix"
        plan.evidence = ["ai planner fixture", "emergency tail mix"]
        return MixPlanValidator.validateAndClamp(plan, context: validationContext).plan
    }

    private static func benchmarkAnalysis(
        track: Track,
        cueTimes: [Double],
        introCueSec: Double?,
        outroCueSec: Double?,
        peak: Double,
        rms: Double,
        spectral: (low: Double, mid: Double, high: Double)
    ) -> TrackAnalysis {
        let times = ([0, track.durationSec] + cueTimes)
            .map { min(max(0, $0), track.durationSec) }
            .reduce(into: [Double]()) { values, time in
                if !values.contains(where: { abs($0 - time) < 0.001 }) {
                    values.append(time)
                }
            }
            .sorted()
        return TrackAnalysis(
            trackId: track.id,
            generatedAt: "2026-06-16T00:00:00Z",
            source: .derived,
            bpm: track.bpm,
            bpmConfidence: track.bpm == nil ? 0 : 0.86,
            beatGridSec: stride(from: 0, through: min(track.durationSec, 16), by: 0.5).map { $0 },
            downbeatsSec: [0],
            barGrid: [BarMarker(index: 0, startSec: 0, beatIndex: 0)],
            phraseMarkers: [PhraseMarker(index: 0, startSec: 0, bars: 8, confidence: 0.8)],
            introCueSec: introCueSec,
            outroCueSec: outroCueSec,
            energyProfile: [rms, min(1, rms + 0.08), max(0, rms - 0.04)],
            waveformPeaks: times.map { WaveformPeak(timeSec: $0, peak: peak, rms: rms) },
            waveformDetail: times.map { WaveformDetailPoint(timeSec: $0, peak: peak, rms: rms, min: -peak, max: peak) },
            spectralBands: times.map { SpectralBandPoint(timeSec: $0, low: spectral.low, mid: spectral.mid, high: spectral.high) },
            transientMarkers: times.enumerated().map {
                TransientMarker(index: $0.offset, timeSec: $0.element, strength: 0.7)
            },
            cueCandidates: [],
            analysisConfidence: 0.82,
            analysisQuality: AnalysisQuality(
                waveformDetail: 0.82,
                spectralBands: 0.82,
                transientMarkers: 0.76,
                beatGrid: 0.82
            ),
            analysisWarnings: []
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
