import Foundation

public enum RenderedTransitionQualityGrade: String, Codable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case reject = "REJECT"
}

public enum RenderedTransitionQualityIssueSeverity: String, Codable, Sendable {
    case warning
    case major
    case critical
}

public enum RenderedTransitionQualityIssueCode: String, Codable, Sendable {
    case clippingRisk = "clipping_risk"
    case peakJump = "peak_jump"
    case rmsJump = "rms_jump"
    case loudnessDelta = "loudness_delta"
    case headroomLow = "headroom_low"
    case spectralMaskingRisk = "spectral_masking_risk"
    case missingAnalysis = "missing_analysis"
}

public struct RenderedTransitionQualityIssue: Codable, Hashable, Sendable {
    public var code: RenderedTransitionQualityIssueCode
    public var severity: RenderedTransitionQualityIssueSeverity
    public var message: String

    public init(
        code: RenderedTransitionQualityIssueCode,
        severity: RenderedTransitionQualityIssueSeverity,
        message: String
    ) {
        self.code = code
        self.severity = severity
        self.message = message
    }
}

public struct RenderedTransitionQualityMetric: Codable, Hashable, Sendable {
    public var name: String
    public var value: Double
    public var score: Double
    public var summary: String

    public init(name: String, value: Double, score: Double, summary: String) {
        self.name = name
        self.value = value
        self.score = score
        self.summary = summary
    }
}

public struct RenderedTransitionQualityReport: Codable, Hashable, Sendable {
    public var score: Double
    public var grade: RenderedTransitionQualityGrade
    public var shouldApply: Bool
    public var issues: [RenderedTransitionQualityIssue]
    public var metrics: [RenderedTransitionQualityMetric]
    public var summary: String

    public init(
        score: Double,
        grade: RenderedTransitionQualityGrade,
        shouldApply: Bool,
        issues: [RenderedTransitionQualityIssue],
        metrics: [RenderedTransitionQualityMetric],
        summary: String
    ) {
        self.score = score
        self.grade = grade
        self.shouldApply = shouldApply
        self.issues = issues
        self.metrics = metrics
        self.summary = summary
    }
}

