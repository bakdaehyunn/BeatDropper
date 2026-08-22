import BeatDropperApplication
import Foundation

@MainActor
final class LibraryFeatureController: LibraryFeatureActionHandling {
    let library: LibraryFeature
    private let creative: CreativeFeature
    let playing: PlayingFeature
    private let shell: AppShellFeature
    let store: any LibraryRepository
    let analysisStore: any TrackAnalysisRepository
    let trackImporter: any TrackImporting
    let trackAnalyzer: any TrackAnalyzing
    let clock: any AppClock

    private var clearMixPlanAction: () -> Void = {}
    private var stopMixPlanSchedulerAction: () -> Void = {}
    private var synchronizeAIMixAction: () -> Void = {}
    private var requestAIMixPlanAction: () -> Void = {}
    private var currentMixPlanPairProvider: () -> PlannedMixPair? = { nil }
    private var setAIMixEnabledAction: (Bool) -> Void = { _ in }

    init(
        library: LibraryFeature,
        creative: CreativeFeature,
        playing: PlayingFeature,
        shell: AppShellFeature,
        store: any LibraryRepository,
        analysisStore: any TrackAnalysisRepository,
        trackImporter: any TrackImporting,
        trackAnalyzer: any TrackAnalyzing,
        clock: any AppClock
    ) {
        self.library = library
        self.creative = creative
        self.playing = playing
        self.shell = shell
        self.store = store
        self.analysisStore = analysisStore
        self.trackImporter = trackImporter
        self.trackAnalyzer = trackAnalyzer
        self.clock = clock
    }

    func configureCoordination(
        clearMixPlan: @escaping () -> Void,
        stopMixPlanScheduler: @escaping () -> Void,
        synchronizeAIMix: @escaping () -> Void,
        requestAIMixPlan: @escaping () -> Void,
        currentMixPlanPair: @escaping () -> PlannedMixPair?,
        setAIMixEnabled: @escaping (Bool) -> Void
    ) {
        clearMixPlanAction = clearMixPlan
        stopMixPlanSchedulerAction = stopMixPlanScheduler
        synchronizeAIMixAction = synchronizeAIMix
        requestAIMixPlanAction = requestAIMixPlan
        currentMixPlanPairProvider = currentMixPlanPair
        setAIMixEnabledAction = setAIMixEnabled
    }

    var playlist: [ImportedTrack] {
        get { library.playlist }
        set {
            library.playlist = newValue
            synchronizePreparedPlaybackSessionIfIdle()
        }
    }

    var libraryRecords: [NativeTrackRecord] {
        get { library.records }
        set {
            library.records = newValue
            library.rebuildBrowserIndex()
        }
    }

    var librarySourceFolders: [NativeLibrarySourceFolder] {
        get { library.sourceFolders }
        set {
            library.sourceFolders = newValue
            library.rebuildBrowserIndex()
        }
    }

    var userPlaylists: [UserPlaylist] {
        get { library.userPlaylists }
        set { library.userPlaylists = newValue }
    }

    var trackAnalysesById: [String: TrackAnalysis] {
        get { library.analysesByTrackID }
        set { library.analysesByTrackID = newValue }
    }

    var analyzingTrackIds: Set<String> {
        get { library.analyzingTrackIDs }
        set { library.analyzingTrackIDs = newValue }
    }

    var queuedAnalysisTrackCount: Int {
        get { library.queuedAnalysisTrackCount }
        set { library.queuedAnalysisTrackCount = newValue }
    }

    var runningAnalysisTrackCount: Int {
        get { library.runningAnalysisTrackCount }
        set { library.runningAnalysisTrackCount = newValue }
    }

    var selectedTrackID: ImportedTrack.ID? {
        get { library.selectedTrackID }
        set {
            library.selectedTrackID = newValue
            if let newValue { creativePreparationTrackID = newValue }
            synchronizePreparedPlaybackSessionIfIdle()
        }
    }

    var selectedUserPlaylistId: String {
        get { library.selectedUserPlaylistID }
        set { library.selectedUserPlaylistID = newValue }
    }

    var userPlaylistNameDraft: String {
        get { library.userPlaylistNameDraft }
        set { library.userPlaylistNameDraft = newValue }
    }

    var maxConcurrentAnalysisTasks: Int { library.maxConcurrentAnalysisTasks }
    var analysisQueueState: NativeAnalysisQueueState {
        get { library.analysisQueueState }
        set { library.analysisQueueState = newValue }
    }
    var queuedAnalysisTracksById: [String: ImportedTrack] {
        get { library.queuedAnalysisTracksByID }
        set { library.queuedAnalysisTracksByID = newValue }
    }

    var notice: String {
        get { shell.notice }
        set { shell.notice = newValue }
    }

    private var creativePreparationTrackID: ImportedTrack.ID? {
        get { creative.preparationTrackID }
        set {
            guard creative.preparationTrackID != newValue else { return }
            creative.preparationTrackID = newValue
            creative.previewPositionSec = 0
            creative.bpmTapDates.removeAll()
            creative.bpmTapEstimate = nil
            creative.bpmTapCount = 0
        }
    }

    var currentMixPlanPair: PlannedMixPair? { currentMixPlanPairProvider() }
    var isAIMixEnabled: Bool {
        get { false }
        set { setAIMixEnabledAction(newValue) }
    }

    func clearCurrentMixPlan() { clearMixPlanAction() }
    func stopMixPlanScheduler() { stopMixPlanSchedulerAction() }
    func syncAIMixAfterPlaylistMutation() { synchronizeAIMixAction() }
    func requestAIMixPlanIfReady() { requestAIMixPlanAction() }

    func synchronizePreparedPlaybackSessionIfIdle() {
        guard playing.session.mode == .idle else { return }
        playing.prepare(
            currentTrack: library.selectedTrack?.track,
            queuedTrack: library.nextAvailableTrack?.track
        )
    }

    func selectPlaylistTrack(_ trackID: ImportedTrack.ID?) {
        selectedTrackID = trackID
    }

    func selectLibraryTrack(_ trackID: ImportedTrack.ID?) {
        library.selectedLibraryTrackID = trackID
        if let trackID { creativePreparationTrackID = trackID }
    }

    func updatePreparation(forTrackID trackID: String, mutate: (inout TrackPreparation) -> Void) {
        guard let index = libraryRecords.firstIndex(where: { $0.id == trackID }) else {
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
}
