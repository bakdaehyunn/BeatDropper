import BeatDropperCore
import SwiftUI

extension ContentView {
    func waveformRenderPoints(for analysis: TrackAnalysis?, maxCount: Int = 180) -> [WaveformRenderPoint] {
        guard let analysis else {
            return []
        }

        if !analysis.waveformDetail.isEmpty {
            let stride = max(1, Int(ceil(Double(analysis.waveformDetail.count) / Double(maxCount))))
            return analysis.waveformDetail.enumerated().compactMap { index, point in
                guard index % stride == 0 else {
                    return nil
                }
                let band = spectralBand(
                    for: analysis,
                    sourceIndex: index,
                    sourceCount: analysis.waveformDetail.count
                )
                return WaveformRenderPoint(
                    id: index,
                    timeSec: point.timeSec,
                    peak: clampedUnit(point.peak),
                    rms: clampedUnit(point.rms),
                    low: clampedUnit(band?.low ?? point.rms),
                    mid: clampedUnit(band?.mid ?? point.peak),
                    high: clampedUnit(band?.high ?? max(0, point.peak - point.rms))
                )
            }
            .prefix(maxCount)
            .map { $0 }
        }

        if !analysis.waveformPeaks.isEmpty {
            let stride = max(1, Int(ceil(Double(analysis.waveformPeaks.count) / Double(maxCount))))
            return analysis.waveformPeaks.enumerated().compactMap { index, point in
                guard index % stride == 0 else {
                    return nil
                }
                let band = spectralBand(
                    for: analysis,
                    sourceIndex: index,
                    sourceCount: analysis.waveformPeaks.count
                )
                return WaveformRenderPoint(
                    id: index,
                    timeSec: point.timeSec,
                    peak: clampedUnit(point.peak),
                    rms: clampedUnit(point.rms),
                    low: clampedUnit(band?.low ?? point.rms),
                    mid: clampedUnit(band?.mid ?? point.peak),
                    high: clampedUnit(band?.high ?? max(0, point.peak - point.rms))
                )
            }
            .prefix(maxCount)
            .map { $0 }
        }

        return []
    }

    func spectralBand(
        for analysis: TrackAnalysis,
        sourceIndex: Int,
        sourceCount: Int
    ) -> SpectralBandPoint? {
        guard !analysis.spectralBands.isEmpty, sourceCount > 0 else {
            return nil
        }
        let ratio = Double(sourceIndex) / Double(max(1, sourceCount - 1))
        let bandIndex = Int((ratio * Double(analysis.spectralBands.count - 1)).rounded())
        return analysis.spectralBands[min(max(0, bandIndex), analysis.spectralBands.count - 1)]
    }

