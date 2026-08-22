import BeatDropperApplication

@MainActor
final class SettingsFeatureController: SettingsFeatureActionHandling {
    private let shell: AppShellFeature
    private let playing: PlayingFeature
    private let repository: any SettingsRepository
    private var invalidatePlanning: (() -> Void)?

    init(
        shell: AppShellFeature,
        playing: PlayingFeature,
        repository: any SettingsRepository
    ) {
        self.shell = shell
        self.playing = playing
        self.repository = repository
    }

    func setPlanningInvalidation(_ action: @escaping () -> Void) {
        invalidatePlanning = action
    }

    func restore() {
        do {
            shell.settings = try repository.loadMigratingLegacyDesktopSettingsIfNeeded().sanitized()
        } catch {
            shell.settings = .defaults
            shell.notice = "Could not restore settings: \(error.localizedDescription)"
        }
        playing.setMasterGain(shell.settings.masterGain)
    }

    func updateFadeDuration(_ value: Double) {
        update(invalidatesPlanning: true) { $0.fadeDurationSec = value }
    }

    func updateMasterGain(_ value: Double) {
        update(invalidatesPlanning: false) { $0.masterGain = value }
    }

    func updateAIDJMode(_ mode: AIDJMode) {
        update(invalidatesPlanning: true) { $0.aiDjMode = mode }
    }

    func updateMixReviewArtifactFolderPath(_ path: String?) {
        update(invalidatesPlanning: false) { $0.mixReviewArtifactFolderPath = path }
    }

    private func update(invalidatesPlanning: Bool, mutate: (inout PlayerSettings) -> Void) {
        var settings = shell.settings
        mutate(&settings)
        shell.settings = settings.sanitized()
        playing.setMasterGain(shell.settings.masterGain)
        if invalidatesPlanning { invalidatePlanning?() }
        do {
            try repository.save(shell.settings)
        } catch {
            shell.notice = "Could not save settings: \(error.localizedDescription)"
        }
    }
}
