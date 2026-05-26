import BeatDropperCore
import SwiftUI

struct MixSettingsView: View {
    @EnvironmentObject private var model: BeatDropperAppModel

    var body: some View {
        Form {
            Section("Mix") {
                Stepper(value: fadeDurationBinding, in: 2...20, step: 1) {
                    LabeledContent("Fade duration", value: "\(Int(model.settings.fadeDurationSec.rounded())) sec")
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Master output", value: "\(Int((model.settings.masterGain * 100).rounded()))%")
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
            get: { model.settings.fadeDurationSec },
            set: { model.updateFadeDuration($0) }
        )
    }

    private var masterGainBinding: Binding<Double> {
        Binding(
            get: { model.settings.masterGain },
            set: { model.updateMasterGain($0) }
        )
    }

    private var aiModeBinding: Binding<AIDJMode> {
        Binding(
            get: { model.settings.aiDjMode },
            set: { model.updateAIDJMode($0) }
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
