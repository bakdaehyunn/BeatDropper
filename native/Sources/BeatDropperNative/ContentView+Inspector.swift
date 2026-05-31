import BeatDropperCore
import SwiftUI

extension ContentView {
    var inspectorPane: some View {
        inspectorContent
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Mix Pair Inspector")
                    .font(.title3.weight(.semibold))

                Spacer()

                centeredIconButton(
                    systemImage: "xmark",
                    help: "Close mix inspector",
                    accessibilityLabel: "Close mix inspector"
                ) {
                    model.isInspectorVisible = false
                }
            }

            if let selectedTrack = model.selectedTrack {
                GroupBox("Selected Track") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.isTrackAvailable(selectedTrack) {
                            HStack {
                                Label("File unavailable", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                Spacer()
                                Button("Relink File", systemImage: "link") {
                                    model.relinkSelectedTrack()
                                }
                            }
                        }
                        Text(selectedTrack.track.title)
                            .font(.headline)
                            .lineLimit(2)
                        LabeledContent("Status", value: model.availabilityStatus(for: selectedTrack))
                        LabeledContent("BPM", value: selectedTrack.track.bpm.map { String(Int($0.rounded())) } ?? "--")
                        LabeledContent("Length", value: formatDuration(selectedTrack.track.durationSec))
                        LabeledContent("Format", value: selectedTrack.track.format.rawValue.uppercased())
                        LabeledContent("File", value: selectedTrack.url.lastPathComponent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Analysis") {
                    analysisSummary(for: selectedTrack)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("AI Mix Plan") {
                    mixPlanSummary
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No Selection", systemImage: "waveform")
            }

            Spacer()
        }
    }

    @ViewBuilder
    func analysisSummary(for selectedTrack: ImportedTrack) -> some View {
        if !model.isTrackAvailable(selectedTrack) {
            Text("--")
                .foregroundStyle(.secondary)
        } else if model.analyzingTrackIds.contains(selectedTrack.id) {
            ProgressView("Analyzing")
                .controlSize(.small)
        } else if let analysis = model.selectedTrackAnalysis {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Ready", value: analysis.analysisConfidence >= 0.65 ? "Yes" : "Low")
                LabeledContent("BPM", value: analysis.bpm.map { String(Int($0.rounded())) } ?? "--")
                LabeledContent("Conf", value: "\(Int((analysis.analysisConfidence * 100).rounded()))%")
                LabeledContent("Grid", value: "\(Int((analysis.analysisQuality.beatGrid * 100).rounded()))%")
                LabeledContent("Cue", value: cueSummary(for: analysis))
                if let intro = analysis.introCueSec {
                    LabeledContent("Intro", value: formatDuration(intro))
                }
                if let outro = analysis.outroCueSec {
                    LabeledContent("Outro", value: formatDuration(outro))
                }
            }
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var mixPlanSummary: some View {
        if model.isPlanningMix {
            ProgressView("Planning")
                .controlSize(.small)
        } else if let plan = model.currentMixPlan {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Transition", value: "\(formatDuration(plan.transitionStartSec)) -> \(formatDuration(plan.transitionEndSec))")
                LabeledContent("Next In", value: formatDuration(plan.nextTrackStartOffsetSec))
                LabeledContent("Style", value: plan.style.rawValue.replacingOccurrences(of: "_", with: " "))
                LabeledContent("Confidence", value: "\(Int((plan.confidence * 100).rounded()))%")
                if let countdown = model.scheduledMixCountdownSec {
                    LabeledContent("Starts", value: formatDuration(countdown))
                }
            }
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    func cueSummary(for analysis: TrackAnalysis) -> String {
        let cueConfidence = analysis.cueCandidates.map(\.confidence).max() ?? 0
        return "\(Int((cueConfidence * 100).rounded()))%"
    }
}