public enum RenderedTransitionQualityAnalyzer {
    public static func analyze(
        plan: MixPlan,
        currentTrack: Track,
        nextTrack: Track,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?,
        sampleCount rawSampleCount: Int = 17
    ) -> RenderedTransitionQualityReport {
        let transitionDurationSec = max(0.05, plan.transitionEndSec - plan.transitionStartSec)
        let sampleCount = max(3, min(65, rawSampleCount))
        let rendered = (0..<sampleCount).map { index in
            let progress = sampleCount == 1 ? 0 : Double(index) / Double(sampleCount - 1)
            let currentTimeSec = plan.transitionStartSec + progress * transitionDurationSec
            let nextTimeSec = plan.nextTrackStartOffsetSec + progress * transitionDurationSec
            return renderSample(
                progress: progress,
                currentTimeSec: currentTimeSec,
                nextTimeSec: nextTimeSec,
                currentTrack: currentTrack,
                nextTrack: nextTrack,
                currentAnalysis: currentAnalysis,
                nextAnalysis: nextAnalysis,
                plan: plan
            )
        }

        let pre = renderReferencePoint(
            timeSec: max(0, plan.transitionStartSec - min(2, transitionDurationSec * 0.5)),
            track: currentTrack,
            analysis: currentAnalysis
        )
        let post = renderReferencePoint(
            timeSec: min(nextTrack.durationSec, plan.nextTrackStartOffsetSec + transitionDurationSec + min(2, transitionDurationSec * 0.5)),
            track: nextTrack,
            analysis: nextAnalysis
        )

        let peakMax = rendered.map(\.peak).max() ?? 0
        let rmsMax = rendered.map(\.rms).max() ?? 0
        let spectralMaskingRisk = rendered.map(\.spectralMaskingRisk).max() ?? 0
        let referencePeak = max(0.000_001, max(pre.peak, post.peak))
        let referenceRMS = max(0.000_001, max(pre.rms, post.rms))
        let peakJumpDb = max(0, db(peakMax) - db(referencePeak))
        let rmsJumpDb = max(0, db(rmsMax) - db(referenceRMS))
        let loudnessDeltaDb = loudnessDelta(currentAnalysis: currentAnalysis, nextAnalysis: nextAnalysis)
        let headroomMarginDb = headroomMargin(currentAnalysis: currentAnalysis, nextAnalysis: nextAnalysis)
        let masterDSP = PlaybackDSPResolver.masterSettings(plan: plan)
        let ceilingDb = masterDSP.ceilingDb
        let ceilingLinear = gain(db: ceilingDb)
        let clips = masterDSP.softLimitEnabled
            ? peakMax > ceilingLinear + 0.005
            : peakMax >= 0.98

        var issues: [RenderedTransitionQualityIssue] = []
        if currentAnalysis == nil || nextAnalysis == nil {
            issues.append(RenderedTransitionQualityIssue(
                code: .missingAnalysis,
                severity: .warning,
                message: "Rendered quality estimate used fallback analysis points."
            ))
        }
        if clips {
            issues.append(RenderedTransitionQualityIssue(
                code: .clippingRisk,
                severity: peakMax >= 1 ? .critical : .major,
                message: "Estimated transition peak \(formatDb(db(peakMax))) exceeds safe ceiling \(formatDb(ceilingDb))."
            ))
        }
        if peakJumpDb >= 6 {
            issues.append(RenderedTransitionQualityIssue(
                code: .peakJump,
                severity: peakJumpDb >= 9 ? .major : .warning,
                message: "Estimated peak jump is \(formatDb(peakJumpDb))."
            ))
        }
        if rmsJumpDb >= 4 {
            issues.append(RenderedTransitionQualityIssue(
                code: .rmsJump,
                severity: rmsJumpDb >= 7 ? .major : .warning,
                message: "Estimated RMS jump is \(formatDb(rmsJumpDb))."
            ))
        }
        if loudnessDeltaDb >= 5 {
            issues.append(RenderedTransitionQualityIssue(
                code: .loudnessDelta,
                severity: loudnessDeltaDb >= 8 ? .major : .warning,
                message: "Estimated track loudness delta is \(formatDb(loudnessDeltaDb))."
            ))
        }
        if headroomMarginDb > 0, headroomMarginDb < 1 {
            issues.append(RenderedTransitionQualityIssue(
                code: .headroomLow,
                severity: .warning,
                message: "Source headroom margin is \(formatDb(headroomMarginDb))."
            ))
        }
        if spectralMaskingRisk >= 0.68 {
            issues.append(RenderedTransitionQualityIssue(
                code: .spectralMaskingRisk,
                severity: spectralMaskingRisk >= 0.82 ? .major : .warning,
                message: "Estimated spectral masking risk is \(formatPercent(spectralMaskingRisk))."
            ))
        }

        let metrics = [
            RenderedTransitionQualityMetric(
                name: "estimated_peak",
                value: peakMax,
                score: scoreUpperBound(value: peakMax, warning: 0.9, reject: 1.0),
                summary: "max \(formatDb(db(peakMax)))"
            ),
            RenderedTransitionQualityMetric(
                name: "peak_jump",
                value: peakJumpDb,
                score: scoreUpperBound(value: peakJumpDb, warning: 4, reject: 9),
                summary: "jump \(formatDb(peakJumpDb))"
            ),
            RenderedTransitionQualityMetric(
                name: "rms_jump",
                value: rmsJumpDb,
                score: scoreUpperBound(value: rmsJumpDb, warning: 3, reject: 8),
                summary: "jump \(formatDb(rmsJumpDb))"
            ),
            RenderedTransitionQualityMetric(
                name: "loudness_delta",
                value: loudnessDeltaDb,
                score: scoreUpperBound(value: loudnessDeltaDb, warning: 4, reject: 9),
                summary: "delta \(formatDb(loudnessDeltaDb))"
            ),
            RenderedTransitionQualityMetric(
                name: "headroom_margin",
                value: headroomMarginDb,
                score: scoreLowerBound(value: headroomMarginDb, warning: 1.5, reject: 0.2),
                summary: "margin \(formatDb(headroomMarginDb))"
            ),
            RenderedTransitionQualityMetric(
                name: "spectral_masking",
                value: spectralMaskingRisk,
                score: scoreUpperBound(value: spectralMaskingRisk, warning: 0.55, reject: 0.85),
                summary: "risk \(formatPercent(spectralMaskingRisk))"
            )
        ]
        let score = clamped(metrics.map(\.score).reduce(0, +) / Double(max(1, metrics.count)), min: 0, max: 1)
        let hasCritical = issues.contains { $0.severity == .critical }
        let hasMajor = issues.contains { $0.severity == .major }
        let grade: RenderedTransitionQualityGrade = if hasCritical || score < 0.45 {
            .reject
        } else if hasMajor || !issues.isEmpty || score < 0.72 {
            .warn
        } else {
            .pass
        }

        return RenderedTransitionQualityReport(
            score: rounded(score),
            grade: grade,
            shouldApply: grade != .reject,
            issues: issues,
            metrics: metrics,
            summary: "peak \(formatDb(db(peakMax))), peak jump \(formatDb(peakJumpDb)), RMS jump \(formatDb(rmsJumpDb)), loudness delta \(formatDb(loudnessDeltaDb)), masking \(formatPercent(spectralMaskingRisk))"
        )
    }

