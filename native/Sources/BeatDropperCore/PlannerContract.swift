import Foundation

public let plannerSchemaVersion = 1

public struct PlannerTrackSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var durationSec: Double
    public var bpm: Double?

    public init(id: String, title: String, durationSec: Double, bpm: Double?) {
        self.id = id
        self.title = title
        self.durationSec = durationSec
        self.bpm = bpm
    }
}

public struct PlannerPlaybackSnapshot: Codable, Hashable, Sendable {
    public var elapsedSec: Double
    public var remainingSec: Double

    public init(elapsedSec: Double, remainingSec: Double) {
        self.elapsedSec = elapsedSec
        self.remainingSec = remainingSec
    }
}

public struct PlannerSettingsSnapshot: Codable, Hashable, Sendable {
    public var fadeDurationSec: Double
    public var aiDjMode: AIDJMode

    public init(fadeDurationSec: Double, aiDjMode: AIDJMode) {
        self.fadeDurationSec = fadeDurationSec
        self.aiDjMode = aiDjMode
    }
}

public struct PlannerAnalysisPair: Codable, Hashable, Sendable {
    public var current: TrackAnalysis?
    public var next: TrackAnalysis?

    public init(current: TrackAnalysis?, next: TrackAnalysis?) {
        self.current = current
        self.next = next
    }
}

public struct PlannerRequest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var currentTrack: PlannerTrackSnapshot
    public var nextTrack: PlannerTrackSnapshot
    public var currentPlayback: PlannerPlaybackSnapshot
    public var analysis: PlannerAnalysisPair
    public var analysisSummary: PlannerAnalysisSummary?
    public var pairContext: MixPairContext?
    public var settings: PlannerSettingsSnapshot

    public init(
        schemaVersion: Int = plannerSchemaVersion,
        currentTrack: PlannerTrackSnapshot,
        nextTrack: PlannerTrackSnapshot,
        currentPlayback: PlannerPlaybackSnapshot,
        analysis: PlannerAnalysisPair,
        analysisSummary: PlannerAnalysisSummary? = nil,
        pairContext: MixPairContext? = nil,
        settings: PlannerSettingsSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.currentTrack = currentTrack
        self.nextTrack = nextTrack
        self.currentPlayback = currentPlayback
        self.analysis = analysis
        self.analysisSummary = analysisSummary
        self.pairContext = pairContext
        self.settings = settings
    }
}

public struct PlannerResponse: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var mixPlan: MixPlan?
    public var error: String?

    public init(
        schemaVersion: Int = plannerSchemaVersion,
        mixPlan: MixPlan?,
        error: String?
    ) {
        self.schemaVersion = schemaVersion
        self.mixPlan = mixPlan
        self.error = error
    }
}

public enum PlannerRequestBuilder {
    public static func build(
        currentTrack: Track,
        nextTrack: Track,
        elapsedSec: Double,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?,
        settings: PlannerSettingsSnapshot
    ) -> PlannerRequest {
        let safeElapsed = min(max(0, elapsedSec.isFinite ? elapsedSec : 0), max(0, currentTrack.durationSec))
        return PlannerRequest(
            currentTrack: PlannerTrackSnapshot(track: currentTrack),
            nextTrack: PlannerTrackSnapshot(track: nextTrack),
            currentPlayback: PlannerPlaybackSnapshot(
                elapsedSec: safeElapsed,
                remainingSec: max(0, currentTrack.durationSec - safeElapsed)
            ),
            analysis: PlannerAnalysisPair(current: currentAnalysis, next: nextAnalysis),
            analysisSummary: PlannerEvidenceBuilder.buildPlannerAnalysisSummary(
                currentTrack: currentTrack,
                nextTrack: nextTrack,
                currentAnalysis: currentAnalysis,
                nextAnalysis: nextAnalysis
            ),
            pairContext: PlannerEvidenceBuilder.buildMixPairContext(
                currentTrack: currentTrack,
                nextTrack: nextTrack,
                currentAnalysis: currentAnalysis,
                nextAnalysis: nextAnalysis
            ),
            settings: settings
        )
    }
}

public extension PlannerTrackSnapshot {
    init(track: Track) {
        self.init(
            id: track.id,
            title: track.title,
            durationSec: track.durationSec,
            bpm: track.bpm?.isFinite == true ? track.bpm : nil
        )
    }
}
