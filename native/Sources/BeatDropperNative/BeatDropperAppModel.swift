import AppKit
import BeatDropperCore
import Foundation

enum NativeWorkspaceMode: String, CaseIterable, Identifiable {
    case playing = "Playing"
    case creative = "Creative"

    var id: String { rawValue }
}

@MainActor
final class BeatDropperAppModel: ObservableObject {
    @Published var playlist: [ImportedTrack] = []
    @Published var libraryRecords: [NativeTrackRecord] = [] {
        didSet { rebuildLibraryBrowserIndex() }
    }
    @Published var librarySourceFolders: [NativeLibrarySourceFolder] = [] {
        didSet { rebuildLibraryBrowserIndex() }
    }
    @Published var userPlaylists: [UserPlaylist] = []
    @Published var trackAnalysesById: [String: TrackAnalysis] = [:]
    @Published private(set) var settings: PlayerSettings = .defaults
    @Published var analyzingTrackIds: Set<String> = []
    @Published var queuedAnalysisTrackCount: Int = 0
    @Published var runningAnalysisTrackCount: Int = 0
    @Published var libraryBrowserTracks: [NativeLibraryBrowserTrack] = []
    @Published var filteredLibraryTracks: [NativeLibraryBrowserTrack] = []
    @Published var currentMixPlan: MixPlan?
    @Published var currentMixPlanPair: PlannedMixPair?
    @Published var currentMixPlanReview: PlannedMixReview?
    @Published var recentMixReviewEvents: [PlannedMixReviewEvent] = []
    @Published var importedMixReviewArtifacts: [ImportedMixReviewArtifact] = []
    @Published var isImportedMixReviewArtifactPairFilterEnabled: Bool = false
    @Published var importedMixReviewArtifactSearchText: String = ""
    @Published var selectedImportedMixReviewComparisonArtifactIds: [ImportedMixReviewArtifact.ID] = []
    @Published var isPlanningMix: Bool = false
    @Published var plannerStatus: String = "No AI mix plan"
    @Published var isAIMixEnabled: Bool = false
    @Published var scheduledMixCountdownSec: Double?
    @Published private(set) var creativePreparationTrackID: ImportedTrack.ID? {
        didSet {
            if oldValue != creativePreparationTrackID {
                creativePreviewPositionSec = 0
                resetBPMTapState()
            }
        }
    }
    @Published private(set) var creativePreviewPositionSec: Double = 0
    @Published private(set) var bpmTapEstimate: Double?
    @Published private(set) var bpmTapCount: Int = 0
    @Published var selectedTrackID: ImportedTrack.ID? {
        didSet {
            if let selectedTrackID {
                creativePreparationTrackID = selectedTrackID
            }
        }
    }
    @Published var selectedUserPlaylistId: String = ""
    @Published var userPlaylistNameDraft: String = ""
    @Published var notice: String = "Ready"
    @Published var workspaceMode: NativeWorkspaceMode = .playing
    @Published var isInspectorVisible: Bool = false
    @Published var isLibraryBrowserVisible: Bool = true
    @Published var selectedLibraryTrackID: ImportedTrack.ID? {
        didSet {
            if let selectedLibraryTrackID {
                creativePreparationTrackID = selectedLibraryTrackID
            }
        }
    }
    @Published var librarySearchText: String = "" {
        didSet { rebuildFilteredLibraryTracks() }
    }

    let audioEngine = NativeAudioEngine()

    let store: NativeLibraryStore
    private let settingsStore: NativeSettingsStore
    let analysisStore: NativeTrackAnalysisStore
    let mixReviewArtifactStore: MixReviewArtifactStore
    let mixPlanner: NativeMixPlannerBridge
    let maxConcurrentAnalysisTasks = NativeAnalysisQueueState.recommendedConcurrency(
        activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
    )
    var analysisQueueState = NativeAnalysisQueueState()
    var queuedAnalysisTracksById: [String: ImportedTrack] = [:]
    var mixPlanTimer: Timer?
    var isExecutingScheduledMix = false
    var activePlannerRequestID: UUID?
    private var bpmTapDates: [Date] = []

