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
                self.currentMixPlan = plan
                self.currentMixPlanPair = PlannedMixPair(currentTrackId: current.id, nextTrackId: next.id)
                self.updateScheduledMixStatus()
                self.startMixPlanSchedulerIfNeeded()
                self.notice = result.source == "local-fallback"
                    ? "Local fallback mix plan ready"
                    : "AI mix plan ready"
            } else {
                self.currentMixPlan = nil
                self.currentMixPlanPair = nil
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
        scheduledMixCountdownSec = nil
        if !isPlanningMix {
            plannerStatus = isAIMixEnabled ? "AI mix active" : "No AI mix plan"
        }
    }
}

private func formatMixTime(_ seconds: Double) -> String {
    let safeSeconds = max(0, Int(seconds.rounded(.down)))
    return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
}
