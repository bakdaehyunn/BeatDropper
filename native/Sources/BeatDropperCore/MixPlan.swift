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

public enum TransitionTimingSource: String, Codable, Sendable {
    case beatGrid = "beat_grid"
    case secondsFallback = "seconds_fallback"
}

public struct MixTempoSyncPlan: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var targetRate: Double?

    public init(enabled: Bool, targetRate: Double?) {
        self.enabled = enabled
        self.targetRate = targetRate
    }
}

public enum MixFilterMode: String, Codable, Sendable {
    case disabled
    case lowPass = "low_pass"
    case highPass = "high_pass"
}

public enum MixClipProtectionMode: String, Codable, Sendable {
    case monitorOnly = "monitor_only"
    case softLimit = "soft_limit"
}

public struct MixGainPlan: Codable, Hashable, Sendable {
    public var outgoingTrimDb: Double?
    public var incomingTrimDb: Double?

    public static let conservativeDefaults = MixGainPlan(outgoingTrimDb: 0, incomingTrimDb: 0)

    public init(outgoingTrimDb: Double? = nil, incomingTrimDb: Double? = nil) {
        self.outgoingTrimDb = outgoingTrimDb
        self.incomingTrimDb = incomingTrimDb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outgoingTrimDb = try container.decodeIfPresent(Double.self, forKey: .outgoingTrimDb)
        incomingTrimDb = try container.decodeIfPresent(Double.self, forKey: .incomingTrimDb)
    }
}

public struct MixThreeBandEQPlan: Codable, Hashable, Sendable {
    public var outgoingLowDb: Double?
    public var outgoingMidDb: Double?
    public var outgoingHighDb: Double?
    public var incomingLowDb: Double?
    public var incomingMidDb: Double?
    public var incomingHighDb: Double?

    public static let conservativeDefaults = MixThreeBandEQPlan(
        outgoingLowDb: 0,
        outgoingMidDb: 0,
        outgoingHighDb: 0,
        incomingLowDb: 0,
        incomingMidDb: 0,
        incomingHighDb: 0
    )

    public init(
        outgoingLowDb: Double? = nil,
        outgoingMidDb: Double? = nil,
        outgoingHighDb: Double? = nil,
        incomingLowDb: Double? = nil,
        incomingMidDb: Double? = nil,
        incomingHighDb: Double? = nil
    ) {
        self.outgoingLowDb = outgoingLowDb
        self.outgoingMidDb = outgoingMidDb
        self.outgoingHighDb = outgoingHighDb
        self.incomingLowDb = incomingLowDb
        self.incomingMidDb = incomingMidDb
        self.incomingHighDb = incomingHighDb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outgoingLowDb = try container.decodeIfPresent(Double.self, forKey: .outgoingLowDb)
        outgoingMidDb = try container.decodeIfPresent(Double.self, forKey: .outgoingMidDb)
        outgoingHighDb = try container.decodeIfPresent(Double.self, forKey: .outgoingHighDb)
        incomingLowDb = try container.decodeIfPresent(Double.self, forKey: .incomingLowDb)
        incomingMidDb = try container.decodeIfPresent(Double.self, forKey: .incomingMidDb)
        incomingHighDb = try container.decodeIfPresent(Double.self, forKey: .incomingHighDb)
    }
}

public struct MixFilterPlan: Codable, Hashable, Sendable {
    public var outgoingMode: MixFilterMode
    public var outgoingStartHz: Double?
    public var outgoingEndHz: Double?
    public var incomingMode: MixFilterMode
    public var incomingStartHz: Double?
    public var incomingEndHz: Double?

    public static let conservativeDefaults = MixFilterPlan(
        outgoingMode: .disabled,
        outgoingStartHz: nil,
        outgoingEndHz: nil,
        incomingMode: .disabled,
        incomingStartHz: nil,
        incomingEndHz: nil
    )

    public init(
        outgoingMode: MixFilterMode = .disabled,
        outgoingStartHz: Double? = nil,
        outgoingEndHz: Double? = nil,
        incomingMode: MixFilterMode = .disabled,
        incomingStartHz: Double? = nil,
        incomingEndHz: Double? = nil
    ) {
        self.outgoingMode = outgoingMode
        self.outgoingStartHz = outgoingStartHz
        self.outgoingEndHz = outgoingEndHz
        self.incomingMode = incomingMode
        self.incomingStartHz = incomingStartHz
        self.incomingEndHz = incomingEndHz
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outgoingMode = try container.decodeIfPresent(MixFilterMode.self, forKey: .outgoingMode) ?? .disabled
        outgoingStartHz = try container.decodeIfPresent(Double.self, forKey: .outgoingStartHz)
        outgoingEndHz = try container.decodeIfPresent(Double.self, forKey: .outgoingEndHz)
        incomingMode = try container.decodeIfPresent(MixFilterMode.self, forKey: .incomingMode) ?? .disabled
        incomingStartHz = try container.decodeIfPresent(Double.self, forKey: .incomingStartHz)
        incomingEndHz = try container.decodeIfPresent(Double.self, forKey: .incomingEndHz)
    }
}

