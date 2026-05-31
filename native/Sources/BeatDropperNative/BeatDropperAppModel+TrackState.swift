import BeatDropperCore
import Foundation

extension BeatDropperAppModel {
    var selectedTrack: ImportedTrack? {
        playlist.first { $0.id == selectedTrackID }
    }

    var selectedLibraryTrack: ImportedTrack? {
        guard let selectedLibraryTrackID else {
            return nil
        }
        guard let row = libraryBrowserTracks.first(where: { $0.id == selectedLibraryTrackID }) else {
            return nil
        }
        return importedTrack(from: row)
    }

    var creativePreparationTrack: ImportedTrack? {
        guard let creativePreparationTrackID else {
            return selectedTrack ?? selectedLibraryTrack
        }
        if let playlistTrack = playlist.first(where: { $0.id == creativePreparationTrackID }) {
            return playlistTrack
        }
        if let row = libraryBrowserTracks.first(where: { $0.id == creativePreparationTrackID }) {
            return importedTrack(from: row)
        }
        return libraryRecords.first(where: { $0.id == creativePreparationTrackID }).map(ImportedTrack.init(record:))
    }

    var creativePreparationAnalysis: TrackAnalysis? {
        guard let trackId = creativePreparationTrack?.id else {
            return nil
        }
        return trackAnalysesById[trackId]
    }

    var creativeTrackPreparation: TrackPreparation {
        guard let trackId = creativePreparationTrack?.id else {
            return .empty
        }
        return preparation(forTrackId: trackId)
    }

    var creativeEffectiveBPM: Double? {
        guard let track = creativePreparationTrack else {
            return nil
        }
        return effectiveBPM(forTrackId: track.id, trackBPM: track.track.bpm, analysis: trackAnalysesById[track.id])
    }

    var canPreviewCreativeTrack: Bool {
        creativePreparationTrack.map(isTrackAvailableForImmediateUse) ?? false
    }

    var isCreativePreviewTrackLoaded: Bool {
        guard let track = creativePreparationTrack else {
            return false
        }
        return audioEngine.currentTrack?.id == track.id
    }

    var isCreativePreviewPlaying: Bool {
        isCreativePreviewTrackLoaded && audioEngine.isPlaybackActive
    }

    var creativePlaybackPositionSec: Double {
        guard isCreativePreviewTrackLoaded else {
            return creativePreviewPositionSec
        }
        return audioEngine.elapsedSec
    }

    var selectedTrackIndex: Int? {
        guard let selectedTrackID else {
            return nil
        }
        return playlist.firstIndex { $0.id == selectedTrackID }
    }

    var selectedUserPlaylist: UserPlaylist? {
        userPlaylists.first { $0.id == selectedUserPlaylistId }
    }

    var totalDurationSec: Double {
        playlist.reduce(0) { $0 + $1.track.durationSec }
    }

    var hasLibrarySourceFolders: Bool {
        !librarySourceFolders.isEmpty
    }

    var missingSourceFolders: [NativeLibrarySourceFolder] {
        librarySourceFolders.filter(\.missing)
    }

    var hasMissingSourceFolders: Bool {
        !missingSourceFolders.isEmpty
    }

    var analysisQueueStatus: String? {
        let running = runningAnalysisTrackCount
        let queued = queuedAnalysisTrackCount
        guard running + queued > 0 else {
            return nil
        }
        if running > 0, queued > 0 {
            return "DSP analysis \(running) running · \(queued) queued"
        }
        if running > 0 {
            return "DSP analysis \(running) running"
        }
        return "DSP analysis \(queued) queued"
    }

    var selectedTrackNeedsRelink: Bool {
        selectedTrack.map { !isTrackAvailableForImmediateUse($0) } ?? false
    }

    var canSaveCurrentSet: Bool {
        !playlist.isEmpty && !normalizeUserPlaylistName(userPlaylistNameDraft).isEmpty
    }

    var canLoadSelectedSet: Bool {
        selectedUserPlaylist != nil
    }

    var canAddSelectedLibraryTrackToPlaylist: Bool {
        selectedLibraryTrack != nil
    }

    var canMoveSelectedTrackUp: Bool {
        guard let selectedTrackIndex else {
            return false
        }
        return selectedTrackIndex > 0
    }

    var canMoveSelectedTrackDown: Bool {
        guard let selectedTrackIndex else {
            return false
        }
        return selectedTrackIndex < playlist.count - 1
    }

    var canRemoveSelectedTrack: Bool {
        selectedTrackID != nil
    }

    var canClearPlaylist: Bool {
        !playlist.isEmpty
    }

    var hasPreviousTrack: Bool {
        adjacentAvailableTrack(offset: -1) != nil
    }

    var hasNextTrack: Bool {
        nextTrackAfterSelection != nil
    }

    var nextTrackAfterSelection: ImportedTrack? {
        adjacentAvailableTrack(offset: 1)
    }

    var canUseTransportPlayPause: Bool {
        if audioEngine.isPlaybackActive || audioEngine.state == .paused {
            return true
        }
        return selectedTrack.map(isTrackAvailableForImmediateUse) ?? false
    }

