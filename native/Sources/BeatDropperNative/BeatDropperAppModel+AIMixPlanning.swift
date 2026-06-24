import BeatDropperCore
import Foundation

extension BeatDropperAppModel {
    func requestMixPlanForNextTrack() {
        guard let current = selectedTrack, let next = nextTrackAfterSelection else {
            plannerStatus = "Select a track with a next track first"
            notice = plannerStatus
            return
        }
        guard markTrackMissingIfUnavailable(current),
              markTrackMissingIfUnavailable(next)
        else {
            plannerStatus = "Cannot plan mix with missing files"
            notice = plannerStatus
            return
        }

        isPlanningMix = true
        let requestID = UUID()
        activePlannerRequestID = requestID
        plannerStatus = "Requesting AI mix plan..."
        notice = plannerStatus
        let currentElapsed = audioEngine.currentTrack?.id == current.id
            ? audioEngine.elapsedSec
            : 0
        let currentAnalysis = trackAnalysesById[current.id]
        let nextAnalysis = trackAnalysesById[next.id]
        let plannerSettings = PlannerSettingsSnapshot(
            fadeDurationSec: settings.fadeDurationSec,
            aiDjMode: settings.aiDjMode
        )
        let request = PlannerRequestBuilder.build(
            currentTrack: current.track,
            nextTrack: next.track,
            elapsedSec: currentElapsed,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis,
            currentPreparation: preparation(forTrackId: current.id),
            nextPreparation: preparation(forTrackId: next.id),
            settings: plannerSettings
        )
        let validationContext = MixPlanValidationContext(
            currentPlaybackElapsedSec: request.currentPlayback.elapsedSec,
            currentTrackDurationSec: current.track.durationSec,
            nextTrackDurationSec: next.track.durationSec,
            maxFadeDurationSec: self.settings.fadeDurationSec
        )
        var mixPlanner = self.mixPlanner
        mixPlanner.timeoutSec = max(1, self.settings.plannerTimeoutMs / 1_000)

        Task { [weak self] in
            let result = await mixPlanner.requestMixPlan(
                request: request,
                validationContext: validationContext
            )
            guard let self else {
                return
            }
            guard self.activePlannerRequestID == requestID else {
                return
            }

            self.isPlanningMix = false
            self.activePlannerRequestID = nil
            if let plan = result.plan {
                let pair = PlannedMixPair(currentTrackId: current.id, nextTrackId: next.id)
                let accepted = self.acceptedMixPlan(
                    plan: plan,
                    pair: pair,
                    result: result,
                    current: current,
                    next: next,
                    currentAnalysis: currentAnalysis,
                    nextAnalysis: nextAnalysis
                )
                self.currentMixPlan = accepted.plan
                self.currentMixPlanPair = pair
                self.currentMixPlanReview = accepted.review
                self.recordMixReviewEvent(plan: accepted.plan, review: accepted.review)
                self.updateScheduledMixStatus()
                self.startMixPlanSchedulerIfNeeded()
                let readyText = accepted.review.source == "local-fallback"
                    ? "Local fallback mix plan ready"
                    : "AI mix plan ready"
                self.notice = "\(readyText) · quality \(accepted.review.renderedQuality.grade.rawValue)"
            } else {
                self.currentMixPlan = nil
                self.currentMixPlanPair = nil
                self.currentMixPlanReview = nil
                self.plannerStatus = result.reason ?? "AI planner returned no plan"
                self.notice = self.plannerStatus
            }
        }
    }

    func setAIMixEnabled(_ enabled: Bool) {
        if enabled {
            enableAIMix()
        } else {
            disableAIMix(noticeText: "AI mix off")
        }
    }

    func enableAIMix() {
        selectFirstAvailableTrackIfNeeded()
        guard playlist.count >= 2, selectedTrack != nil, nextTrackAfterSelection != nil else {
            isAIMixEnabled = false
            plannerStatus = "AI mix needs at least two available tracks"
            notice = plannerStatus
            return
        }

        isAIMixEnabled = true
        plannerStatus = "AI mix active: analyzing playlist"
        notice = plannerStatus
        refreshAnalyses(for: playlist)
        requestAIMixPlanIfReady()
    }

    func disableAIMix(noticeText: String) {
        isAIMixEnabled = false
        stopMixPlanScheduler()
        clearCurrentMixPlan()
        isPlanningMix = false
        activePlannerRequestID = nil
        plannerStatus = "No AI mix plan"
        notice = noticeText
    }

    func cancelMixPlan() {
        disableAIMix(noticeText: "Canceled AI mix")
    }

