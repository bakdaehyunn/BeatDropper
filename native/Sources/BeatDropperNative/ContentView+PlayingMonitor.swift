import BeatDropperCore
import SwiftUI

extension ContentView {
    var mixMonitor: some View {
        VStack(spacing: 8) {
            playingMonitorMetaBar
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
            Label("Track Monitor", systemImage: "waveform")
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

    var playingMixStatusText: String {
        if let plan = model.currentMixPlan {
            return "AI Mix \(model.scheduledMixCountdownSec.map { "in \(formatDuration($0))" } ?? "ready") · OUT \(formatDuration(plan.transitionStartSec)) · IN \(formatDuration(plan.nextTrackStartOffsetSec)) · \(Int((plan.confidence * 100).rounded()))%"
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
                    : formatDuration(model.currentMixPlan?.transitionStartSec ?? model.currentDeckAnalysis?.outroCueSec ?? 0),
                track: model.currentDeckDisplayTrack,
                analysis: model.currentDeckAnalysis,
                elapsedSec: model.audioEngine.currentTrack != nil ? model.audioEngine.elapsedSec : nil,
                cueTimeSec: model.currentMixPlan?.transitionStartSec ?? model.currentDeckAnalysis?.outroCueSec,
                cueLabel: "OUT",
                isNextDeck: false,
                status: model.currentDeckDisplayStatus,
                meter: model.audioEngine.currentDeckMeter
            )

            deckWaveformRow(
                title: "Next",
                value: formatDuration(model.currentMixPlan?.nextTrackStartOffsetSec ?? model.nextDeckAnalysis?.introCueSec ?? 0),
                track: model.nextDeckDisplayTrack,
                analysis: model.nextDeckAnalysis,
                elapsedSec: nil,
                cueTimeSec: model.currentMixPlan?.nextTrackStartOffsetSec ?? model.nextDeckAnalysis?.introCueSec,
                cueLabel: "IN",
                isNextDeck: true,
                status: model.nextDeckDisplayStatus,
                meter: model.audioEngine.nextDeckMeter
            )
        }
        .padding(10)
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
            .frame(width: 124, alignment: .leading)

            trackWaveformStrip(
                title: title,
                track: track,
                analysis: analysis,
                elapsedSec: elapsedSec,
                cueTimeSec: cueTimeSec,
                cueLabel: cueLabel,
                isNextDeck: isNextDeck
            )
            .frame(height: 118)
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