    private static func renderSample(
        progress: Double,
        currentTimeSec: Double,
        nextTimeSec: Double,
        currentTrack: Track,
        nextTrack: Track,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?,
        plan: MixPlan
    ) -> (peak: Double, rms: Double, spectralMaskingRisk: Double) {
        let gains = CrossfadeMath.equalPowerGains(progress: progress)
        let outgoingDSP = PlaybackDSPResolver.deckSettings(plan: plan, role: .outgoing, analysis: currentAnalysis)
        let incomingDSP = PlaybackDSPResolver.deckSettings(plan: plan, role: .incoming, analysis: nextAnalysis)
        let outgoingGain = gains.outgoing * gain(db: outgoingDSP.gainDb)
        let incomingGain = gains.incoming * gain(db: incomingDSP.gainDb)
        let currentPoint = waveformPoint(at: currentTimeSec, track: currentTrack, analysis: currentAnalysis)
        let nextPoint = waveformPoint(at: nextTimeSec, track: nextTrack, analysis: nextAnalysis)
        let unprotectedPeak = currentPoint.peak * outgoingGain + nextPoint.peak * incomingGain
        let rms = sqrt(pow(currentPoint.rms * outgoingGain, 2) + pow(nextPoint.rms * incomingGain, 2))
        let masterDSP = PlaybackDSPResolver.masterSettings(plan: plan)
        let peak = masterDSP.softLimitEnabled
            ? min(unprotectedPeak, PlaybackDSPResolver.linearGain(db: masterDSP.ceilingDb))
            : unprotectedPeak
        let currentBand = spectralBand(at: currentTimeSec, track: currentTrack, analysis: currentAnalysis)
        let nextBand = spectralBand(at: nextTimeSec, track: nextTrack, analysis: nextAnalysis)
        let masking = spectralMaskingRisk(
            current: currentBand,
            next: nextBand,
            outgoingGain: outgoingGain,
            incomingGain: incomingGain
        )
        return (peak, rms, masking)
    }

    private static func renderReferencePoint(
        timeSec: Double,
        track: Track,
        analysis: TrackAnalysis?
    ) -> (peak: Double, rms: Double) {
        let point = waveformPoint(at: timeSec, track: track, analysis: analysis)
        return (point.peak, point.rms)
    }

    private static func waveformPoint(
        at timeSec: Double,
        track: Track,
        analysis: TrackAnalysis?
    ) -> (peak: Double, rms: Double) {
        if let point = nearest(analysis?.waveformDetail ?? [], timeSec: timeSec, durationSec: track.durationSec) {
            return (clamped(point.peak, min: 0, max: 2), clamped(point.rms, min: 0, max: 2))
        }
        if let point = nearest(analysis?.waveformPeaks ?? [], timeSec: timeSec, durationSec: track.durationSec) {
            return (clamped(point.peak, min: 0, max: 2), clamped(point.rms, min: 0, max: 2))
        }
        return (0.45, 0.25)
    }

    private static func spectralBand(
        at timeSec: Double,
        track: Track,
        analysis: TrackAnalysis?
    ) -> SpectralBandPoint? {
        nearest(analysis?.spectralBands ?? [], timeSec: timeSec, durationSec: track.durationSec)
    }

