import Foundation
import BeatDropperDomain

public enum TransitionPlanningIntent: Hashable, Sendable {
    case scheduled
    case manualNext
}

public enum BeatAlignedTransitionPolicy {
    public static let maximumBeatAlignedDurationSec = 32.0

    public static func durationSec(barCount: Int, synchronizedBPM: Double) -> Double? {
        guard barCount >= 0,
              synchronizedBPM.isFinite,
              synchronizedBPM >= 40,
              synchronizedBPM <= 240
        else {
            return nil
        }
        return Double(barCount) * 4 * 60 / synchronizedBPM
    }

    public static func apply(
        to proposedPlan: MixPlan,
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        intent: TransitionPlanningIntent = .scheduled
    ) -> MixPlan? {
        guard let currentGrid = reliableGrid(
            analysis: request.analysis.current,
            fallbackBPM: request.currentTrack.bpm
        ), let nextGrid = reliableGrid(
            analysis: request.analysis.next,
            fallbackBPM: request.nextTrack.bpm
        ) else {
            return secondsFallback(
                proposedPlan: proposedPlan,
                request: request,
                validationContext: validationContext,
                intent: intent
            )
        }

        let tempoRate = nextGrid.barDurationSec / currentGrid.barDurationSec
        let tempoSyncSuitable = tempoRate >= 0.85 && tempoRate <= 1.15
        let relativeTempoDifference = abs(currentGrid.gridBPM - nextGrid.gridBPM) / currentGrid.gridBPM
        let effectiveStyle: MixStyle
        if tempoSyncSuitable {
            effectiveStyle = proposedPlan.style
        } else if relativeTempoDifference <= 0.30 {
            effectiveStyle = .energySwap
        } else {
            effectiveStyle = .hardCut
        }

        let preferredBars = preferredBarCounts(
            style: effectiveStyle,
            mode: request.settings.aiDjMode,
            currentGrid: currentGrid,
            nextGrid: nextGrid,
            proposedPlan: proposedPlan
        )

        for barCount in preferredBars where barCount > 0 {
            guard let window = alignedWindow(
                barCount: barCount,
                proposedPlan: proposedPlan,
                request: request,
                currentGrid: currentGrid,
                nextGrid: nextGrid,
                intent: intent
            ) else {
                continue
            }

            let selectedStyle = style(for: barCount, preferredStyle: effectiveStyle)
            let synchronizedBPM = 240 * Double(barCount) / window.durationSec
            var plan = proposedPlan
            plan.transitionStartSec = window.start.startSec
            plan.transitionEndSec = window.end.startSec
            plan.nextTrackStartOffsetSec = window.incoming.startSec
            plan.style = selectedStyle
            plan.currentBarIndex = window.start.index
            plan.nextBarIndex = window.incoming.index
            plan.phraseAlignment = phraseAlignment(
                currentBarIndex: window.start.index,
                nextBarIndex: window.incoming.index
            )
            plan.tempoSync = MixTempoSyncPlan(
                enabled: tempoSyncSuitable && selectedStyle != .hardCut,
                targetRate: tempoSyncSuitable && selectedStyle != .hardCut ? tempoRate : nil
            )
            plan.transitionBarCount = barCount
            plan.transitionTimingSource = .beatGrid
            plan.synchronizedBPM = synchronizedBPM
            plan.reasoningSummary = policyReason(
                original: proposedPlan.reasoningSummary,
                barCount: barCount,
                style: selectedStyle,
                tempoSyncSuitable: tempoSyncSuitable
            )
            plan.evidence = policyEvidence(
                original: proposedPlan.evidence,
                barCount: barCount,
                durationSec: window.durationSec,
                synchronizedBPM: synchronizedBPM,
                tempoRate: tempoRate,
                tempoSyncSuitable: tempoSyncSuitable,
                intent: intent
            )

            let beatContext = MixPlanValidationContext(
                currentPlaybackElapsedSec: validationContext.currentPlaybackElapsedSec,
                currentTrackDurationSec: validationContext.currentTrackDurationSec,
                nextTrackDurationSec: validationContext.nextTrackDurationSec,
                maxFadeDurationSec: max(validationContext.maxFadeDurationSec, window.durationSec + 0.01)
            )
            if let validated = MixPlanValidator.validateAndClamp(plan, context: beatContext).plan {
                return validated
            }
        }

        return zeroBarCut(
            proposedPlan: proposedPlan,
            request: request,
            validationContext: validationContext,
            currentGrid: currentGrid,
            nextGrid: nextGrid,
            intent: intent
        )
    }

    private struct ReliableGrid {
        var markers: [BarMarker]
        var barDurationSec: Double
        var gridBPM: Double
        var quality: Double
    }

    private struct AlignedWindow {
        var start: BarMarker
        var end: BarMarker
        var incoming: BarMarker

        var durationSec: Double {
            end.startSec - start.startSec
        }
    }