    func drawWaveformBackground(in context: GraphicsContext, size: CGSize) {
        let fullRect = CGRect(origin: .zero, size: size)
        context.fill(
            roundedRectPath(fullRect, radius: 7),
            with: .color(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )

        drawHorizontalLine(
            y: size.height * 0.5,
            color: Color.primary.opacity(0.16),
            lineWidth: 1,
            in: context,
            size: size
        )
        drawHorizontalLine(
            y: size.height * 0.25,
            color: Color.primary.opacity(0.06),
            lineWidth: 1,
            in: context,
            size: size
        )
        drawHorizontalLine(
            y: size.height * 0.75,
            color: Color.primary.opacity(0.06),
            lineWidth: 1,
            in: context,
            size: size
        )
    }

    func drawWaveformPlaceholder(
        in context: GraphicsContext,
        size: CGSize,
        label: String
    ) {
        let resolved = context.resolve(
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        )
        context.draw(resolved, at: CGPoint(x: size.width * 0.5, y: size.height * 0.5), anchor: .center)
    }

    func drawWaveformPoints(
        _ points: [WaveformRenderPoint],
        in context: GraphicsContext,
        size: CGSize,
        isNextDeck: Bool
    ) {
        guard !points.isEmpty, size.width > 0, size.height > 0 else {
            return
        }

        let count = max(1, points.count)
        let step = size.width / CGFloat(count)
        let barWidth = max(1.4, min(4.4, step * 0.58))
        let centerY = size.height * 0.52
        let upperMaxHeight = size.height * 0.42
        let lowerMaxHeight = size.height * 0.34

        for (index, point) in points.enumerated() {
            let x = step * CGFloat(index) + (step - barWidth) * 0.5
            let peakHeight = max(5, CGFloat(point.peak) * upperMaxHeight)
            let rmsHeight = max(3, CGFloat(point.rms) * lowerMaxHeight)
            let highAlpha = 0.28 + clampedUnit(point.high) * 0.48
            let midAlpha = 0.25 + clampedUnit(point.mid) * 0.42
            let lowAlpha = 0.24 + clampedUnit(point.low) * 0.48

            let upperColor = isNextDeck
                ? Color.cyan.opacity(midAlpha)
                : Color.orange.opacity(midAlpha)
            let upperAccent = isNextDeck
                ? Color.teal.opacity(highAlpha)
                : Color.red.opacity(highAlpha)
            let lowerColor = Color.accentColor.opacity(lowAlpha)

            let upperRect = CGRect(
                x: x,
                y: max(2, centerY - peakHeight),
                width: barWidth,
                height: peakHeight
            )
            let lowerRect = CGRect(
                x: x,
                y: centerY + 2,
                width: barWidth,
                height: rmsHeight
            )

            context.fill(roundedRectPath(upperRect, radius: barWidth * 0.5), with: .color(upperColor))
            context.fill(roundedRectPath(upperRect.insetBy(dx: 0, dy: peakHeight * 0.35), radius: barWidth * 0.5), with: .color(upperAccent))
            context.fill(roundedRectPath(lowerRect, radius: barWidth * 0.5), with: .color(lowerColor))
        }
    }

    func drawBarMarkers(
        _ markers: [BarMarker],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for marker in markers where marker.index % 4 == 0 {
            let x = xPosition(timeSec: marker.startSec, durationSec: durationSec, width: size.width)
            let isPhrase = marker.index % 8 == 0
            drawVerticalLine(
                x: x,
                yStart: 0,
                yEnd: size.height,
                color: Color.primary.opacity(isPhrase ? 0.18 : 0.08),
                lineWidth: isPhrase ? 1.2 : 0.8,
                in: context
            )
        }
    }

    func drawPhraseMarkers(
        _ markers: [PhraseMarker],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for marker in markers.prefix(64) {
            let x = xPosition(timeSec: marker.startSec, durationSec: durationSec, width: size.width)
            drawVerticalLine(
                x: x,
                yStart: 0,
                yEnd: size.height,
                color: Color.white.opacity(0.12 + clampedUnit(marker.confidence) * 0.2),
                lineWidth: 1.4,
                in: context
            )
        }
    }

    func drawTransientMarkers(
        _ markers: [TransientMarker],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for marker in markers.prefix(90) {
            let x = xPosition(timeSec: marker.timeSec, durationSec: durationSec, width: size.width)
            let strength = clampedUnit(marker.strength)
            let markerHeight = size.height * CGFloat(0.28 + strength * 0.46)
            let yStart = (size.height - markerHeight) * 0.5
            drawVerticalLine(
                x: x,
                yStart: yStart,
                yEnd: yStart + markerHeight,
                color: Color.white.opacity(0.12 + strength * 0.42),
                lineWidth: 0.9,
                in: context
            )
        }
    }

    func drawPreparationCueMarkers(
        _ cues: [TrackPreparationCue],
        durationSec: Double,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard durationSec > 0 else {
            return
        }

        for cue in cues.prefix(24) {
            let x = xPosition(timeSec: cue.timeSec, durationSec: durationSec, width: size.width)
            drawVerticalLine(
                x: x,
                yStart: 0,
                yEnd: size.height,
                color: cueColor(cue.kind).opacity(0.9),
                lineWidth: 1.8,
                in: context
            )

            let label = cue.kind.displayName.prefix(1).uppercased()
            let rect = CGRect(
                x: min(max(4, x + 4), max(4, size.width - 24)),
                y: size.height - 22,
                width: 20,
                height: 16
            )
            context.fill(roundedRectPath(rect, radius: 8), with: .color(cueColor(cue.kind).opacity(0.92)))
            let resolved = context.resolve(
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.black)
            )
            context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    func drawWaveformCursor(
        timeSec: Double,
        durationSec: Double,
        label: String,
        color: Color,
        in context: GraphicsContext,
        size: CGSize,
        alignTrailing: Bool = false
    ) {
        guard durationSec > 0 else {
            return
        }

        let x = xPosition(timeSec: timeSec, durationSec: durationSec, width: size.width)
        drawVerticalLine(
            x: x,
            yStart: 0,
            yEnd: size.height,
            color: color.opacity(0.9),
            lineWidth: label == "PLAY" ? 2.2 : 1.8,
            in: context
        )

        let width: CGFloat = label == "PLAY" ? 36 : 30
        let labelCenterX = alignTrailing
            ? min(max(width * 0.5 + 3, x - width * 0.5), size.width - width * 0.5 - 3)
            : min(max(width * 0.5 + 3, x + width * 0.5), size.width - width * 0.5 - 3)
        let rect = CGRect(x: labelCenterX - width * 0.5, y: 4, width: width, height: 16)

        context.fill(roundedRectPath(rect, radius: 8), with: .color(color.opacity(0.95)))
        let resolved = context.resolve(
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundColor(.black)
        )
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    func cueColor(_ kind: TrackPreparationCueKind) -> Color {
        switch kind {
        case .intro:
            return .cyan
        case .drop:
            return .orange
        case .breakdown:
            return .purple
        case .outro:
            return .red
        case .custom:
            return .yellow
        }
    }

    func drawHorizontalLine(
        y: CGFloat,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext,
        size: CGSize
    ) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    func drawVerticalLine(
        x: CGFloat,
        yStart: CGFloat,
        yEnd: CGFloat,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext
    ) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: yStart))
        path.addLine(to: CGPoint(x: x, y: yEnd))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: radius, height: radius)
        )
        return path
    }

    func xPosition(timeSec: Double, durationSec: Double, width: CGFloat) -> CGFloat {
        guard timeSec.isFinite, durationSec.isFinite, durationSec > 0 else {
            return 0
        }
        return min(width, max(0, CGFloat(timeSec / durationSec) * width))
    }

    func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(1, max(0, value))
    }
}
