import BeatDropperApplication
import SwiftUI

struct MixSettingsView: View {
    @EnvironmentObject private var model: BeatDropperAppModel
    @EnvironmentObject private var shell: AppShellFeature

    var body: some View {
        Form {
            Section("Mix") {
                Stepper(value: fadeDurationBinding, in: 2...20, step: 1) {
                    LabeledContent("Fade duration", value: "\(Int(shell.settings.fadeDurationSec.rounded())) sec")
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Master output", value: "\(Int((shell.settings.masterGain * 100).rounded()))%")
                        .monospacedDigit()
                    Slider(value: masterGainBinding, in: 0...1, step: 0.01)
                }
            }

            Section("AI Mix Planning") {
                Picker("Mode", selection: aiModeBinding) {
                    ForEach(AIDJMode.allCases, id: \.self) { mode in
                        Text(aiModeLabel(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Planner", value: "Codex")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .accessibilityLabel("BeatDropper settings")
    }

    private var fadeDurationBinding: Binding<Double> {
        Binding(
            get: { shell.settings.fadeDurationSec },
            set: { model.settingsActions.updateFadeDuration($0) }
        )
    }

    private var masterGainBinding: Binding<Double> {
        Binding(
            get: { shell.settings.masterGain },
            set: { model.settingsActions.updateMasterGain($0) }
        )
    }

    private var aiModeBinding: Binding<AIDJMode> {
        Binding(
            get: { shell.settings.aiDjMode },
            set: { model.settingsActions.updateAIDJMode($0) }
        )
    }

    private func aiModeLabel(_ mode: AIDJMode) -> String {
        switch mode {
        case .safe:
            return "Safe"
        case .balanced:
            return "Balanced"
        case .adventurous:
            return "Adventurous"
        }
    }
}
