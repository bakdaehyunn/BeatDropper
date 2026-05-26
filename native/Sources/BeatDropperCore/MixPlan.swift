import Foundation

public enum MixStyle: String, Codable, Sendable {
    case smoothBlend = "smooth_blend"
    case energySwap = "energy_swap"
    case hardCut = "hard_cut"
}

public enum PhraseAlignment: String, Codable, Sendable {
    case aligned
    case near
    case free
}

public enum EnergyStrategy: String, Codable, Sendable {
    case lift
    case maintain
    case drop
}

public struct MixTempoSyncPlan: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var targetRate: Double?

    public init(enabled: Bool, targetRate: Double?) {
        self.enabled = enabled
        self.targetRate = targetRate
    }
}

public struct MixPlan: Codable, Hashable, Sendable {
    public var transitionStartSec: Double
    public var transitionEndSec: Double
    public var nextTrackStartOffsetSec: Double
    public var style: MixStyle
    public var confidence: Double
    public var reasoningSummary: String?
    public var tempoSync: MixTempoSyncPlan
    public var candidateId: String?
    public var currentBarIndex: Int?
    public var nextBarIndex: Int?
    public var phraseAlignment: PhraseAlignment?
    public var energyStrategy: EnergyStrategy?
    public var evidence: [String]

    public init(
        transitionStartSec: Double,
        transitionEndSec: Double,
        nextTrackStartOffsetSec: Double,
        style: MixStyle,
        confidence: Double,
        reasoningSummary: String?,
        tempoSync: MixTempoSyncPlan,
        candidateId: String? = nil,
        currentBarIndex: Int? = nil,
        nextBarIndex: Int? = nil,
        phraseAlignment: PhraseAlignment? = nil,
        energyStrategy: EnergyStrategy? = nil,
        evidence: [String] = []
    ) {
        self.transitionStartSec = transitionStartSec
        self.transitionEndSec = transitionEndSec
        self.nextTrackStartOffsetSec = nextTrackStartOffsetSec
        self.style = style
        self.confidence = confidence
        self.reasoningSummary = reasoningSummary
        self.tempoSync = tempoSync
        self.candidateId = candidateId
        self.currentBarIndex = currentBarIndex
        self.nextBarIndex = nextBarIndex
        self.phraseAlignment = phraseAlignment
        self.energyStrategy = energyStrategy
        self.evidence = evidence
    }
}
