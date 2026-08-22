import BeatDropperDomain
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperReview
import Combine
import Foundation

@MainActor
public protocol AudioPlayback: AnyObject {
    var session: PlaybackSessionState { get }
    var sessionPublisher: AnyPublisher<PlaybackSessionState, Never> { get }
    func prepareSession(currentTrack: Track?, queuedTrack: Track?)
    func setMasterGain(_ gain: Double)
    func loadPrimary(url: URL, track: Track) throws
    func play(url: URL, track: Track) throws
    func playPreview(url: URL, track: Track, startOffsetSec: TimeInterval) throws
    func play() throws
    func resume() throws
    func crossfadeTo(
        url: URL,
        track: Track,
        durationSec: TimeInterval,
        startOffsetSec: TimeInterval,
        plan: MixPlan?,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?,
        completion: @escaping () -> Void
    ) throws
    func pause()
    func stop()
}

public extension AudioPlayback {
    func crossfadeTo(
        url: URL,
        track: Track,
        durationSec: TimeInterval,
        startOffsetSec: TimeInterval = 0,
        plan: MixPlan? = nil,
        currentAnalysis: TrackAnalysis? = nil,
        nextAnalysis: TrackAnalysis? = nil
    ) throws {
        try crossfadeTo(
            url: url,
            track: track,
            durationSec: durationSec,
            startOffsetSec: startOffsetSec,
            plan: plan,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis,
            completion: {}
        )
    }
}

@MainActor public protocol AudioPlaybackAutomation: AnyObject {
    func simulateConfigurationChangeRecoveryForAutomation()
}

public protocol LibraryRepository: Sendable {
    func loadMigratingLegacyDesktopStateIfNeeded() throws -> NativeLibraryState
    func save(_ state: NativeLibraryState) throws
}

public protocol SettingsRepository: Sendable {
    func loadMigratingLegacyDesktopSettingsIfNeeded() throws -> PlayerSettings
    func save(_ settings: PlayerSettings) throws
}

public protocol TrackAnalysisRepository: Sendable {
    func read(trackId: String) throws -> TrackAnalysis?
    @discardableResult func write(_ analysis: TrackAnalysis) throws -> TrackAnalysis
}

public protocol TrackAnalyzing: Sendable {
    func analyze(track: Track, url: URL) async throws -> TrackAnalysis
    func currentFileRevision(for url: URL) throws -> TrackFileRevision
}

public protocol MixReviewRepository: Sendable {
    func load() throws -> MixReviewArtifactState
    func save(_ state: MixReviewArtifactState) throws
}

public protocol MixPlanning: Sendable {
    func requestMixPlan(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        timeoutSec: TimeInterval
    ) async -> NativeMixPlannerResult
}

public protocol FileAvailabilityChecking: Sendable {
    func fileExists(at url: URL) -> Bool
}

public protocol TrackAvailabilityChecking: FileAvailabilityChecking, Sendable {
    func fileSize(at url: URL) -> Int64
}

public protocol TrackImporting: TrackAvailabilityChecking, Sendable {
    @MainActor func openAudioFiles() -> [URL]
    @MainActor func openReplacementAudioFile() -> URL?
    @MainActor func openMusicFolder() -> URL?
    func importTracks(from urls: [URL]) async -> [ImportedTrack]
    func importFolder(_ folderURL: URL) async -> [ImportedTrack]
    func classifyOpenURLs(_ urls: [URL]) -> NativeOpenImportSelection
    func importTrack(from url: URL) async -> ImportedTrack?
}

public protocol AppClock: Sendable { var now: Date { get } }
@MainActor public protocol AppSchedule: AnyObject { func cancel() }
@MainActor public protocol AppScheduling: AnyObject {
    func scheduleRepeating(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> any AppSchedule
}