    var canRequestMixPlan: Bool {
        guard !isPlanningMix,
              let selectedTrack,
              let nextTrackAfterSelection
        else {
            return false
        }
        return isTrackAvailableForImmediateUse(selectedTrack) &&
            isTrackAvailableForImmediateUse(nextTrackAfterSelection)
    }

    var canEnableAIMix: Bool {
        guard let selectedTrack, let nextTrackAfterSelection else {
            return false
        }
        return isTrackAvailableForImmediateUse(selectedTrack) &&
            isTrackAvailableForImmediateUse(nextTrackAfterSelection)
    }

    var canCancelMixPlan: Bool {
        currentMixPlan != nil || isPlanningMix || isAIMixEnabled
    }

    var isPlaybackActive: Bool {
        audioEngine.isPlaybackActive
    }

    func availabilityStatus(for imported: ImportedTrack) -> String {
        if imported.missing {
            return "Missing"
        }
        if !FileManager.default.fileExists(atPath: imported.url.path) {
            return "Unavailable"
        }
        return "Ready"
    }

    func availabilityStatus(for browserTrack: NativeLibraryBrowserTrack) -> String {
        availabilityStatus(for: importedTrack(from: browserTrack))
    }

    func isTrackAvailable(_ imported: ImportedTrack) -> Bool {
        isTrackAvailableForImmediateUse(imported)
    }

    func isTrackAvailable(_ browserTrack: NativeLibraryBrowserTrack) -> Bool {
        isTrackAvailableForImmediateUse(importedTrack(from: browserTrack))
    }

    func sourceDisplayName(for imported: ImportedTrack) -> String {
        guard let sourceFolderPath = imported.sourceFolderPath else {
            return "Files"
        }
        let normalizedPath = URL(fileURLWithPath: sourceFolderPath).standardizedFileURL.path
        if let folder = librarySourceFolders.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalizedPath
        }) {
            return folder.displayName
        }
        return URL(fileURLWithPath: sourceFolderPath).lastPathComponent
    }

    func importedTrack(from browserTrack: NativeLibraryBrowserTrack) -> ImportedTrack {
        ImportedTrack(
            track: browserTrack.track,
            url: URL(fileURLWithPath: browserTrack.filePath),
            sourceFolderPath: browserTrack.sourceFolderPath,
            fileFingerprint: browserTrack.fileFingerprint,
            missing: browserTrack.missing,
            missingAt: browserTrack.missingAt
        )
    }

    func adjacentAvailableTrack(offset: Int) -> ImportedTrack? {
        guard
            let selectedTrackIndex,
            offset != 0
        else {
            return nil
        }

        var index = selectedTrackIndex + offset
        while playlist.indices.contains(index) {
            let candidate = playlist[index]
            if isTrackAvailableForImmediateUse(candidate) {
                return candidate
            }
            index += offset
        }
        return nil
    }

    func analysisStatus(for imported: ImportedTrack) -> String {
        guard isTrackAvailableForImmediateUse(imported) else {
            return imported.missing ? "Missing" : "Unavailable"
        }
        if analysisQueueState.isRunning(imported.id) {
            return "Analyzing"
        }
        if analysisQueueState.isPending(imported.id) {
            return "Queued"
        }
        guard let analysis = trackAnalysesById[imported.id] else {
            return "Pending"
        }
        return "Quality \(Int((analysis.analysisConfidence * 100).rounded()))%"
    }

    func analysis(for imported: ImportedTrack) -> TrackAnalysis? {
        trackAnalysesById[imported.id]
    }

    func displayBPM(for imported: ImportedTrack) -> String {
        guard let bpm = effectiveBPM(
            forTrackId: imported.id,
            trackBPM: imported.track.bpm,
            analysis: trackAnalysesById[imported.id]
        ) else {
            return "--"
        }
        return String(Int(bpm.rounded()))
    }

    func displayBPM(for browserTrack: NativeLibraryBrowserTrack) -> String {
        guard let bpm = effectiveBPM(
            forTrackId: browserTrack.id,
            trackBPM: browserTrack.track.bpm,
            analysis: trackAnalysesById[browserTrack.id]
        ) else {
            return "--"
        }
        return String(Int(bpm.rounded()))
    }

    func preparation(for imported: ImportedTrack) -> TrackPreparation {
        preparation(forTrackId: imported.id)
    }

    func preparation(forTrackId trackId: String) -> TrackPreparation {
        libraryRecords.first { $0.id == trackId }?.preparation ?? .empty
    }

    func effectiveBPM(
        forTrackId trackId: String,
        trackBPM: Double?,
        analysis: TrackAnalysis?
    ) -> Double? {
        preparation(forTrackId: trackId).bpmOverride ?? analysis?.bpm ?? trackBPM
    }

    func formatDurationLabel(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--"
        }
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
    }

    func isTrackAvailableForImmediateUse(_ imported: ImportedTrack) -> Bool {
        !imported.missing && FileManager.default.fileExists(atPath: imported.url.path)
    }
}
