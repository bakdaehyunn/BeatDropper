import BeatDropperApplication
import Foundation

@MainActor
protocol PlaybackTransitionExecuting: AnyObject {
    func executeTransition(
        from current: ImportedTrack,
        to target: ImportedTrack,
        plan: MixPlan?,
        clearPlanAfterStart: Bool
    ) throws
}

@MainActor
final class PlayingFeatureController: PlayingFeatureActionHandling, PlaybackTransitionExecuting {
    private let playing: PlayingFeature
    private let library: LibraryFeature
    private let libraryActions: LibraryFeatureController
    private let shell: AppShellFeature

    private var currentMixPlan: () -> MixPlan? = { nil }
    private var currentMixPlanPair: () -> PlannedMixPair? = { nil }
    private var scheduleManualMixPlan: (MixPlan, PlannedMixPair) -> Void = { _, _ in }
    private var clearMixPlan: () -> Void = {}
    private var requestMixPlan: () -> Void = {}
    private var startMixPlanScheduler: () -> Void = {}
    private var stopMixPlanScheduler: () -> Void = {}

    init(
        playing: PlayingFeature,
        library: LibraryFeature,
        libraryActions: LibraryFeatureController,
        shell: AppShellFeature
    ) {
        self.playing = playing
        self.library = library
        self.libraryActions = libraryActions
        self.shell = shell
    }

    func configurePlanningCoordination(
        currentMixPlan: @escaping () -> MixPlan?,
        currentMixPlanPair: @escaping () -> PlannedMixPair?,
        scheduleManualMixPlan: @escaping (MixPlan, PlannedMixPair) -> Void,
        clearMixPlan: @escaping () -> Void,
        requestMixPlan: @escaping () -> Void,
        startMixPlanScheduler: @escaping () -> Void,
        stopMixPlanScheduler: @escaping () -> Void
    ) {
        self.currentMixPlan = currentMixPlan
        self.currentMixPlanPair = currentMixPlanPair
        self.scheduleManualMixPlan = scheduleManualMixPlan
        self.clearMixPlan = clearMixPlan
        self.requestMixPlan = requestMixPlan
        self.startMixPlanScheduler = startMixPlanScheduler
        self.stopMixPlanScheduler = stopMixPlanScheduler
    }

    func playPause() {
        do {
            if playing.session.isPlaybackActive {
                playing.pause()
                stopMixPlanScheduler()
                return
            }

            if playing.session.mode == .paused {
                try playing.resume()
                startMixPlanScheduler()
                return
            }

            guard let selectedTrack = library.selectedTrack else {
                shell.notice = "Load tracks first"
                return
            }
            guard libraryActions.markTrackMissingIfUnavailable(selectedTrack) else {
                shell.notice = "Track file is missing. Rescan or relink the source folder."
                return
            }

            try playing.play(url: selectedTrack.url, track: selectedTrack.track)
            playing.prepare(currentTrack: selectedTrack.track, queuedTrack: library.nextAvailableTrack?.track)
            startMixPlanScheduler()
            shell.notice = "Playing \(selectedTrack.track.title)"
        } catch {
            shell.notice = error.localizedDescription
        }
    }

    func playPreviousTrack() {
        playAdjacentTrack(offset: -1)
    }

    func playNextTrack() {
        playAdjacentTrack(offset: 1)
    }