public struct MixLoudnessPlan: Codable, Hashable, Sendable {
    public var targetIntegratedLufs: Double?
    public var maxPeakDb: Double?

    public static let conservativeDefaults = MixLoudnessPlan(
        targetIntegratedLufs: nil,
        maxPeakDb: -1
    )

    public init(targetIntegratedLufs: Double? = nil, maxPeakDb: Double? = nil) {
        self.targetIntegratedLufs = targetIntegratedLufs
        self.maxPeakDb = maxPeakDb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetIntegratedLufs = try container.decodeIfPresent(Double.self, forKey: .targetIntegratedLufs)
        maxPeakDb = try container.decodeIfPresent(Double.self, forKey: .maxPeakDb)
    }
}

public struct MixClipProtectionPlan: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var mode: MixClipProtectionMode
    public var ceilingDb: Double?

    public static let conservativeDefaults = MixClipProtectionPlan(
        enabled: true,
        mode: .monitorOnly,
        ceilingDb: -1
    )

    public init(
        enabled: Bool = true,
        mode: MixClipProtectionMode = .monitorOnly,
        ceilingDb: Double? = nil
    ) {
        self.enabled = enabled
        self.mode = mode
        self.ceilingDb = ceilingDb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        mode = try container.decodeIfPresent(MixClipProtectionMode.self, forKey: .mode) ?? .monitorOnly
        ceilingDb = try container.decodeIfPresent(Double.self, forKey: .ceilingDb)
    }
}

public struct MixControlPlan: Codable, Hashable, Sendable {
    public var gain: MixGainPlan
    public var eq: MixThreeBandEQPlan
    public var filter: MixFilterPlan
    public var loudness: MixLoudnessPlan
    public var clipProtection: MixClipProtectionPlan
    public var qualityNotes: [String]

    public static let conservativeDefaults = MixControlPlan(
        gain: .conservativeDefaults,
        eq: .conservativeDefaults,
        filter: .conservativeDefaults,
        loudness: .conservativeDefaults,
        clipProtection: .conservativeDefaults,
        qualityNotes: ["conservative runtime DSP defaults"]
    )

    public init(
        gain: MixGainPlan = .conservativeDefaults,
        eq: MixThreeBandEQPlan = .conservativeDefaults,
        filter: MixFilterPlan = .conservativeDefaults,
        loudness: MixLoudnessPlan = .conservativeDefaults,
        clipProtection: MixClipProtectionPlan = .conservativeDefaults,
        qualityNotes: [String] = []
    ) {
        self.gain = gain
        self.eq = eq
        self.filter = filter
        self.loudness = loudness
        self.clipProtection = clipProtection
        self.qualityNotes = qualityNotes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gain = try container.decodeIfPresent(MixGainPlan.self, forKey: .gain) ?? .conservativeDefaults
        eq = try container.decodeIfPresent(MixThreeBandEQPlan.self, forKey: .eq) ?? .conservativeDefaults
        filter = try container.decodeIfPresent(MixFilterPlan.self, forKey: .filter) ?? .conservativeDefaults
        loudness = try container.decodeIfPresent(MixLoudnessPlan.self, forKey: .loudness) ?? .conservativeDefaults
        clipProtection = try container.decodeIfPresent(MixClipProtectionPlan.self, forKey: .clipProtection) ?? .conservativeDefaults
        qualityNotes = try container.decodeIfPresent([String].self, forKey: .qualityNotes) ?? []
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
    public var mixControls: MixControlPlan?
    public var transitionBarCount: Int?
    public var transitionTimingSource: TransitionTimingSource?
    public var synchronizedBPM: Double?

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
        evidence: [String] = [],
        mixControls: MixControlPlan? = nil,
        transitionBarCount: Int? = nil,
        transitionTimingSource: TransitionTimingSource? = nil,
        synchronizedBPM: Double? = nil
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
        self.mixControls = mixControls
        self.transitionBarCount = transitionBarCount
        self.transitionTimingSource = transitionTimingSource
        self.synchronizedBPM = synchronizedBPM
    }
}