    init(
        store: NativeLibraryStore = .applicationSupport(),
        settingsStore: NativeSettingsStore = .applicationSupport(),
        analysisStore: NativeTrackAnalysisStore = .applicationSupport(),
        mixReviewArtifactStore: MixReviewArtifactStore = .applicationSupport(),
        mixPlanner: NativeMixPlannerBridge = NativeMixPlannerBridge()
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.analysisStore = analysisStore
        self.mixReviewArtifactStore = mixReviewArtifactStore
        self.mixPlanner = mixPlanner
        restoreSettings()
        restoreLibraryState()
        restoreMixReviewArtifacts()
    }

    func previewCreativeTrack(at timeSec: Double) {
        guard let track = creativePreparationTrack else {
            notice = "Select a track first"
            return
        }
        guard markTrackMissingIfUnavailable(track) else {
            notice = "Track file is missing. Rescan or relink the source folder."
            return
        }

        let safeTime = PlaybackPositionMath.clampedElapsed(timeSec, durationSec: track.track.durationSec)
        creativePreviewPositionSec = safeTime
        do {
            try audioEngine.playPreview(url: track.url, track: track.track, startOffsetSec: safeTime)
            notice = "Preview \(track.track.title) at \(formatDurationLabel(safeTime))"
        } catch {
            notice = error.localizedDescription
        }
    }

    func toggleCreativePreviewPlayback() {
        guard let track = creativePreparationTrack else {
            notice = "Select a track first"
            return
        }
        guard markTrackMissingIfUnavailable(track) else {
            notice = "Track file is missing. Rescan or relink the source folder."
            return
        }

        do {
            if isCreativePreviewTrackLoaded, audioEngine.isPlaybackActive {
                creativePreviewPositionSec = audioEngine.elapsedSec
                audioEngine.pause()
                notice = "Preview paused"
                return
            }

            if isCreativePreviewTrackLoaded, audioEngine.state == .paused {
                try audioEngine.resume()
                notice = "Preview \(track.track.title)"
                return
            }

            previewCreativeTrack(at: creativePreviewPositionSec)
        } catch {
            notice = error.localizedDescription
        }
    }

    func seekCreativePreview(by deltaSec: Double) {
        let nextPosition = creativePlaybackPositionSec + deltaSec
        previewCreativeTrack(at: nextPosition)
    }

    func stopCreativePreview() {
        if isCreativePreviewTrackLoaded {
            audioEngine.stop()
        }
        creativePreviewPositionSec = 0
        notice = "Preview stopped"
    }

    func tapBPMForCreativeTrack() {
        guard creativePreparationTrack != nil else {
            notice = "Select a track first"
            return
        }

        let now = Date()
        if let last = bpmTapDates.last, now.timeIntervalSince(last) > 2 {
            bpmTapDates.removeAll()
        }
        bpmTapDates.append(now)
        bpmTapDates = Array(bpmTapDates.suffix(8))
        bpmTapCount = bpmTapDates.count

        guard bpmTapDates.count >= 2 else {
            bpmTapEstimate = nil
            notice = "Tap BPM"
            return
        }

        let intervals = zip(bpmTapDates.dropFirst(), bpmTapDates).map { later, earlier in
            later.timeIntervalSince(earlier)
        }
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard averageInterval > 0 else {
            return
        }

        var bpm = 60 / averageInterval
        while bpm < 90 {
            bpm *= 2
        }
        while bpm > 180 {
            bpm /= 2
        }
        bpmTapEstimate = (bpm * 10).rounded() / 10
        notice = "Tap BPM \(String(format: "%.1f", bpmTapEstimate ?? bpm))"
    }

    func applyTappedBPMToCreativeTrack() {
        guard let track = creativePreparationTrack else {
            notice = "Select a track first"
            return
        }
        guard let bpmTapEstimate else {
            notice = "Tap BPM first"
            return
        }

        updatePreparation(forTrackId: track.id) { preparation in
            preparation.bpmOverride = bpmTapEstimate
        }
        notice = "Set prep BPM \(String(format: "%.1f", bpmTapEstimate))"
    }

