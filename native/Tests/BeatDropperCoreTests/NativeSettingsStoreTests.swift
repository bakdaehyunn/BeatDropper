import BeatDropperCore
import Foundation
import Testing

struct NativeSettingsStoreTests {
    @Test func missingSettingsFileLoadsDefaults() throws {
        let fileURL = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let settings = try NativeSettingsStore(fileURL: fileURL).load()

        #expect(settings.fadeDurationSec == 8)
        #expect(settings.masterGain == 0.9)
        #expect(settings.aiDjEnabled == false)
        #expect(settings.aiDjMode == .safe)
        #expect(settings.activeAiAgentProfileId == PlayerSettings.codexAgentProfileId)
        #expect(settings.plannerTimeoutMs == 20_000)
        #expect(settings.mixReviewArtifactFolderPath == nil)
    }

    @Test func sanitizesAndPersistsNativeSettings() throws {
        let fileURL = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = NativeSettingsStore(fileURL: fileURL)
        try store.save(
            PlayerSettings(
                fadeDurationSec: 100,
                masterGain: -1,
                predecodeLeadSec: 100,
                repeatAll: false,
                decodeTimeoutDurationWeightMs: 100,
                decodeTimeoutSizeWeightMs: 2_000,
                aiDjEnabled: true,
                aiDjMode: .adventurous,
                aiAgentProfiles: [
                    AIAgentProfile(
                        id: "custom",
                        name: "Custom",
                        kind: "cli",
                        command: "custom",
                        args: [],
                        timeoutMs: 999,
                        enabled: true
                    )
                ],
                activeAiAgentProfileId: "custom",
                plannerCommand: "custom",
                plannerArgs: ["planner"],
                plannerTimeoutMs: 999,
                mixReviewArtifactFolderPath: "  /tmp/BeatDropper Reviews  "
            )
        )

        let loaded = try store.load()

        #expect(loaded.fadeDurationSec == 20)
        #expect(loaded.masterGain == 0)
        #expect(loaded.predecodeLeadSec == 40)
        #expect(loaded.repeatAll == false)
        #expect(loaded.decodeTimeoutDurationWeightMs == 80)
        #expect(loaded.decodeTimeoutSizeWeightMs == 1_200)
        #expect(loaded.aiDjEnabled == true)
        #expect(loaded.aiDjMode == .adventurous)
        #expect(loaded.aiAgentProfiles.map(\.id) == [PlayerSettings.codexAgentProfileId])
        #expect(loaded.plannerCommand == "node")
        #expect(loaded.plannerTimeoutMs == 20_000)
        #expect(loaded.mixReviewArtifactFolderPath == "/tmp/BeatDropper Reviews")
    }

    @Test func saveWritesBackupAndLoadFallsBackWhenPrimaryIsCorrupt() throws {
        let fileURL = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = NativeSettingsStore(fileURL: fileURL)
        try store.save(PlayerSettings(fadeDurationSec: 14, masterGain: 0.42, aiDjMode: .balanced))
        #expect(FileManager.default.fileExists(atPath: store.backupFileURL.path))

        try Data("{bad-json".utf8).write(to: fileURL)
        let loaded = try store.load()

        #expect(loaded.fadeDurationSec == 14)
        #expect(loaded.masterGain == 0.42)
        #expect(loaded.aiDjMode == .balanced)
    }

    @Test func emptyMixReviewArtifactFolderPathSanitizesToNil() throws {
        let settings = NativeSettingsStore.sanitize(
            PlayerSettings(mixReviewArtifactFolderPath: "   ")
        )

        #expect(settings.mixReviewArtifactFolderPath == nil)
    }

    @Test func loadFallsBackToBackupWhenPrimaryIsMissing() throws {
        let fileURL = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = NativeSettingsStore(fileURL: fileURL)
        try store.save(PlayerSettings(fadeDurationSec: 6, masterGain: 0.31, aiDjMode: .adventurous))
        try FileManager.default.removeItem(at: fileURL)
        let loaded = try store.load()

        #expect(loaded.fadeDurationSec == 6)
        #expect(loaded.masterGain == 0.31)
        #expect(loaded.aiDjMode == .adventurous)
    }

    @Test func migratesElectronPlayerSettingsWhenNativeSettingsAreMissing() throws {
        let folderURL = temporaryFolderURL()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try Data(
            """
            {
              "fadeDurationSec": 12,
              "masterGain": 0.72,
              "predecodeLeadSec": 24,
              "repeatAll": false,
              "decodeTimeoutDurationWeightMs": 33,
              "decodeTimeoutSizeWeightMs": 444,
              "aiDjEnabled": true,
              "aiDjMode": "balanced",
              "aiAgentProfiles": [
                {
                  "id": "old-custom",
                  "name": "Old Custom",
                  "kind": "cli",
                  "command": "old",
                  "args": ["planner"],
                  "timeoutMs": 9999,
                  "enabled": true
                }
              ],
              "activeAiAgentProfileId": "old-custom",
              "plannerCommand": "old",
              "plannerArgs": ["planner"],
              "plannerTimeoutMs": 9999,
              "mixReviewArtifactFolderPath": "/tmp/BeatDropper Review Notes"
            }
            """.utf8
        ).write(to: folderURL.appendingPathComponent("player-settings.json"))

        let nativeURL = folderURL.appendingPathComponent("native-settings.json")
        let store = NativeSettingsStore(fileURL: nativeURL)
        let settings = try store.loadMigratingElectronSettingsIfNeeded()

        #expect(FileManager.default.fileExists(atPath: nativeURL.path))
        #expect(settings.fadeDurationSec == 12)
        #expect(settings.masterGain == 0.72)
        #expect(settings.predecodeLeadSec == 24)
        #expect(settings.repeatAll == false)
        #expect(settings.decodeTimeoutDurationWeightMs == 33)
        #expect(settings.decodeTimeoutSizeWeightMs == 444)
        #expect(settings.aiDjEnabled == true)
        #expect(settings.aiDjMode == .balanced)
        #expect(settings.activeAiAgentProfileId == PlayerSettings.codexAgentProfileId)
        #expect(settings.plannerCommand == "node")
        #expect(settings.plannerTimeoutMs == 20_000)
        #expect(settings.mixReviewArtifactFolderPath == "/tmp/BeatDropper Review Notes")
    }

    private func temporarySettingsURL() -> URL {
        temporaryFolderURL().appendingPathComponent("native-settings.json")
    }

    private func temporaryFolderURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