    private static func reliableGrid(analysis: TrackAnalysis?, fallbackBPM: Double?) -> ReliableGrid? {
        guard let analysis,
              analysis.analysisQuality.beatGrid >= 0.45,
              analysis.analysisConfidence >= 0.45,
              analysis.bpmConfidence >= 0.55
        else {
            return nil
        }
        let markers = analysis.barGrid
            .filter { $0.startSec.isFinite && $0.startSec >= 0 }
            .sorted { $0.startSec < $1.startSec }
        guard markers.count >= 4 else {
            return nil
        }
        let intervals = zip(markers, markers.dropFirst())
            .map { $1.startSec - $0.startSec }
            .filter { $0.isFinite && $0 >= 1 && $0 <= 6 }
        guard intervals.count >= 3, let barDurationSec = median(intervals) else {
            return nil
        }
        let deviations = intervals.map { abs($0 - barDurationSec) / barDurationSec }
        guard (median(deviations) ?? 1) <= 0.08 else {
            return nil
        }
        let bpm = analysis.bpm ?? fallbackBPM
        guard let bpm, bpm.isFinite, bpm >= 40, bpm <= 240 else {
            return nil
        }
        let gridBPM = 240 / barDurationSec
        guard abs(gridBPM - bpm) / bpm <= 0.12 else {
            return nil
        }
        return ReliableGrid(
            markers: markers,
            barDurationSec: barDurationSec,
            gridBPM: gridBPM,
            quality: min(analysis.analysisQuality.beatGrid, analysis.bpmConfidence)
        )
    }

    private static func preferredBarCounts(
        style: MixStyle,
        mode: AIDJMode,
        currentGrid: ReliableGrid,
        nextGrid: ReliableGrid,
        proposedPlan: MixPlan
    ) -> [Int] {
        switch style {
        case .hardCut:
            return [1]
        case .energySwap:
            return [4, 1]
        case .smoothBlend:
            let safeExtended = mode == .safe &&
                proposedPlan.phraseAlignment == .aligned &&
                min(currentGrid.quality, nextGrid.quality) >= 0.75 &&
                (durationSec(barCount: 16, synchronizedBPM: currentGrid.gridBPM) ?? .infinity) <= maximumBeatAlignedDurationSec
            return safeExtended ? [16, 8, 4, 1] : [8, 4, 1]
        }
    }

    private static func alignedWindow(
        barCount: Int,
        proposedPlan: MixPlan,
        request: PlannerRequest,
        currentGrid: ReliableGrid,
        nextGrid: ReliableGrid,
        intent: TransitionPlanningIntent
    ) -> AlignedWindow? {
        guard barCount > 0,
              currentGrid.markers.count > barCount,
              nextGrid.markers.count > barCount
        else {
            return nil
        }
        let elapsed = request.currentPlayback.elapsedSec
        let targetEnd = max(elapsed, proposedPlan.transitionEndSec)
        let phraseCycle = barCount >= 8 ? 8 : max(1, barCount)
        var candidates: [(start: BarMarker, end: BarMarker, score: Double)] = []
        for endPosition in barCount..<currentGrid.markers.count {
            let start = currentGrid.markers[endPosition - barCount]
            let end = currentGrid.markers[endPosition]
            let duration = end.startSec - start.startSec
            guard start.startSec >= elapsed - 0.02,
                  end.startSec <= request.currentTrack.durationSec + 0.02,
                  duration > 0.05,
                  duration <= maximumBeatAlignedDurationSec,
                  positiveModulo(start.index, phraseCycle) == 0
            else {
                continue
            }
            let targetScore: Double = switch intent {
            case .scheduled:
                abs(end.startSec - targetEnd)
            case .manualNext:
                max(0, start.startSec - elapsed)
            }
            candidates.append((start, end, targetScore))
        }
        guard !candidates.isEmpty else {
            return nil
        }
        let selected = candidates.min { $0.score < $1.score }!
        let requiredPhase = positiveModulo(selected.start.index, 8)
        let requestedOffset = max(0, proposedPlan.nextTrackStartOffsetSec)
        let maximumIncomingPosition = nextGrid.markers.count - barCount - 1
        guard maximumIncomingPosition >= 0 else {
            return nil
        }
        let incomingCandidates = nextGrid.markers[0...maximumIncomingPosition]
        let phaseMatches = incomingCandidates.filter { positiveModulo($0.index, 8) == requiredPhase }
        let pool = phaseMatches.isEmpty ? Array(incomingCandidates) : phaseMatches
        guard let incoming = pool.min(by: {
            abs($0.startSec - requestedOffset) < abs($1.startSec - requestedOffset)
        }) else {
            return nil
        }
        return AlignedWindow(start: selected.start, end: selected.end, incoming: incoming)
    }

