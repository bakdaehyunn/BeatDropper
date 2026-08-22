import Foundation

public extension PlayerSettings {
    func sanitized() -> PlayerSettings {
        PlayerSettings(
            fadeDurationSec: min(20, max(2, fadeDurationSec.isFinite ? fadeDurationSec : Self.defaults.fadeDurationSec)),
            masterGain: min(1, max(0, masterGain.isFinite ? masterGain : Self.defaults.masterGain)),
            predecodeLeadSec: min(40, max(3, predecodeLeadSec.isFinite ? predecodeLeadSec : Self.defaults.predecodeLeadSec)),
            repeatAll: repeatAll,
            decodeTimeoutDurationWeightMs: min(80, max(0, decodeTimeoutDurationWeightMs.isFinite ? decodeTimeoutDurationWeightMs : Self.defaults.decodeTimeoutDurationWeightMs)),
            decodeTimeoutSizeWeightMs: min(1_200, max(0, decodeTimeoutSizeWeightMs.isFinite ? decodeTimeoutSizeWeightMs : Self.defaults.decodeTimeoutSizeWeightMs)),
            aiDjEnabled: aiDjEnabled,
            aiDjMode: aiDjMode,
            aiAgentProfiles: [Self.defaultCodexAgentProfile],
            activeAiAgentProfileId: Self.codexAgentProfileId,
            plannerCommand: Self.defaultCodexAgentProfile.command,
            plannerArgs: Self.defaultCodexAgentProfile.args,
            plannerTimeoutMs: Self.defaultCodexAgentProfile.timeoutMs,
            mixReviewArtifactFolderPath: mixReviewArtifactFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
