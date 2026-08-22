import BeatDropperDomain
import BeatDropperLibrary
import Foundation

public extension LibraryFeature {
    var selectedTrack: ImportedTrack? {
        playlist.first { $0.id == selectedTrackID }
    }

    var selectedTrackIndex: Int? {
        guard let selectedTrackID else { return nil }
        return playlist.firstIndex { $0.id == selectedTrackID }
    }

    var selectedLibraryTrack: ImportedTrack? {
        guard let selectedLibraryTrackID,
              let row = browserTracks.first(where: { $0.id == selectedLibraryTrackID })
        else { return nil }
        return importedTrack(from: row)
    }

    var selectedUserPlaylist: UserPlaylist? {
        userPlaylists.first { $0.id == selectedUserPlaylistID }
    }

    var selectedTrackAnalysis: TrackAnalysis? {
        selectedTrack.flatMap { analysesByTrackID[$0.id] }
    }

    var totalDurationSec: Double {
        playlist.reduce(0) { $0 + $1.track.durationSec }
    }

    var hasSourceFolders: Bool { !sourceFolders.isEmpty }
    var missingSourceFolders: [NativeLibrarySourceFolder] { sourceFolders.filter(\.missing) }
    var hasMissingSourceFolders: Bool { !missingSourceFolders.isEmpty }

    var analysisQueueStatus: String? {
        let running = runningAnalysisTrackCount
        let queued = queuedAnalysisTrackCount
        guard running + queued > 0 else { return nil }
        if running > 0, queued > 0 { return "DSP analysis \(running) running · \(queued) queued" }
        if running > 0 { return "DSP analysis \(running) running" }
        return "DSP analysis \(queued) queued"
    }

    var selectedTrackNeedsRelink: Bool {
        selectedTrack.map { !isAvailable($0) } ?? false
    }

    var canSaveCurrentSet: Bool {
        !playlist.isEmpty && !normalizeUserPlaylistName(userPlaylistNameDraft).isEmpty
    }

    var canLoadSelectedSet: Bool { selectedUserPlaylist != nil }
    var canAddSelectedLibraryTrackToPlaylist: Bool { selectedLibraryTrack != nil }
    var canRemoveSelectedTrack: Bool { selectedTrackID != nil }
    var canClearPlaylist: Bool { !playlist.isEmpty }

    var canMoveSelectedTrackUp: Bool {
        guard let selectedTrackIndex else { return false }
        return selectedTrackIndex > 0
    }

    var canMoveSelectedTrackDown: Bool {
        guard let selectedTrackIndex else { return false }
        return selectedTrackIndex < playlist.count - 1
    }

    var previousAvailableTrack: ImportedTrack? { adjacentAvailableTrack(offset: -1) }
    var nextAvailableTrack: ImportedTrack? { adjacentAvailableTrack(offset: 1) }
    var hasPreviousTrack: Bool { previousAvailableTrack != nil }
    var hasNextTrack: Bool { nextAvailableTrack != nil }

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

    func availabilityStatus(for track: ImportedTrack) -> String {
        if track.missing { return "Missing" }
        return isAvailable(track) ? "Ready" : "Unavailable"
    }

    func availabilityStatus(for browserTrack: NativeLibraryBrowserTrack) -> String {
        availabilityStatus(for: importedTrack(from: browserTrack))
    }

    func isAvailable(_ browserTrack: NativeLibraryBrowserTrack) -> Bool {
        isAvailable(importedTrack(from: browserTrack))
    }

    func adjacentAvailableTrack(offset: Int) -> ImportedTrack? {
        guard let selectedTrackIndex, offset != 0 else { return nil }
        var index = selectedTrackIndex + offset
        while playlist.indices.contains(index) {
            let candidate = playlist[index]
            if isAvailable(candidate) { return candidate }
            index += offset
        }
        return nil
    }

    func analysisStatus(for track: ImportedTrack) -> String {
        guard isAvailable(track) else { return track.missing ? "Missing" : "Unavailable" }
        if analysisQueueState.isRunning(track.id) { return "Analyzing" }
        if analysisQueueState.isPending(track.id) { return "Queued" }
        guard let analysis = analysesByTrackID[track.id] else { return "Pending" }
        return "Quality \(Int((analysis.analysisConfidence * 100).rounded()))%"
    }

    func analysis(for track: ImportedTrack) -> TrackAnalysis? { analysesByTrackID[track.id] }

    func preparation(forTrackID trackID: String) -> TrackPreparation {
        records.first { $0.id == trackID }?.preparation ?? .empty
    }

    func effectiveBPM(forTrackID trackID: String, trackBPM: Double?, analysis: TrackAnalysis?) -> Double? {
        preparation(forTrackID: trackID).bpmOverride ?? analysis?.bpm ?? trackBPM
    }