    private static func zeroBarCut(
        proposedPlan: MixPlan,
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        currentGrid: ReliableGrid,
        nextGrid: ReliableGrid,
        intent: TransitionPlanningIntent
    ) -> MixPlan? {
        let elapsed = request.currentPlayback.elapsedSec
        let target = intent == .manualNext ? elapsed : max(elapsed, proposedPlan.transitionEndSec)
        guard let outgoing = currentGrid.markers.min(by: {
            abs($0.startSec - target) < abs($1.startSec - target)
        }), let incoming = nextGrid.markers.min(by: {
            abs($0.startSec - proposedPlan.nextTrackStartOffsetSec) < abs($1.startSec - proposedPlan.nextTrackStartOffsetSec)
        }) else {
            return nil
        }
        var plan = proposedPlan
        plan.transitionEndSec = max(elapsed + 0.08, outgoing.startSec)
        plan.transitionStartSec = max(elapsed, plan.transitionEndSec - 0.08)
        plan.nextTrackStartOffsetSec = incoming.startSec
        plan.style = .hardCut
        plan.tempoSync = MixTempoSyncPlan(enabled: false, targetRate: nil)
        plan.currentBarIndex = outgoing.index
        plan.nextBarIndex = incoming.index
        plan.phraseAlignment = phraseAlignment(currentBarIndex: outgoing.index, nextBarIndex: incoming.index)
        plan.transitionBarCount = 0
        plan.transitionTimingSource = .beatGrid
        plan.synchronizedBPM = currentGrid.gridBPM
        plan.evidence = Array((["beat-grid policy: 0-bar hard cut", "insufficient aligned runway"] + proposedPlan.evidence).prefix(8))
        return MixPlanValidator.validateAndClamp(plan, context: validationContext).plan
    }

    private static func secondsFallback(
        proposedPlan: MixPlan,
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        intent: TransitionPlanningIntent
    ) -> MixPlan? {
        let elapsed = request.currentPlayback.elapsedSec
        let duration = max(0.25, request.settings.fadeDurationSec)
        let requestedEnd = intent == .manualNext
            ? elapsed + duration
            : max(elapsed + min(duration, 2), proposedPlan.transitionEndSec)
        let end = min(request.currentTrack.durationSec, requestedEnd)
        var plan = proposedPlan
        plan.transitionEndSec = end
        plan.transitionStartSec = max(elapsed, end - duration)
        plan.tempoSync = MixTempoSyncPlan(enabled: false, targetRate: nil)
        plan.transitionBarCount = nil
        plan.transitionTimingSource = .secondsFallback
        plan.synchronizedBPM = nil
        plan.evidence = Array((["seconds fallback: beat/BPM confidence insufficient"] + proposedPlan.evidence).prefix(8))
        return MixPlanValidator.validateAndClamp(plan, context: validationContext).plan
    }

    private static func style(for barCount: Int, preferredStyle: MixStyle) -> MixStyle {
        if barCount <= 1 {
            return .hardCut
        }
        if barCount <= 4 {
            return .energySwap
        }
        return preferredStyle == .smoothBlend ? .smoothBlend : preferredStyle
    }

    private static func phraseAlignment(currentBarIndex: Int, nextBarIndex: Int) -> PhraseAlignment {
        let currentPhase = positiveModulo(currentBarIndex, 8)
        let nextPhase = positiveModulo(nextBarIndex, 8)
        if currentPhase == nextPhase {
            return .aligned
        }
        let distance = min(abs(currentPhase - nextPhase), 8 - abs(currentPhase - nextPhase))
        return distance <= 1 ? .near : .free
    }

    private static func policyReason(
        original: String?,
        barCount: Int,
        style: MixStyle,
        tempoSyncSuitable: Bool
    ) -> String {
        let barLabel = barCount == 1 ? "1 bar" : "\(barCount) bars"
        let policy = "Beat-grid policy selected \(barLabel) (\(style.rawValue)); tempo sync \(tempoSyncSuitable ? "enabled" : "not suitable")"
        guard let original, !original.isEmpty else {
            return policy
        }
        return "\(policy). \(original)"
    }

    private static func policyEvidence(
        original: [String],
        barCount: Int,
        durationSec: Double,
        synchronizedBPM: Double,
        tempoRate: Double,
        tempoSyncSuitable: Bool,
        intent: TransitionPlanningIntent
    ) -> [String] {
        let intentText = intent == .manualNext ? "manual Next" : "scheduled"
        let policy = [
            "beat-grid policy: \(barCount) \(barCount == 1 ? "bar" : "bars") / \(String(format: "%.2f", durationSec))s @ synchronized BPM \(String(format: "%.2f", synchronizedBPM))",
            tempoSyncSuitable
                ? "tempo rate \(String(format: "%.4f", tempoRate)); \(intentText) phrase-aligned OUT/IN"
                : "tempo sync unsuitable; shortened transition; \(intentText) phrase-aligned OUT/IN"
        ]
        let priorityOriginal = original.filter {
            $0.localizedCaseInsensitiveContains("planner failure") ||
                $0.localizedCaseInsensitiveContains("BPM delta") ||
                $0.localizedCaseInsensitiveContains("phrase")
        }
        let remainingOriginal = original.filter { item in
            !priorityOriginal.contains(item)
        }
        return Array((policy + priorityOriginal + remainingOriginal).prefix(8))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let result = value % divisor
        return result >= 0 ? result : result + divisor
    }
}