    func requestAIMixPlanIfReady() {
        guard isAIMixEnabled else {
            return
        }
        guard !isPlanningMix else {
            return
        }
        guard let current = selectedTrack,
              let next = nextTrackAfterSelection,
              isTrackAvailableForImmediateUse(current),
              isTrackAvailableForImmediateUse(next)
        else {
            plannerStatus = "AI mix active: waiting for an available next track"
            return
        }

        if currentMixPlanPair == PlannedMixPair(currentTrackId: current.id, nextTrackId: next.id),
           currentMixPlan != nil {
            startMixPlanSchedulerIfNeeded()
            return
        }

        let currentPairNeedsAnalysis = trackAnalysesById[current.id] == nil ||
            trackAnalysesById[next.id] == nil
        if currentPairNeedsAnalysis, queuedAnalysisTrackCount + runningAnalysisTrackCount > 0 {
            plannerStatus = "AI mix active: analyzing playlist"
            return
        }

        requestMixPlanForNextTrack()
    }

    func syncAIMixAfterPlaylistMutation() {
        guard isAIMixEnabled else {
            return
        }
        selectFirstAvailableTrackIfNeeded()
        guard playlist.count >= 2, selectedTrack != nil, nextTrackAfterSelection != nil else {
            disableAIMix(noticeText: "AI mix off: need two available tracks")
            return
        }

        refreshAnalyses(for: playlist)
        requestAIMixPlanIfReady()
    }

    func startMixPlanSchedulerIfNeeded() {
        stopMixPlanScheduler()
        guard
            currentMixPlan != nil,
            let pair = currentMixPlanPair,
            audioEngine.isPlaybackActive,
            audioEngine.currentTrack?.id == pair.currentTrackId
        else {
            updateScheduledMixStatus()
            return
        }

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickMixPlanScheduler()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mixPlanTimer = timer
        tickMixPlanScheduler()
    }

    func stopMixPlanScheduler() {
        mixPlanTimer?.invalidate()
        mixPlanTimer = nil
        scheduledMixCountdownSec = nil
    }

    func tickMixPlanScheduler() {
        guard
            !isExecutingScheduledMix,
            let plan = currentMixPlan,
            let pair = currentMixPlanPair,
            audioEngine.isPlaybackActive,
            audioEngine.currentTrack?.id == pair.currentTrackId,
            let current = playlist.first(where: { $0.id == pair.currentTrackId }),
            let target = playlist.first(where: { $0.id == pair.nextTrackId })
        else {
            updateScheduledMixStatus()
            return
        }

        guard isTrackAvailableForImmediateUse(target) else {
            stopMixPlanScheduler()
            clearCurrentMixPlan()
            notice = "Scheduled mix canceled because a file is missing"
            return
        }

        let secondsUntilTransition = MixPlanScheduler.secondsUntilTransition(
            plan: plan,
            elapsedSec: audioEngine.elapsedSec
        )
        if !MixPlanScheduler.shouldStartTransition(plan: plan, elapsedSec: audioEngine.elapsedSec) {
            scheduledMixCountdownSec = secondsUntilTransition
            updateScheduledMixStatus()
            return
        }

        do {
            isExecutingScheduledMix = true
            stopMixPlanScheduler()
            try executeTransition(
                from: current,
                to: target,
                plan: plan,
                clearPlanAfterStart: true
            )
            notice = "Executing scheduled AI mix"
            isExecutingScheduledMix = false
            requestAIMixPlanIfReady()
        } catch {
            isExecutingScheduledMix = false
            stopMixPlanScheduler()
            notice = error.localizedDescription
        }
    }

    func updateScheduledMixStatus() {
        guard let plan = currentMixPlan else {
            scheduledMixCountdownSec = nil
            if !isPlanningMix {
                plannerStatus = "No AI mix plan"
            }
            return
        }

        if audioEngine.isPlaybackActive, audioEngine.currentTrack?.id == currentMixPlanPair?.currentTrackId {
            let countdown = MixPlanScheduler.secondsUntilTransition(plan: plan, elapsedSec: audioEngine.elapsedSec)
            scheduledMixCountdownSec = countdown
            plannerStatus = "Scheduled in \(formatMixTime(countdown)) · next in \(formatMixTime(plan.nextTrackStartOffsetSec))"
        } else {
            scheduledMixCountdownSec = nil
            plannerStatus = "AI plan \(formatMixTime(plan.transitionStartSec)) -> \(formatMixTime(plan.nextTrackStartOffsetSec))"
        }
    }

    func clearCurrentMixPlan() {
        stopMixPlanScheduler()
        currentMixPlan = nil
        currentMixPlanPair = nil
        currentMixPlanReview = nil
        scheduledMixCountdownSec = nil
        if !isPlanningMix {
            plannerStatus = isAIMixEnabled ? "AI mix active" : "No AI mix plan"
        }
    }