    private func playAdjacentTrack(offset: Int) {
        do {
            guard
                let selectedTrackIndex = library.selectedTrackIndex,
                let target = library.adjacentAvailableTrack(offset: offset)
            else {
                shell.notice = offset > 0 ? "No available next track" : "No available previous track"
                return
            }

            let current = library.playlist[selectedTrackIndex]
            let matchingPlan = offset == 1 &&
                currentMixPlanPair()?.currentTrackId == current.id &&
                currentMixPlanPair()?.nextTrackId == target.id
                ? currentMixPlan()
                : nil

            if playing.session.isPlaybackActive {
                if offset == 1 {
                    guard let manualPlan = manualNextTransitionPlan(
                        from: current,
                        to: target,
                        proposedPlan: matchingPlan
                    ) else {
                        throw NativePlaybackError.transitionUnavailable
                    }
                    scheduleManualMixPlan(
                        manualPlan,
                        PlannedMixPair(currentTrackId: current.id, nextTrackId: target.id)
                    )
                    startMixPlanScheduler()
                    shell.notice = "Next queued on bar · \(manualPlan.transitionBarCount.map { "\($0) bars" } ?? "seconds fallback")"
                    return
                }
                try executeTransition(
                    from: current,
                    to: target,
                    plan: nil,
                    clearPlanAfterStart: true
                )
                shell.notice = "Crossfading to \(target.track.title)"
            } else {
                libraryActions.selectedTrackID = target.id
                try playing.play(url: target.url, track: target.track)
                playing.prepare(currentTrack: target.track, queuedTrack: library.nextAvailableTrack?.track)
                shell.notice = "Playing \(target.track.title)"
            }
            clearMixPlan()
            requestMixPlan()
        } catch {
            shell.notice = error.localizedDescription
        }
    }

    func executeTransition(
        from current: ImportedTrack,
        to target: ImportedTrack,
        plan: MixPlan?,
        clearPlanAfterStart: Bool
    ) throws {
        guard libraryActions.markTrackMissingIfUnavailable(target) else {
            throw NativePlaybackError.trackUnavailable(target.track.title)
        }

        let duration = plan.map {
            max(0.25, $0.transitionEndSec - $0.transitionStartSec)
        } ?? shell.settings.fadeDurationSec
        let startOffset = plan?.nextTrackStartOffsetSec ?? 0
        libraryActions.selectedTrackID = target.id
        try playing.crossfadeTo(
            url: target.url,
            track: target.track,
            durationSec: duration,
            startOffsetSec: startOffset,
            plan: plan,
            currentAnalysis: library.analysesByTrackID[current.id],
            nextAnalysis: library.analysesByTrackID[target.id]
        ) { [weak self] in
            guard let self else { return }
            self.shell.notice = "Playing \(target.track.title)"
            self.playing.prepare(
                currentTrack: target.track,
                queuedTrack: self.library.nextAvailableTrack?.track
            )
        }
        if clearPlanAfterStart {
            clearMixPlan()
        }
    }

    private func manualNextTransitionPlan(
        from current: ImportedTrack,
        to target: ImportedTrack,
        proposedPlan: MixPlan?
    ) -> MixPlan? {
        let request = PlannerRequestBuilder.build(
            currentTrack: current.track,
            nextTrack: target.track,
            elapsedSec: playing.session.currentTrack?.id == current.id ? playing.session.currentElapsedSec : 0,
            currentAnalysis: library.analysesByTrackID[current.id],
            nextAnalysis: library.analysesByTrackID[target.id],
            currentPreparation: library.preparation(forTrackID: current.id),
            nextPreparation: library.preparation(forTrackID: target.id),
            settings: PlannerSettingsSnapshot(
                fadeDurationSec: shell.settings.fadeDurationSec,
                aiDjMode: shell.settings.aiDjMode
            )
        )
        let context = MixPlanValidationContext(
            currentPlaybackElapsedSec: request.currentPlayback.elapsedSec,
            currentTrackDurationSec: current.track.durationSec,
            nextTrackDurationSec: target.track.durationSec,
            maxFadeDurationSec: shell.settings.fadeDurationSec
        )
        if let proposedPlan {
            return BeatAlignedTransitionPolicy.apply(
                to: proposedPlan,
                request: request,
                validationContext: context,
                intent: .manualNext
            )
        }
        return NativeFallbackMixPlanner.buildPlan(
            request: request,
            validationContext: context,
            failureReason: "manual_next",
            intent: .manualNext
        )
    }
}

private enum NativePlaybackError: LocalizedError {
    case trackUnavailable(String)
    case transitionUnavailable

    var errorDescription: String? {
        switch self {
        case .trackUnavailable(let title):
            return "\(title) is missing. Rescan or relink the source folder."
        case .transitionUnavailable:
            return "No safe transition window is available for the next track."
        }
    }
}