    func displayBPM(for track: ImportedTrack) -> String {
        guard let bpm = effectiveBPM(
            forTrackID: track.id,
            trackBPM: track.track.bpm,
            analysis: analysesByTrackID[track.id]
        ) else { return "--" }
        return String(Int(bpm.rounded()))
    }

    func displayBPM(for browserTrack: NativeLibraryBrowserTrack) -> String {
        guard let bpm = effectiveBPM(
            forTrackID: browserTrack.id,
            trackBPM: browserTrack.track.bpm,
            analysis: analysesByTrackID[browserTrack.id]
        ) else { return "--" }
        return String(Int(bpm.rounded()))
    }
}

public extension CreativeFeature {
    func preparationTrack(in library: LibraryFeature) -> ImportedTrack? {
        guard let preparationTrackID else { return library.selectedTrack ?? library.selectedLibraryTrack }
        if let track = library.playlist.first(where: { $0.id == preparationTrackID }) { return track }
        if let row = library.browserTracks.first(where: { $0.id == preparationTrackID }) {
            return library.importedTrack(from: row)
        }
        return library.records.first(where: { $0.id == preparationTrackID }).map(ImportedTrack.init(record:))
    }

    func preparationAnalysis(in library: LibraryFeature) -> TrackAnalysis? {
        guard let trackID = preparationTrack(in: library)?.id else { return nil }
        return library.analysesByTrackID[trackID]
    }

    func trackPreparation(in library: LibraryFeature) -> TrackPreparation {
        guard let trackID = preparationTrack(in: library)?.id else { return .empty }
        return library.preparation(forTrackID: trackID)
    }

    func effectiveBPM(in library: LibraryFeature) -> Double? {
        guard let track = preparationTrack(in: library) else { return nil }
        return library.effectiveBPM(
            forTrackID: track.id,
            trackBPM: track.track.bpm,
            analysis: library.analysesByTrackID[track.id]
        )
    }

    func canPreview(in library: LibraryFeature) -> Bool {
        preparationTrack(in: library).map(library.isAvailable) ?? false
    }

    func isPreviewTrackLoaded(in library: LibraryFeature, playing: PlayingFeature) -> Bool {
        guard let track = preparationTrack(in: library) else { return false }
        return playing.session.currentTrack?.id == track.id
    }

    func isPreviewPlaying(in library: LibraryFeature, playing: PlayingFeature) -> Bool {
        isPreviewTrackLoaded(in: library, playing: playing) && playing.session.isPlaybackActive
    }

    func playbackPosition(in library: LibraryFeature, playing: PlayingFeature) -> Double {
        isPreviewTrackLoaded(in: library, playing: playing) ? playing.session.currentElapsedSec : previewPositionSec
    }
}

public extension PlayingFeature {
    var currentDisplayTrack: Track? { session.currentTrack }
    var nextDisplayTrack: Track? { session.queuedTrack }
    var isPlaybackActive: Bool { session.isPlaybackActive }

    func canUseTransport(in library: LibraryFeature) -> Bool {
        if session.isPlaybackActive || session.mode == .paused { return true }
        return library.selectedTrack.map(library.isAvailable) ?? false
    }

    func currentDisplayStatus(in library: LibraryFeature) -> String {
        if session.isPlaybackActive { return session.mode.rawValue }
        guard let trackID = session.currentTrack?.id,
              let imported = library.playlist.first(where: { $0.id == trackID })
        else { return "Selected" }
        return library.availabilityStatus(for: imported)
    }

    func nextDisplayStatus(in library: LibraryFeature) -> String {
        if session.queuedTrack != nil { return session.mode == .crossfading ? "Crossfading" : "Queued" }
        return "No available next"
    }

    func currentAnalysis(in library: LibraryFeature) -> TrackAnalysis? {
        currentDisplayTrack.flatMap { library.analysesByTrackID[$0.id] }
    }

    func nextAnalysis(in library: LibraryFeature) -> TrackAnalysis? {
        nextDisplayTrack.flatMap { library.analysesByTrackID[$0.id] }
    }
}

public extension MixPlanningFeature {
    func canRequestPlan(in library: LibraryFeature) -> Bool {
        guard !isPlanning,
              let current = library.selectedTrack,
              let next = library.nextAvailableTrack
        else { return false }
        return library.isAvailable(current) && library.isAvailable(next)
    }

    func canEnable(in library: LibraryFeature) -> Bool {
        guard let current = library.selectedTrack, let next = library.nextAvailableTrack else { return false }
        return library.isAvailable(current) && library.isAvailable(next)
    }

    var canCancel: Bool { currentPlan != nil || isPlanning || isEnabled }
}
