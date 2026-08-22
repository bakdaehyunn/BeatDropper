import BeatDropperDomain
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperReview
import Combine
import Foundation

public enum NativeWorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case playing = "Playing"
    case creative = "Creative"
    public var id: String { rawValue }
}

@MainActor
public final class PlayingFeature: ObservableObject {
    @Published public private(set) var session: PlaybackSessionState
    private let audioPlayback: any AudioPlayback
    private var sessionCancellable: AnyCancellable?

    public init(audioPlayback: any AudioPlayback) {
        self.audioPlayback = audioPlayback
        self.session = audioPlayback.session
        self.sessionCancellable = audioPlayback.sessionPublisher
            .removeDuplicates()
            .sink { [weak self] session in self?.session = session }
    }

    public func setMasterGain(_ gain: Double) { audioPlayback.setMasterGain(gain) }
    public func prepare(currentTrack: Track?, queuedTrack: Track?) {
        audioPlayback.prepareSession(currentTrack: currentTrack, queuedTrack: queuedTrack)
    }
    public func loadPrimary(url: URL, track: Track) throws { try audioPlayback.loadPrimary(url: url, track: track) }
    public func play(url: URL, track: Track) throws { try audioPlayback.play(url: url, track: track) }
    public func playPreview(url: URL, track: Track, startOffsetSec: TimeInterval) throws {
        try audioPlayback.playPreview(url: url, track: track, startOffsetSec: startOffsetSec)
    }
    public func play() throws { try audioPlayback.play() }
    public func resume() throws { try audioPlayback.resume() }
    public func pause() { audioPlayback.pause() }
    public func stop() { audioPlayback.stop() }
    public func crossfadeTo(
        url: URL,
        track: Track,
        durationSec: TimeInterval,
        startOffsetSec: TimeInterval = 0,
        plan: MixPlan? = nil,
        currentAnalysis: TrackAnalysis? = nil,
        nextAnalysis: TrackAnalysis? = nil,
        completion: @escaping () -> Void = {}
    ) throws {
        try audioPlayback.crossfadeTo(
            url: url,
            track: track,
            durationSec: durationSec,
            startOffsetSec: startOffsetSec,
            plan: plan,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis,
            completion: completion
        )
    }

    public func simulateConfigurationRecoveryForTesting() {
        (audioPlayback as? any AudioPlaybackAutomation)?.simulateConfigurationChangeRecoveryForAutomation()
    }
}

@MainActor
public final class LibraryFeature: ObservableObject {
    @Published public var playlist: [ImportedTrack] = []
    @Published public var records: [NativeTrackRecord] = []
    @Published public var sourceFolders: [NativeLibrarySourceFolder] = []
    @Published public var userPlaylists: [UserPlaylist] = []
    @Published public var analysesByTrackID: [String: TrackAnalysis] = [:]
    @Published public var analyzingTrackIDs: Set<String> = []
    @Published public var queuedAnalysisTrackCount = 0
    @Published public var runningAnalysisTrackCount = 0
    @Published public var browserTracks: [NativeLibraryBrowserTrack] = []
    @Published public var filteredBrowserTracks: [NativeLibraryBrowserTrack] = []
    @Published public var selectedTrackID: ImportedTrack.ID?
    @Published public var selectedLibraryTrackID: ImportedTrack.ID?
    @Published public var selectedUserPlaylistID = ""
    @Published public var userPlaylistNameDraft = ""
    @Published public var searchText = ""
    public var analysisQueueState = NativeAnalysisQueueState()
    public var queuedAnalysisTracksByID: [String: ImportedTrack] = [:]
    public let maxConcurrentAnalysisTasks = NativeAnalysisQueueState.recommendedConcurrency(
        activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
    )
    private let trackAvailability: any TrackAvailabilityChecking

    public init(trackAvailability: any TrackAvailabilityChecking) {
        self.trackAvailability = trackAvailability
    }

    public func isAvailable(_ track: ImportedTrack) -> Bool {
        !track.missing && trackAvailability.fileExists(at: track.url)
    }

    public func rebuildBrowserIndex() {
        browserTracks = NativeLibraryBrowserIndex.build(records: records, sourceFolders: sourceFolders)
        applySearchFilter()
    }

    public func updateSearchText(_ text: String) {
        searchText = text
        applySearchFilter()
    }

    public func applySearchFilter() {
        filteredBrowserTracks = NativeLibraryBrowserIndex.filter(browserTracks, query: searchText)
        if let selectedLibraryTrackID,
           !browserTracks.contains(where: { $0.id == selectedLibraryTrackID }) {
            self.selectedLibraryTrackID = nil
        }
    }
}

@MainActor
public final class CreativeFeature: ObservableObject {
    @Published public var preparationTrackID: ImportedTrack.ID?
    @Published public var previewPositionSec: Double = 0
    @Published public var bpmTapEstimate: Double?
    @Published public var bpmTapCount = 0
    public var bpmTapDates: [Date] = []
    public init() {}
}

@MainActor
public final class MixPlanningFeature: ObservableObject {
    @Published public var currentPlan: MixPlan?
    @Published public var currentPair: PlannedMixPair?
    @Published public var currentReview: PlannedMixReview?
    @Published public var isPlanning = false
    @Published public var status = "No AI mix plan"
    @Published public var isEnabled = false
    @Published public var scheduledCountdownSec: Double?
    @Published public var isManualTransitionScheduled = false
    public var schedule: (any AppSchedule)?
    public var isExecutingScheduledMix = false
    public var activeRequestID: UUID?

    public init() {}
}

@MainActor
public final class MixReviewFeature: ObservableObject {
    @Published public var recentEvents: [PlannedMixReviewEvent] = []
    @Published public var importedArtifacts: [ImportedMixReviewArtifact] = []
    @Published public var isPairFilterEnabled = false
    @Published public var searchText = ""
    @Published public var selectedComparisonArtifactIDs: [ImportedMixReviewArtifact.ID] = []

    public init() {}
}

@MainActor
public final class AppNavigation: ObservableObject {
    @Published public var workspaceMode: NativeWorkspaceMode = .playing
    @Published public var isInspectorVisible = false
    @Published public var isLibraryBrowserVisible = true
    public init() {}
}

@MainActor
public final class AppShellFeature: ObservableObject {
    @Published public var settings: PlayerSettings = .defaults
    @Published public var notice = "Ready"

    public init() {}

    public func presentNotice(_ notice: String) {
        self.notice = notice
    }
}