    func acceptedMixPlan(
        plan: MixPlan,
        pair: PlannedMixPair,
        result: NativeMixPlannerResult,
        current: ImportedTrack,
        next: ImportedTrack,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?
    ) -> AcceptedMixPlan {
        let aiReport = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan,
            currentTrack: current.track,
            nextTrack: next.track,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis
        )
        let aiComparison = buildPlanComparison(
            plan: plan,
            source: result.source,
            reason: result.reason,
            renderedQuality: aiReport
        )
        guard result.source == "cli",
              let fallbackPlan = result.shadowFallbackPlan
        else {
            return AcceptedMixPlan(
                plan: plan,
                review: PlannedMixReview(
                    pair: pair,
                    source: result.source,
                    fallbackReason: result.source == "local-fallback" ? result.reason : nil,
                    selectionReason: nil,
                    renderedQuality: aiReport,
                    shadowFallbackComparison: nil
                )
            )
        }

        let fallbackComparison = buildPlanComparison(
            plan: fallbackPlan,
            source: "local-fallback",
            reason: result.shadowFallbackReason,
            current: current,
            next: next,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis
        )
        let decision = MixPlanAcceptanceGate.decide(
            currentTrackId: pair.currentTrackId,
            nextTrackId: pair.nextTrackId,
            aiPlan: exportPlan(from: aiComparison),
            fallbackPlan: exportPlan(from: fallbackComparison)
        )

        switch decision.selectedRole {
        case .aiPlanner:
            return AcceptedMixPlan(
                plan: plan,
                review: PlannedMixReview(
                    pair: pair,
                    source: result.source,
                    fallbackReason: nil,
                    selectionReason: decision.reason.rawValue,
                    renderedQuality: aiReport,
                    shadowFallbackComparison: fallbackComparison
                )
            )
        case .localFallback:
            return AcceptedMixPlan(
                plan: fallbackPlan,
                review: PlannedMixReview(
                    pair: pair,
                    source: "local-fallback",
                    fallbackReason: decision.reason.rawValue,
                    selectionReason: decision.reason.rawValue,
                    renderedQuality: fallbackComparison.renderedQuality,
                    shadowFallbackComparison: aiComparison
                )
            )
        }
    }

    func buildPlanComparison(
        plan: MixPlan,
        source: String,
        reason: String?,
        current: ImportedTrack,
        next: ImportedTrack,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?
    ) -> PlannedMixReviewPlanComparison {
        let report = RenderedTransitionQualityAnalyzer.analyze(
            plan: plan,
            currentTrack: current.track,
            nextTrack: next.track,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis
        )
        return PlannedMixReviewPlanComparison(
            source: source,
            reason: reason,
            transitionStartSec: plan.transitionStartSec,
            transitionEndSec: plan.transitionEndSec,
            nextTrackStartOffsetSec: plan.nextTrackStartOffsetSec,
            style: plan.style,
            confidence: plan.confidence,
            candidateId: plan.candidateId,
            renderedQuality: report
        )
    }

    func buildPlanComparison(
        plan: MixPlan,
        source: String,
        reason: String?,
        renderedQuality: RenderedTransitionQualityReport
    ) -> PlannedMixReviewPlanComparison {
        PlannedMixReviewPlanComparison(
            source: source,
            reason: reason,
            transitionStartSec: plan.transitionStartSec,
            transitionEndSec: plan.transitionEndSec,
            nextTrackStartOffsetSec: plan.nextTrackStartOffsetSec,
            style: plan.style,
            confidence: plan.confidence,
            candidateId: plan.candidateId,
            renderedQuality: renderedQuality
        )
    }

    func exportPlan(from comparison: PlannedMixReviewPlanComparison) -> MixReviewExportPlan {
        MixReviewExportPlan(
            source: comparison.source,
            reason: comparison.reason,
            transitionStartSec: comparison.transitionStartSec,
            transitionEndSec: comparison.transitionEndSec,
            nextTrackStartOffsetSec: comparison.nextTrackStartOffsetSec,
            style: comparison.style,
            confidence: comparison.confidence,
            candidateId: comparison.candidateId,
            renderedQuality: comparison.renderedQuality
        )
    }

    func recordMixReviewEvent(plan: MixPlan, review: PlannedMixReview) {
        let event = PlannedMixReviewEvent(
            id: UUID(),
            createdAt: Date(),
            pair: review.pair,
            source: review.source,
            fallbackReason: review.fallbackReason,
            selectionReason: review.selectionReason,
            transitionStartSec: plan.transitionStartSec,
            transitionEndSec: plan.transitionEndSec,
            nextTrackStartOffsetSec: plan.nextTrackStartOffsetSec,
            style: plan.style,
            confidence: plan.confidence,
            candidateId: plan.candidateId,
            renderedQuality: review.renderedQuality,
            shadowFallbackComparison: review.shadowFallbackComparison
        )
        recentMixReviewEvents.insert(event, at: 0)
        recentMixReviewEvents = Array(recentMixReviewEvents.prefix(12))
    }
}

private func formatMixTime(_ seconds: Double) -> String {
    let safeSeconds = max(0, Int(seconds.rounded(.down)))
    return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
}
