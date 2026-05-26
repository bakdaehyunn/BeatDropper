import Foundation

public enum AudioFormat: String, Codable, Sendable {
    case mp3
    case wav
}

public enum AIDJMode: String, Codable, CaseIterable, Sendable {
    case safe
    case balanced
    case adventurous
}

public struct Track: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var durationSec: Double
    public var format: AudioFormat
    public var bpm: Double?

    public init(
        id: String,
        title: String,
        durationSec: Double,
        format: AudioFormat,
        bpm: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.durationSec = durationSec
        self.format = format
        self.bpm = bpm
    }
}

public struct MusicLibraryTrack: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var durationSec: Double
    public var format: AudioFormat
    public var bpm: Double?
    public var addedAt: String
    public var updatedAt: String
    public var sourcePath: String
    public var sourceLabel: String
    public var missing: Bool
    public var missingAt: String?

    public init(
        id: String,
        title: String,
        durationSec: Double,
        format: AudioFormat,
        bpm: Double? = nil,
        addedAt: String,
        updatedAt: String,
        sourcePath: String,
        sourceLabel: String,
        missing: Bool,
        missingAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.durationSec = durationSec
        self.format = format
        self.bpm = bpm
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.sourcePath = sourcePath
        self.sourceLabel = sourceLabel
        self.missing = missing
        self.missingAt = missingAt
    }
}

public struct UserPlaylist: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var trackIds: [String]
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        name: String,
        trackIds: [String],
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.trackIds = trackIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AIAgentProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public var command: String
    public var args: [String]
    public var timeoutMs: Double
    public var enabled: Bool

    public init(
        id: String,
        name: String,
        kind: String,
        command: String,
        args: [String],
        timeoutMs: Double,
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.command = command
        self.args = args
        self.timeoutMs = timeoutMs
        self.enabled = enabled
    }
}

public struct PlayerSettings: Codable, Hashable, Sendable {
    public static let codexAgentProfileId = "codex"

    public static let defaultCodexAgentProfile = AIAgentProfile(
        id: codexAgentProfileId,
        name: "Codex",
        kind: "cli",
        command: "node",
        args: ["scripts/codex-mix-planner.cjs"],
        timeoutMs: 20_000,
        enabled: true
    )

    public static let defaults = PlayerSettings()

    public var fadeDurationSec: Double
    public var masterGain: Double
    public var predecodeLeadSec: Double
    public var repeatAll: Bool
    public var decodeTimeoutDurationWeightMs: Double
    public var decodeTimeoutSizeWeightMs: Double
    public var aiDjEnabled: Bool
    public var aiDjMode: AIDJMode
    public var aiAgentProfiles: [AIAgentProfile]
    public var activeAiAgentProfileId: String
    public var plannerCommand: String
    public var plannerArgs: [String]
    public var plannerTimeoutMs: Double

    public init(
        fadeDurationSec: Double = 8,
        masterGain: Double = 0.9,
        predecodeLeadSec: Double = 20,
        repeatAll: Bool = true,
        decodeTimeoutDurationWeightMs: Double = 20,
        decodeTimeoutSizeWeightMs: Double = 200,
        aiDjEnabled: Bool = false,
        aiDjMode: AIDJMode = .safe,
        aiAgentProfiles: [AIAgentProfile] = [PlayerSettings.defaultCodexAgentProfile],
        activeAiAgentProfileId: String = "codex",
        plannerCommand: String = "node",
        plannerArgs: [String] = ["scripts/codex-mix-planner.cjs"],
        plannerTimeoutMs: Double = 20_000
    ) {
        self.fadeDurationSec = fadeDurationSec
        self.masterGain = masterGain
        self.predecodeLeadSec = predecodeLeadSec
        self.repeatAll = repeatAll
        self.decodeTimeoutDurationWeightMs = decodeTimeoutDurationWeightMs
        self.decodeTimeoutSizeWeightMs = decodeTimeoutSizeWeightMs
        self.aiDjEnabled = aiDjEnabled
        self.aiDjMode = aiDjMode
        self.aiAgentProfiles = aiAgentProfiles
        self.activeAiAgentProfileId = activeAiAgentProfileId
        self.plannerCommand = plannerCommand
        self.plannerArgs = plannerArgs
        self.plannerTimeoutMs = plannerTimeoutMs
    }
}