    func setCreativeBPMOverride(_ bpm: Double) {
        guard let track = creativePreparationTrack else {
            notice = "Select a track first"
            return
        }
        guard bpm.isFinite, (40...260).contains(bpm) else {
            notice = "BPM must be 40-260"
            return
        }

        let preparedBPM = (bpm * 10).rounded() / 10
        updatePreparation(forTrackId: track.id) { preparation in
            preparation.bpmOverride = preparedBPM
        }
        resetBPMTapState()
        notice = "Set prep BPM \(String(format: "%.1f", preparedBPM))"
    }

    func clearCreativeBPMOverride() {
        guard let track = creativePreparationTrack else {
            notice = "Select a track first"
            return
        }
        updatePreparation(forTrackId: track.id) { preparation in
            preparation.bpmOverride = nil
        }
        resetBPMTapState()
        notice = "Cleared prep BPM"
    }

    func addCreativeHotCue(kind: TrackPreparationCueKind) {
        guard let track = creativePreparationTrack else {
            notice = "Select a track first"
            return
        }
        let safeTime = PlaybackPositionMath.clampedElapsed(
            creativePlaybackPositionSec,
            durationSec: track.track.durationSec
        )
        updatePreparation(forTrackId: track.id) { preparation in
            preparation.hotCues.append(TrackPreparationCue(
                kind: kind,
                timeSec: safeTime,
                label: kind.displayName
            ))
        }
        notice = "Added \(kind.displayName) cue at \(formatDurationLabel(safeTime))"
    }

    func removeCreativeHotCue(_ cue: TrackPreparationCue) {
        guard let track = creativePreparationTrack else {
            return
        }
        updatePreparation(forTrackId: track.id) { preparation in
            preparation.hotCues.removeAll { $0.id == cue.id }
        }
        notice = "Removed cue"
    }

    private func updatePreparation(
        forTrackId trackId: String,
        mutate: (inout TrackPreparation) -> Void
    ) {
        guard let index = libraryRecords.firstIndex(where: { $0.id == trackId }) else {
            notice = "Track is not in the library"
            return
        }

        var record = libraryRecords[index]
        var preparation = record.preparation
        mutate(&preparation)
        record.preparation = preparation
        record.updatedAt = timestamp()
        libraryRecords[index] = record
        refreshPlaylistFromLibraryRecords()
        persistLibraryState()
    }

    private func resetBPMTapState() {
        bpmTapDates.removeAll()
        bpmTapEstimate = nil
        bpmTapCount = 0
    }

    func updateFadeDuration(_ value: Double) {
        updateSettings(invalidatesMixPlan: true) { settings in
            settings.fadeDurationSec = value
        }
    }

    func updateMasterGain(_ value: Double) {
        updateSettings(invalidatesMixPlan: false) { settings in
            settings.masterGain = value
        }
    }

    func updateAIDJMode(_ mode: AIDJMode) {
        updateSettings(invalidatesMixPlan: true) { settings in
            settings.aiDjMode = mode
        }
    }

