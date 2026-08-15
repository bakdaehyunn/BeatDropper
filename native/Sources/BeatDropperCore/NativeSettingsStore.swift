import Foundation

public final class NativeSettingsStore: @unchecked Sendable {
    public let fileURL: URL
    public var backupFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("backup.json")
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport(
        appFolderName: String = "BeatDropper",
        filename: String = "native-settings.json",
        fileManager: FileManager = .default
    ) -> NativeSettingsStore {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return NativeSettingsStore(
            fileURL: baseURL
                .appendingPathComponent(appFolderName, isDirectory: true)
                .appendingPathComponent(filename)
        )
    }

    public func load() throws -> PlayerSettings {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.fileExists(atPath: backupFileURL.path) else {
                return .defaults
            }
            return try loadSettings(at: backupFileURL)
        }

        do {
            return try loadSettings(at: fileURL)
        } catch {
            guard FileManager.default.fileExists(atPath: backupFileURL.path) else {
                throw error
            }
            return try loadSettings(at: backupFileURL)
        }
    }

    public func loadMigratingLegacyDesktopSettingsIfNeeded() throws -> PlayerSettings {
        if FileManager.default.fileExists(atPath: fileURL.path) ||
            FileManager.default.fileExists(atPath: backupFileURL.path) {
            return try load()
        }

        let legacySettingsURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("player-settings.json")
        guard FileManager.default.fileExists(atPath: legacySettingsURL.path) else {
            return .defaults
        }

        let settings = try Self.sanitize(data: Data(contentsOf: legacySettingsURL))
        try save(settings)
        return settings
    }

    public func save(_ settings: PlayerSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(Self.sanitize(settings))
        try data.write(to: fileURL, options: [.atomic])
        try writeCurrentSettingsBackup()
    }

    private func loadSettings(at url: URL) throws -> PlayerSettings {
        try Self.sanitize(data: Data(contentsOf: url))
    }

    private func writeCurrentSettingsBackup() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        let temporaryBackupURL = backupFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(backupFileURL.lastPathComponent).\(UUID().uuidString).tmp")
        try FileManager.default.copyItem(at: fileURL, to: temporaryBackupURL)
        if FileManager.default.fileExists(atPath: backupFileURL.path) {
            _ = try FileManager.default.replaceItemAt(
                backupFileURL,
                withItemAt: temporaryBackupURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: temporaryBackupURL, to: backupFileURL)
        }
    }

    public static func sanitize(_ settings: PlayerSettings) -> PlayerSettings {
        PlayerSettings(
            fadeDurationSec: clamp(settings.fadeDurationSec, min: 2, max: 20),
            masterGain: clamp(settings.masterGain, min: 0, max: 1),
            predecodeLeadSec: clamp(settings.predecodeLeadSec, min: 3, max: 40),
            repeatAll: settings.repeatAll,
            decodeTimeoutDurationWeightMs: clamp(settings.decodeTimeoutDurationWeightMs, min: 0, max: 80),
            decodeTimeoutSizeWeightMs: clamp(settings.decodeTimeoutSizeWeightMs, min: 0, max: 1_200),
            aiDjEnabled: settings.aiDjEnabled,
            aiDjMode: settings.aiDjMode,
            aiAgentProfiles: [PlayerSettings.defaultCodexAgentProfile],
            activeAiAgentProfileId: PlayerSettings.codexAgentProfileId,
            plannerCommand: PlayerSettings.defaultCodexAgentProfile.command,
            plannerArgs: PlayerSettings.defaultCodexAgentProfile.args,
            plannerTimeoutMs: PlayerSettings.defaultCodexAgentProfile.timeoutMs,
            mixReviewArtifactFolderPath: string(settings.mixReviewArtifactFolderPath)
        )
    }

    public static func sanitize(data: Data) throws -> PlayerSettings {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let raw = object as? [String: Any] else {
            return .defaults
        }

        let defaults = PlayerSettings.defaults
        let mode = string(raw["aiDjMode"]).flatMap(AIDJMode.init(rawValue:)) ?? defaults.aiDjMode
        return PlayerSettings(
            fadeDurationSec: clamp(number(raw["fadeDurationSec"]) ?? defaults.fadeDurationSec, min: 2, max: 20),
            masterGain: clamp(number(raw["masterGain"]) ?? defaults.masterGain, min: 0, max: 1),
            predecodeLeadSec: clamp(number(raw["predecodeLeadSec"]) ?? defaults.predecodeLeadSec, min: 3, max: 40),
            repeatAll: bool(raw["repeatAll"]) ?? defaults.repeatAll,
            decodeTimeoutDurationWeightMs: clamp(
                number(raw["decodeTimeoutDurationWeightMs"]) ?? defaults.decodeTimeoutDurationWeightMs,
                min: 0,
                max: 80
            ),
            decodeTimeoutSizeWeightMs: clamp(
                number(raw["decodeTimeoutSizeWeightMs"]) ?? defaults.decodeTimeoutSizeWeightMs,
                min: 0,
                max: 1_200
            ),
            aiDjEnabled: bool(raw["aiDjEnabled"]) ?? defaults.aiDjEnabled,
            aiDjMode: mode,
            aiAgentProfiles: [PlayerSettings.defaultCodexAgentProfile],
            activeAiAgentProfileId: PlayerSettings.codexAgentProfileId,
            plannerCommand: PlayerSettings.defaultCodexAgentProfile.command,
            plannerArgs: PlayerSettings.defaultCodexAgentProfile.args,
            plannerTimeoutMs: PlayerSettings.defaultCodexAgentProfile.timeoutMs,
            mixReviewArtifactFolderPath: string(raw["mixReviewArtifactFolderPath"])
        )
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        guard value.isFinite else {
            return min
        }
        return Swift.min(max, Swift.max(min, value))
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            let result = value.doubleValue
            return result.isFinite ? result : nil
        }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        value as? Bool
    }

    private static func string(_ value: Any?) -> String? {
        let result = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result?.isEmpty == false ? result : nil
    }
}
