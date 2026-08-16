import BeatDropperCore
import SwiftUI

extension ContentView {
    var playingTransitionPlan: MixPlan? {
        model.audioEngine.activeTransitionPlan ?? model.currentMixPlan
    }

    var mixMonitor: some View {
        VStack(spacing: 8) {
            playingMonitorMetaBar
            playingTransitionDecisionRow
            playingWaveformStack
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.32), lineWidth: 1)
        )
        .accessibilityLabel("Live mix monitor")
    }

    var playingMonitorMetaBar: some View {
        HStack(spacing: 12) {
            Label("Live Transition", systemImage: "waveform.path.ecg")
                .font(.headline.weight(.semibold))

            Spacer(minLength: 12)

            Text(playingMixStatusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .accessibilityLabel("Playing monitor status")
    }

    var playingTransitionDecisionRow: some View {
        HStack(spacing: 10) {
            deckDecisionCard(
                label: "CURRENT DECK",
                track: model.currentDeckDisplayTrack,
                analysis: model.currentDeckAnalysis,
                status: model.currentDeckDisplayStatus,
                accent: .orange
            )

            transitionDecisionCard
                .frame(minWidth: 230, maxWidth: .infinity)

            deckDecisionCard(
                label: "NEXT DECK",
                track: model.nextDeckDisplayTrack,
                analysis: model.nextDeckAnalysis,
                status: model.nextDeckDisplayStatus,
                accent: .cyan
            )
        }
        .accessibilityLabel("Current deck transition decision and next deck")
    }

    func deckDecisionCard(
        label: String,
        track: Track?,
        analysis: TrackAnalysis?,
        status: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
            Text(track?.title ?? "No track")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 10) {
                Text(analysis?.bpm.map { "\(Int($0.rounded())) BPM" } ?? "-- BPM")
                Text(status)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    var transitionDecisionCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if model.isPlanningMix {
                    ProgressView()
                        .controlSize(.small)
                    Text("Planning transition")
                } else if let plan = playingTransitionPlan {
                    Text(model.audioEngine.state == .crossfading
                        ? "MIX LIVE \(Int((model.audioEngine.crossfadeProgress * 100).rounded()))%"
                        : model.scheduledMixCountdownSec.map { "MIX IN \(formatDuration($0))" } ?? "TRANSITION READY")
                        .font(.headline.monospacedDigit())
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(Int((plan.confidence * 100).rounded()))%")
                        .font(.callout.weight(.semibold).monospacedDigit())
                } else {
                    Text(model.isAIMixEnabled ? "WAITING FOR PAIR" : "AI MIX OFF")
                        .font(.headline)
                }
            }

            if let plan = playingTransitionPlan {
                Text(transitionEvidenceText(plan))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            } else {
                Text("Select a playable pair to inspect the transition decision")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let review = model.currentMixPlanReview {
                    Text("Quality \(review.renderedQuality.grade.rawValue) \(Int((review.renderedQuality.score * 100).rounded()))%")
                        .foregroundStyle(renderedQualityColor(review.renderedQuality.grade))
                } else {
                    Text("Evidence available on demand")
                        .foregroundStyle(.secondary)
                }
                Button("Evidence", systemImage: "sidebar.right") {
                    model.isInspectorVisible = true
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedTrack == nil)
                .help("Open planner evidence and rendered mix quality")
            }
            .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transition decision")
    }

    var playingMixStatusText: String {
        if let plan = playingTransitionPlan {
            let qualityText = model.currentMixPlanReview.map {
                " · Q \($0.renderedQuality.grade.rawValue) \(Int(($0.renderedQuality.score * 100).rounded()))%"
            } ?? ""
            let phase = model.audioEngine.state == .crossfading
                ? "live \(Int((model.audioEngine.crossfadeProgress * 100).rounded()))%"
                : model.scheduledMixCountdownSec.map { "in \(formatDuration($0))" } ?? "ready"
            return "Mix \(phase) · \(transitionEvidenceText(plan)) · \(Int((plan.confidence * 100).rounded()))%\(qualityText)"
        }
        if model.isPlanningMix {
            return "AI Mix planning"
        }
        if model.isAIMixEnabled {
            return "AI Mix active"
        }
        return "AI Mix off"
    }

    var playingWaveformStack: some View {
        VStack(spacing: 10) {
            deckWaveformRow(
                title: "Current",
                value: model.audioEngine.currentTrack != nil
                    ? formatDuration(model.audioEngine.elapsedSec)
                    : formatDuration(playingTransitionPlan?.transitionStartSec ?? model.currentDeckAnalysis?.outroCueSec ?? 0),
                track: model.currentDeckDisplayTrack,
                analysis: model.currentDeckAnalysis,
                elapsedSec: model.audioEngine.currentTrack != nil ? model.audioEngine.elapsedSec : nil,
                cueTimeSec: playingTransitionPlan?.transitionStartSec ?? model.currentDeckAnalysis?.outroCueSec,
                cueLabel: "OUT",
                isNextDeck: false,
                status: model.currentDeckDisplayStatus,
                meter: model.audioEngine.currentDeckMeter
            )

            deckWaveformRow(
                title: "Next",
                value: model.audioEngine.queuedTrack != nil
                    ? formatDuration(model.audioEngine.nextDeckElapsedSec)
                    : formatDuration(playingTransitionPlan?.nextTrackStartOffsetSec ?? model.nextDeckAnalysis?.introCueSec ?? 0),
                track: model.nextDeckDisplayTrack,
                analysis: model.nextDeckAnalysis,
                elapsedSec: model.audioEngine.queuedTrack != nil
                    ? model.audioEngine.nextDeckElapsedSec
                    : nil,
                cueTimeSec: playingTransitionPlan?.nextTrackStartOffsetSec ?? model.nextDeckAnalysis?.introCueSec,
                cueLabel: "IN",
                isNextDeck: true,
                status: model.nextDeckDisplayStatus,
                meter: model.audioEngine.nextDeckMeter
            )
        }
        .padding(8)
        .background(
            Color(nsColor: .textBackgroundColor).opacity(0.35),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        )
        .accessibilityLabel("Playing waveform stack")
    }

    func transitionEvidenceText(_ plan: MixPlan) -> String {
        let style = plan.style.rawValue.replacingOccurrences(of: "_", with: " ")
        let bars = plan.transitionBarCount.map { $0 == 1 ? "1 bar" : "\($0) bars" } ?? "seconds fallback"
        let duration = formatDuration(max(0, plan.transitionEndSec - plan.transitionStartSec))
        let source = plan.transitionTimingSource == .beatGrid ? "GRID" : "SECONDS"
        return "\(style) · \(bars) · \(duration) · \(source) · OUT \(formatDuration(plan.transitionStartSec)) · IN \(formatDuration(plan.nextTrackStartOffsetSec))"
    }

    func deckWaveformRow(
        title: String,
        value: String,
        track: Track?,
        analysis: TrackAnalysis?,
        elapsedSec: Double?,
        cueTimeSec: Double?,
        cueLabel: String,
        isNextDeck: Bool,
        status: String,
        meter: AudioLevelMeter
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                Text(track?.title ?? "No track")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                miniDeckMeter(meter)
                Text(status)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 110, alignment: .leading)

            trackWaveformStrip(
                title: title,
                track: track,
                analysis: analysis,
                elapsedSec: elapsedSec,
                cueTimeSec: cueTimeSec,
                cueLabel: cueLabel,
                isNextDeck: isNextDeck
            )
            .frame(height: 58)
        }
    }

    func miniDeckMeter(_ meter: AudioLevelMeter) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor).opacity(0.28))
                RoundedRectangle(cornerRadius: 2)
                    .fill(meter.clipped ? Color.red : Color.accentColor)
                    .frame(width: max(2, proxy.size.width * meter.rms))
                Rectangle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 1.5)
                    .offset(x: max(0, min(proxy.size.width - 1.5, proxy.size.width * meter.peak)))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Deck level")
        .accessibilityValue(meter.clipped ? "clipping" : "\(Int(meter.peakDb.rounded())) decibels")
    }

    func trackWaveformStrip(
        title: String,
        track: Track?,
        analysis: TrackAnalysis?,
        elapsedSec: Double?,
        cueTimeSec: Double?,
        cueLabel: String,
        isNextDeck: Bool
    ) -> some View {
        let points = waveformRenderPoints(for: analysis)
        let durationSec = max(0, track?.durationSec ?? 0)
        let accessibilityTitle = "\(title) waveform overview"

        return Canvas { context, size in
            drawWaveformBackground(in: context, size: size)

            guard track != nil, durationSec > 0 else {
                drawWaveformPlaceholder(in: context, size: size, label: "--")
                return
            }

            guard !points.isEmpty else {
                drawWaveformPlaceholder(in: context, size: size, label: "DSP --")
                return
            }

            drawBarMarkers(analysis?.barGrid ?? [], durationSec: durationSec, in: context, size: size)
            drawPhraseMarkers(analysis?.phraseMarkers ?? [], durationSec: durationSec, in: context, size: size)
            drawTransientMarkers(analysis?.transientMarkers ?? [], durationSec: durationSec, in: context, size: size)

            drawWaveformPoints(points, in: context, size: size, isNextDeck: isNextDeck)

            if let cueTimeSec {
                drawWaveformCursor(
                    timeSec: cueTimeSec,
                    durationSec: durationSec,
                    label: cueLabel,
                    color: isNextDeck ? .cyan : .orange,
                    in: context,
                    size: size,
                    alignTrailing: !isNextDeck
                )
            }

            if let elapsedSec {
                drawWaveformCursor(
                    timeSec: elapsedSec,
                    durationSec: durationSec,
                    label: "PLAY",
                    color: .white,
                    in: context,
                    size: size
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        )
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(points.isEmpty ? "no waveform data" : "\(points.count) waveform points")
    }
}