    func playPause() {
        do {
            if audioEngine.isPlaybackActive {
                audioEngine.pause()
                stopMixPlanScheduler()
                return
            }

            if audioEngine.state == .paused {
                try audioEngine.resume()
                startMixPlanSchedulerIfNeeded()
                return
            }

            guard let selectedTrack else {
                notice = "Load tracks first"
                return
            }
            guard markTrackMissingIfUnavailable(selectedTrack) else {
                notice = "Track file is missing. Rescan or relink the source folder."
                return
            }

            try audioEngine.play(url: selectedTrack.url, track: selectedTrack.track)
            startMixPlanSchedulerIfNeeded()
            notice = "Playing \(selectedTrack.track.title)"
        } catch {
            notice = error.localizedDescription
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
                let selectedTrackIndex,
                let target = adjacentAvailableTrack(offset: offset)
            else {
                notice = offset > 0 ? "No available next track" : "No available previous track"
                return
            }

            let current = playlist[selectedTrackIndex]
            let matchingPlan = offset == 1 &&
                currentMixPlanPair?.currentTrackId == current.id &&
                currentMixPlanPair?.nextTrackId == target.id
                ? currentMixPlan
                : nil
            selectedTrackID = target.id

            if audioEngine.isPlaybackActive {
                try executeTransition(
                    from: current,
                    to: target,
                    plan: matchingPlan,
                    clearPlanAfterStart: true
                )
                notice = matchingPlan == nil
                    ? "Crossfading to \(target.track.title)"
                    : "Executing AI mix plan"
            } else {
                try audioEngine.play(url: target.url, track: target.track)
                notice = "Playing \(target.track.title)"
            }
            clearCurrentMixPlan()
            requestAIMixPlanIfReady()
        } catch {
            notice = error.localizedDescription
        }
    }

    func executeTransition(
        from current: ImportedTrack,
        to target: ImportedTrack,
        plan: MixPlan?,
        clearPlanAfterStart: Bool
    ) throws {
        guard markTrackMissingIfUnavailable(target) else {
            throw NativePlaybackError.trackUnavailable(target.track.title)
        }

        let duration = plan.map {
            max(0.25, $0.transitionEndSec - $0.transitionStartSec)
        } ?? settings.fadeDurationSec
        let startOffset = plan?.nextTrackStartOffsetSec ?? 0
        selectedTrackID = target.id
        try audioEngine.crossfadeTo(
            url: target.url,
            track: target.track,
            durationSec: duration,
            startOffsetSec: startOffset
        ) { [weak self] in
            self?.notice = "Playing \(target.track.title)"
        }
        if clearPlanAfterStart {
            clearCurrentMixPlan()
        }
    }

    private func restoreSettings() {
        do {
            settings = try settingsStore.loadMigratingElectronSettingsIfNeeded()
            audioEngine.setMasterGain(settings.masterGain)
        } catch {
            settings = .defaults
            audioEngine.setMasterGain(settings.masterGain)
            notice = "Could not restore settings: \(error.localizedDescription)"
        }
    }