    private static func nearest(_ points: [WaveformDetailPoint], timeSec: Double, durationSec: Double) -> WaveformDetailPoint? {
        guard !points.isEmpty else {
            return nil
        }
        let safeTime = clamped(timeSec, min: 0, max: max(0, durationSec))
        return points.min { abs($0.timeSec - safeTime) < abs($1.timeSec - safeTime) }
    }

    private static func nearest(_ points: [WaveformPeak], timeSec: Double, durationSec: Double) -> WaveformPeak? {
        guard !points.isEmpty else {
            return nil
        }
        let safeTime = clamped(timeSec, min: 0, max: max(0, durationSec))
        return points.min { abs($0.timeSec - safeTime) < abs($1.timeSec - safeTime) }
    }

    private static func nearest(_ points: [SpectralBandPoint], timeSec: Double, durationSec: Double) -> SpectralBandPoint? {
        guard !points.isEmpty else {
            return nil
        }
        let safeTime = clamped(timeSec, min: 0, max: max(0, durationSec))
        return points.min { abs($0.timeSec - safeTime) < abs($1.timeSec - safeTime) }
    }

    private static func spectralMaskingRisk(
        current: SpectralBandPoint?,
        next: SpectralBandPoint?,
        outgoingGain: Double,
        incomingGain: Double
    ) -> Double {
        guard let current, let next else {
            return 0
        }
        let overlapGain = min(outgoingGain, incomingGain)
        guard overlapGain > 0.18 else {
            return 0
        }
        let low = bandOverlap(current.low, next.low) * 0.45
        let mid = bandOverlap(current.mid, next.mid) * 0.35
        let high = bandOverlap(current.high, next.high) * 0.2
        return clamped((low + mid + high) * clamped(overlapGain * 1.35, min: 0, max: 1), min: 0, max: 1)
    }

    private static func bandOverlap(_ left: Double, _ right: Double) -> Double {
        let safeLeft = clamped(left, min: 0, max: 1)
        let safeRight = clamped(right, min: 0, max: 1)
        let shared = min(safeLeft, safeRight)
        let combined = max(0.000_001, max(safeLeft, safeRight))
        return clamped((shared / combined) * max(safeLeft, safeRight), min: 0, max: 1)
    }

    private static func scoreUpperBound(value: Double, warning: Double, reject: Double) -> Double {
        if value <= warning {
            return 1
        }
        guard reject > warning else {
            return 0
        }
        return clamped(1 - (value - warning) / (reject - warning), min: 0, max: 1)
    }

    private static func scoreLowerBound(value: Double, warning: Double, reject: Double) -> Double {
        if value >= warning {
            return 1
        }
        guard warning > reject else {
            return 0
        }
        return clamped((value - reject) / (warning - reject), min: 0, max: 1)
    }

    private static func loudnessDelta(currentAnalysis: TrackAnalysis?, nextAnalysis: TrackAnalysis?) -> Double {
        guard
            let current = currentAnalysis?.loudness,
            let next = nextAnalysis?.loudness,
            current.confidence >= 0.45,
            next.confidence >= 0.45
        else {
            return 0
        }
        return abs(current.integratedRMSDb - next.integratedRMSDb)
    }

    private static func headroomMargin(currentAnalysis: TrackAnalysis?, nextAnalysis: TrackAnalysis?) -> Double {
        guard
            let current = currentAnalysis?.loudness,
            let next = nextAnalysis?.loudness,
            current.confidence >= 0.45,
            next.confidence >= 0.45
        else {
            return 12
        }
        return min(current.headroomDb, next.headroomDb)
    }

    private static func gain(db: Double) -> Double {
        guard db.isFinite else {
            return 1
        }
        return pow(10, db / 20)
    }

    private static func db(_ linear: Double) -> Double {
        guard linear.isFinite, linear > 0 else {
            return -60
        }
        return max(-60, 20 * log10(linear))
    }

    private static func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(maxValue, Swift.max(minValue, value.isFinite ? value : minValue))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }

    private static func formatDb(_ value: Double) -> String {
        "\(String(format: "%.1f", value)) dB"
    }

    private static func formatPercent(_ value: Double) -> String {
        "\(Int((clamped(value, min: 0, max: 1) * 100).rounded()))%"
    }
}
