import BeatDropperApplication
import Foundation

@MainActor
final class CreativeFeatureController: CreativeFeatureActionHandling {
    private let creative: CreativeFeature
    private let library: LibraryFeature
    private let playing: PlayingFeature
    private let libraryActions: LibraryFeatureController
    private let shell: AppShellFeature
    private let clock: any AppClock

    init(
        creative: CreativeFeature,
        library: LibraryFeature,
        playing: PlayingFeature,
        libraryActions: LibraryFeatureController,
        shell: AppShellFeature,
        clock: any AppClock
    ) {
        self.creative = creative
        self.library = library
        self.playing = playing
        self.libraryActions = libraryActions
        self.shell = shell
        self.clock = clock
    }

    func previewCreativeTrack(at timeSec: Double) {
        guard let track = creative.preparationTrack(in: library) else {
            shell.notice = "Select a track first"
            return
        }
        guard libraryActions.markTrackMissingIfUnavailable(track) else {
            shell.notice = "Track file is missing. Rescan or relink the source folder."
            return
        }

        let safeTime = PlaybackPositionMath.clampedElapsed(timeSec, durationSec: track.track.durationSec)
        creative.previewPositionSec = safeTime
        do {
            try playing.playPreview(url: track.url, track: track.track, startOffsetSec: safeTime)
            shell.notice = "Preview \(track.track.title) at \(nativeDurationLabel(safeTime))"
        } catch {
            shell.notice = error.localizedDescription
        }
    }

    func toggleCreativePreviewPlayback() {
        guard let track = creative.preparationTrack(in: library) else {
            shell.notice = "Select a track first"
            return
        }
        guard libraryActions.markTrackMissingIfUnavailable(track) else {
            shell.notice = "Track file is missing. Rescan or relink the source folder."
            return
        }

        do {
            if creative.isPreviewTrackLoaded(in: library, playing: playing), playing.session.isPlaybackActive {
                creative.previewPositionSec = playing.session.currentElapsedSec
                playing.pause()
                shell.notice = "Preview paused"
                return
            }
            if creative.isPreviewTrackLoaded(in: library, playing: playing), playing.session.mode == .paused {
                try playing.resume()
                shell.notice = "Preview \(track.track.title)"
                return
            }
            previewCreativeTrack(at: creative.previewPositionSec)
        } catch {
            shell.notice = error.localizedDescription
        }
    }

    func seekCreativePreview(by deltaSec: Double) {
        previewCreativeTrack(at: creative.playbackPosition(in: library, playing: playing) + deltaSec)
    }

    func stopCreativePreview() {
        if creative.isPreviewTrackLoaded(in: library, playing: playing) { playing.stop() }
        creative.previewPositionSec = 0
        shell.notice = "Preview stopped"
    }

    func tapBPMForCreativeTrack() {
        guard creative.preparationTrack(in: library) != nil else {
            shell.notice = "Select a track first"
            return
        }

        let now = clock.now
        if let last = creative.bpmTapDates.last, now.timeIntervalSince(last) > 2 {
            creative.bpmTapDates.removeAll()
        }
        creative.bpmTapDates.append(now)
        creative.bpmTapDates = Array(creative.bpmTapDates.suffix(8))
        creative.bpmTapCount = creative.bpmTapDates.count

        guard creative.bpmTapDates.count >= 2 else {
            creative.bpmTapEstimate = nil
            shell.notice = "Tap BPM"
            return
        }
        let intervals = zip(creative.bpmTapDates.dropFirst(), creative.bpmTapDates).map { later, earlier in
            later.timeIntervalSince(earlier)
        }
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard averageInterval > 0 else { return }

        var bpm = 60 / averageInterval
        while bpm < 90 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        creative.bpmTapEstimate = (bpm * 10).rounded() / 10
        shell.notice = "Tap BPM \(String(format: "%.1f", creative.bpmTapEstimate ?? bpm))"
    }

    func applyTappedBPMToCreativeTrack() {
        guard let track = creative.preparationTrack(in: library) else {
            shell.notice = "Select a track first"
            return
        }
        guard let bpm = creative.bpmTapEstimate else {
            shell.notice = "Tap BPM first"
            return
        }
        libraryActions.updatePreparation(forTrackID: track.id) { $0.bpmOverride = bpm }
        shell.notice = "Set prep BPM \(String(format: "%.1f", bpm))"
    }

    func setCreativeBPMOverride(_ bpm: Double) {
        guard let track = creative.preparationTrack(in: library) else {
            shell.notice = "Select a track first"
            return
        }
        guard bpm.isFinite, (40...260).contains(bpm) else {
            shell.notice = "BPM must be 40-260"
            return
        }
        let preparedBPM = (bpm * 10).rounded() / 10
        libraryActions.updatePreparation(forTrackID: track.id) { $0.bpmOverride = preparedBPM }
        resetBPMTapState()
        shell.notice = "Set prep BPM \(String(format: "%.1f", preparedBPM))"
    }

    func clearCreativeBPMOverride() {
        guard let track = creative.preparationTrack(in: library) else {
            shell.notice = "Select a track first"
            return
        }
        libraryActions.updatePreparation(forTrackID: track.id) { $0.bpmOverride = nil }
        resetBPMTapState()
        shell.notice = "Cleared prep BPM"
    }

    func addCreativeHotCue(kind: TrackPreparationCueKind) {
        guard let track = creative.preparationTrack(in: library) else {
            shell.notice = "Select a track first"
            return
        }
        let safeTime = PlaybackPositionMath.clampedElapsed(
            creative.playbackPosition(in: library, playing: playing),
            durationSec: track.track.durationSec
        )
        libraryActions.updatePreparation(forTrackID: track.id) {
            $0.hotCues.append(TrackPreparationCue(kind: kind, timeSec: safeTime, label: kind.displayName))
        }
        shell.notice = "Added \(kind.displayName) cue at \(nativeDurationLabel(safeTime))"
    }

    func removeCreativeHotCue(_ cue: TrackPreparationCue) {
        guard let track = creative.preparationTrack(in: library) else { return }
        libraryActions.updatePreparation(forTrackID: track.id) {
            $0.hotCues.removeAll { $0.id == cue.id }
        }
        shell.notice = "Removed cue"
    }

    private func resetBPMTapState() {
        creative.bpmTapDates.removeAll()
        creative.bpmTapEstimate = nil
        creative.bpmTapCount = 0
    }
}

private func nativeDurationLabel(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "--" }
    let safeSeconds = max(0, Int(seconds.rounded(.down)))
    return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
}