    private func persistSettings() {
        do {
            try settingsStore.save(settings)
        } catch {
            notice = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func updateSettings(
        invalidatesMixPlan: Bool,
        mutate: (inout PlayerSettings) -> Void
    ) {
        var next = settings
        mutate(&next)
        settings = NativeSettingsStore.sanitize(next)
        audioEngine.setMasterGain(settings.masterGain)
        if invalidatesMixPlan {
            clearCurrentMixPlan()
            requestAIMixPlanIfReady()
        }
        persistSettings()
    }

    var mixReviewArtifactFolderURL: URL? {
        var isDirectory: ObjCBool = false
        guard let path = settings.mixReviewArtifactFolderPath,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func updateMixReviewArtifactFolder(_ folderURL: URL) {
        updateSettings(invalidatesMixPlan: false) { settings in
            settings.mixReviewArtifactFolderPath = folderURL.path
        }
    }

}

struct PlannedMixPair: Equatable, Sendable {
    var currentTrackId: String
    var nextTrackId: String
}

struct PlannedMixReview: Equatable, Sendable {
    var pair: PlannedMixPair
    var source: String
    var fallbackReason: String?
    var selectionReason: String?
    var renderedQuality: RenderedTransitionQualityReport
    var shadowFallbackComparison: PlannedMixReviewPlanComparison?
}

struct AcceptedMixPlan: Equatable, Sendable {
    var plan: MixPlan
    var review: PlannedMixReview
}

struct PlannedMixReviewPlanComparison: Equatable, Sendable {
    var source: String
    var reason: String?
    var transitionStartSec: Double
    var transitionEndSec: Double
    var nextTrackStartOffsetSec: Double
    var style: MixStyle
    var confidence: Double
    var candidateId: String?
    var renderedQuality: RenderedTransitionQualityReport
}

struct PlannedMixReviewEvent: Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var pair: PlannedMixPair
    var source: String
    var fallbackReason: String?
    var selectionReason: String?
    var transitionStartSec: Double
    var transitionEndSec: Double
    var nextTrackStartOffsetSec: Double
    var style: MixStyle
    var confidence: Double
    var candidateId: String?
    var renderedQuality: RenderedTransitionQualityReport
    var shadowFallbackComparison: PlannedMixReviewPlanComparison?
}

struct ImportedMixReviewArtifact: Identifiable, Equatable, Sendable {
    var id: UUID
    var importedAt: Date
    var fileName: String
    var format: String
    var content: String
    var reviewCount: Int
    var schemaVersion: Int?
    var trackPairs: [MixReviewArtifactTrackPair]
    var pairDetails: [MixReviewArtifactPairDetail]
    var reviewAnnotation: String

    init(
        id: UUID,
        importedAt: Date,
        fileName: String,
        format: String,
        content: String,
        reviewCount: Int,
        schemaVersion: Int?,
        trackPairs: [MixReviewArtifactTrackPair] = [],
        pairDetails: [MixReviewArtifactPairDetail] = [],
        reviewAnnotation: String = ""
    ) {
        self.id = id
        self.importedAt = importedAt
        self.fileName = fileName
        self.format = format
        self.content = content
        self.reviewCount = reviewCount
        self.schemaVersion = schemaVersion
        self.trackPairs = trackPairs
        self.pairDetails = pairDetails
        self.reviewAnnotation = reviewAnnotation
    }

    init(persisted: PersistedMixReviewArtifact) {
        let extractedPairs = MixReviewArtifactPairExtractor.trackPairs(content: persisted.content)
        let pairDetails = MixReviewArtifactPairDetailExtractor.pairDetails(content: persisted.content)
        self.id = UUID(uuidString: persisted.id) ?? UUID()
        self.importedAt = ISO8601DateFormatter().date(from: persisted.importedAt) ?? Date()
        self.fileName = persisted.fileName
        self.format = persisted.format
        self.content = persisted.content
        self.reviewCount = persisted.reviewCount
        self.schemaVersion = persisted.schemaVersion
        self.trackPairs = persisted.trackPairs.isEmpty ? extractedPairs : persisted.trackPairs
        self.pairDetails = pairDetails
        self.reviewAnnotation = persisted.reviewAnnotation
    }

    var persisted: PersistedMixReviewArtifact {
        PersistedMixReviewArtifact(
            id: id.uuidString,
            importedAt: ISO8601DateFormatter().string(from: importedAt),
            fileName: fileName,
            format: format,
            content: content,
            reviewCount: reviewCount,
            schemaVersion: schemaVersion,
            trackPairs: trackPairs,
            reviewAnnotation: reviewAnnotation
        )
    }

    func matches(pair: PlannedMixPair) -> Bool {
        MixReviewArtifactPairFilter.matches(
            trackPairs: trackPairs,
            currentTrackId: pair.currentTrackId,
            nextTrackId: pair.nextTrackId
        )
    }

    func matches(searchText: String) -> Bool {
        MixReviewArtifactSearch.matches(
            fileName: fileName,
            format: format,
            reviewCount: reviewCount,
            trackPairs: trackPairs,
            content: content,
            annotation: reviewAnnotation,
            query: searchText
        )
    }
}

struct ImportedMixReviewArtifactComparison: Identifiable, Equatable, Sendable {
    var pair: PlannedMixPair
    var leftArtifact: ImportedMixReviewArtifact
    var rightArtifact: ImportedMixReviewArtifact
    var pairComparison: MixReviewArtifactPairComparison

    var id: String {
        [
            pair.currentTrackId,
            pair.nextTrackId,
            leftArtifact.id.uuidString,
            rightArtifact.id.uuidString
        ].joined(separator: "|")
    }
}

private enum NativePlaybackError: LocalizedError {
    case trackUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .trackUnavailable(let title):
            return "\(title) is missing. Rescan or relink the source folder."
        }
    }
}
