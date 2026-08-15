import Foundation

public enum PlaybackDeckRole: Sendable {
    case outgoing
    case incoming
}

public struct PlaybackDeckDSPSettings: Equatable, Sendable {
    public var gainDb: Double
    public var lowEQDb: Double
    public var midEQDb: Double
    public var highEQDb: Double
    public var filterMode: MixFilterMode
    public var filterStartHz: Double?
    public var filterEndHz: Double?
    public var playbackRate: Double

    public init(
        gainDb: Double,
        lowEQDb: Double,
        midEQDb: Double,
        highEQDb: Double,
        filterMode: MixFilterMode,
        filterStartHz: Double?,
        filterEndHz: Double?,
        playbackRate: Double
    ) {
        self.gainDb = gainDb
        self.lowEQDb = lowEQDb
        self.midEQDb = midEQDb
        self.highEQDb = highEQDb
        self.filterMode = filterMode
        self.filterStartHz = filterStartHz
        self.filterEndHz = filterEndHz
        self.playbackRate = playbackRate
    }

    public static let neutral = PlaybackDeckDSPSettings(
        gainDb: 0,
        lowEQDb: 0,
        midEQDb: 0,
        highEQDb: 0,
        filterMode: .disabled,
        filterStartHz: nil,
        filterEndHz: nil,
        playbackRate: 1
    )

    public func filterFrequency(at rawProgress: Double) -> Double? {
        guard filterMode != .disabled else {
            return nil
        }
        let fallback = filterMode == .highPass ? 20.0 : 20_000.0
        let start = Self.clampedFrequency(filterStartHz ?? filterEndHz ?? fallback)
        let end = Self.clampedFrequency(filterEndHz ?? filterStartHz ?? fallback)
        let progress = CrossfadeMath.clampedProgress(rawProgress)
        // Frequency perception is logarithmic, so filter automation should be too.
        return exp(log(start) + (log(end) - log(start)) * progress)
    }

    public func interpolated(toward target: PlaybackDeckDSPSettings, progress rawProgress: Double) -> PlaybackDeckDSPSettings {
        let progress = CrossfadeMath.clampedProgress(rawProgress)
        func value(_ start: Double, _ end: Double) -> Double {
            start + (end - start) * progress
        }
        return PlaybackDeckDSPSettings(
            gainDb: value(gainDb, target.gainDb),
            lowEQDb: value(lowEQDb, target.lowEQDb),
            midEQDb: value(midEQDb, target.midEQDb),
            highEQDb: value(highEQDb, target.highEQDb),
            filterMode: target.filterMode,
            filterStartHz: target.filterStartHz,
            filterEndHz: target.filterEndHz,
            playbackRate: value(playbackRate, target.playbackRate)
        )
    }

    private static func clampedFrequency(_ frequency: Double) -> Double {
        min(20_000, max(20, frequency.isFinite ? frequency : 20))
    }
}

public struct PlaybackMasterDSPSettings: Equatable, Sendable {
    public var softLimitEnabled: Bool
    public var ceilingDb: Double

    public init(softLimitEnabled: Bool, ceilingDb: Double) {
        self.softLimitEnabled = softLimitEnabled
        self.ceilingDb = ceilingDb
    }

    public static let neutral = PlaybackMasterDSPSettings(softLimitEnabled: false, ceilingDb: -1)
}

public enum PlaybackDSPResolver {
    public static func deckSettings(
        plan: MixPlan?,
        role: PlaybackDeckRole,
        analysis: TrackAnalysis?
    ) -> PlaybackDeckDSPSettings {
        guard let plan else {
            return .neutral
        }
        let controls = plan.mixControls ?? .conservativeDefaults
        let requestedTrim = role == .outgoing
            ? controls.gain.outgoingTrimDb ?? 0
            : controls.gain.incomingTrimDb ?? 0
        let loudnessTrim = loudnessGainDb(controls: controls, analysis: analysis)
        let peakLimitedGain = peakLimitedGainDb(
            requestedGainDb: requestedTrim + loudnessTrim,
            controls: controls,
            analysis: analysis
        )

        return PlaybackDeckDSPSettings(
            gainDb: rounded(clamped(peakLimitedGain, min: -12, max: 6)),
            lowEQDb: rounded(clamped(
                role == .outgoing ? controls.eq.outgoingLowDb ?? 0 : controls.eq.incomingLowDb ?? 0,
                min: -12,
                max: 6
            )),
            midEQDb: rounded(clamped(
                role == .outgoing ? controls.eq.outgoingMidDb ?? 0 : controls.eq.incomingMidDb ?? 0,
                min: -12,
                max: 6
            )),
            highEQDb: rounded(clamped(
                role == .outgoing ? controls.eq.outgoingHighDb ?? 0 : controls.eq.incomingHighDb ?? 0,
                min: -12,
                max: 6
            )),
            filterMode: role == .outgoing ? controls.filter.outgoingMode : controls.filter.incomingMode,
            filterStartHz: sanitizedFrequency(
                role == .outgoing ? controls.filter.outgoingStartHz : controls.filter.incomingStartHz
            ),
            filterEndHz: sanitizedFrequency(
                role == .outgoing ? controls.filter.outgoingEndHz : controls.filter.incomingEndHz
            ),
            playbackRate: role == .incoming && plan.tempoSync.enabled
                ? rounded(clamped(plan.tempoSync.targetRate ?? 1, min: 0.85, max: 1.15))
                : 1
        )
    }

    public static func masterSettings(plan: MixPlan?) -> PlaybackMasterDSPSettings {
        guard let protection = plan?.mixControls?.clipProtection else {
            return .neutral
        }
        return PlaybackMasterDSPSettings(
            softLimitEnabled: protection.enabled && protection.mode == .softLimit,
            ceilingDb: rounded(clamped(protection.ceilingDb ?? -1, min: -6, max: -0.1))
        )
    }

    public static func linearGain(db: Double) -> Double {
        guard db.isFinite else {
            return 1
        }
        return pow(10, db / 20)
    }

    private static func loudnessGainDb(controls: MixControlPlan, analysis: TrackAnalysis?) -> Double {
        guard
            let target = controls.loudness.targetIntegratedLufs,
            let loudness = analysis?.loudness,
            loudness.confidence >= 0.45,
            let measured = loudness.integratedLUFS,
            measured.isFinite
        else {
            return 0
        }
        return clamped(target - measured, min: -6, max: 6)
    }

    private static func peakLimitedGainDb(
        requestedGainDb: Double,
        controls: MixControlPlan,
        analysis: TrackAnalysis?
    ) -> Double {
        guard
            let maximumPeak = controls.loudness.maxPeakDb,
            let truePeak = analysis?.loudness?.truePeakDb,
            truePeak.isFinite
        else {
            return requestedGainDb
        }
        return min(requestedGainDb, maximumPeak - truePeak)
    }

    private static func sanitizedFrequency(_ value: Double?) -> Double? {
        value.map { rounded(clamped($0, min: 20, max: 20_000)) }
    }

    private static func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(maxValue, Swift.max(minValue, value.isFinite ? value : minValue))
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}

/// Deterministic reference renderer used to verify planner-to-playback DSP behavior.
/// The real-time engine uses Apple audio units, while this implementation gives tests
/// a platform-independent PCM oracle for gain, EQ, filters, fades, and peak ceilings.
public enum PlaybackDSPReferenceRenderer {
    public static func renderDeck(
        samples: [Float],
        sampleRate: Double,
        settings: PlaybackDeckDSPSettings,
        filterProgress: Double
    ) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else {
            return []
        }
        var processors = [
            Biquad(coefficients: lowShelf(sampleRate: sampleRate, frequency: 200, gainDb: settings.lowEQDb)),
            Biquad(coefficients: peaking(sampleRate: sampleRate, frequency: 1_000, gainDb: settings.midEQDb, q: 0.8)),
            Biquad(coefficients: highShelf(sampleRate: sampleRate, frequency: 6_000, gainDb: settings.highEQDb))
        ]
        if let frequency = settings.filterFrequency(at: filterProgress) {
            let coefficients = settings.filterMode == .highPass
                ? highPass(sampleRate: sampleRate, frequency: frequency)
                : lowPass(sampleRate: sampleRate, frequency: frequency)
            processors.append(Biquad(coefficients: coefficients))
        }
        let gain = PlaybackDSPResolver.linearGain(db: settings.gainDb)
        return samples.map { sample in
            var output = Double(sample)
            for index in processors.indices {
                output = processors[index].process(output)
            }
            return Float(output * gain)
        }
    }

    public static func mix(
        outgoing: [Float],
        incoming: [Float],
        progress: Double,
        master: PlaybackMasterDSPSettings
    ) -> [Float] {
        let gains = CrossfadeMath.equalPowerGains(progress: progress)
        let count = min(outgoing.count, incoming.count)
        let ceiling = PlaybackDSPResolver.linearGain(db: master.ceilingDb)
        return (0..<count).map { index in
            let mixed = Double(outgoing[index]) * gains.outgoing + Double(incoming[index]) * gains.incoming
            guard master.softLimitEnabled else {
                return Float(mixed)
            }
            // Smooth bounded transfer with an exact configured output ceiling.
            return Float(tanh(mixed / max(0.000_001, ceiling)) * ceiling)
        }
    }

    private struct Coefficients {
        var b0: Double
        var b1: Double
        var b2: Double
        var a1: Double
        var a2: Double
    }

    private struct Biquad {
        var coefficients: Coefficients
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0

        mutating func process(_ sample: Double) -> Double {
            let output = coefficients.b0 * sample + coefficients.b1 * x1 + coefficients.b2 * x2
                - coefficients.a1 * y1 - coefficients.a2 * y2
            x2 = x1
            x1 = sample
            y2 = y1
            y1 = output
            return output
        }
    }

    private static func lowShelf(sampleRate: Double, frequency: Double, gainDb: Double) -> Coefficients {
        shelf(sampleRate: sampleRate, frequency: frequency, gainDb: gainDb, high: false)
    }

    private static func highShelf(sampleRate: Double, frequency: Double, gainDb: Double) -> Coefficients {
        shelf(sampleRate: sampleRate, frequency: frequency, gainDb: gainDb, high: true)
    }

    private static func shelf(sampleRate: Double, frequency: Double, gainDb: Double, high: Bool) -> Coefficients {
        let amplitude = pow(10, gainDb / 40)
        let omega = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cosine = cos(omega)
        let sine = sin(omega)
        let alpha = sine / 2 * sqrt(2)
        let beta = 2 * sqrt(amplitude) * alpha
        let b0: Double
        let b1: Double
        let b2: Double
        let a0: Double
        let a1: Double
        let a2: Double
        if high {
            b0 = amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta)
            b1 = -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine)
            b2 = amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta)
            a0 = (amplitude + 1) - (amplitude - 1) * cosine + beta
            a1 = 2 * ((amplitude - 1) - (amplitude + 1) * cosine)
            a2 = (amplitude + 1) - (amplitude - 1) * cosine - beta
        } else {
            b0 = amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + beta)
            b1 = 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine)
            b2 = amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - beta)
            a0 = (amplitude + 1) + (amplitude - 1) * cosine + beta
            a1 = -2 * ((amplitude - 1) + (amplitude + 1) * cosine)
            a2 = (amplitude + 1) + (amplitude - 1) * cosine - beta
        }
        return normalized(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    private static func peaking(sampleRate: Double, frequency: Double, gainDb: Double, q: Double) -> Coefficients {
        let amplitude = pow(10, gainDb / 40)
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        return normalized(
            b0: 1 + alpha * amplitude,
            b1: -2 * cos(omega),
            b2: 1 - alpha * amplitude,
            a0: 1 + alpha / amplitude,
            a1: -2 * cos(omega),
            a2: 1 - alpha / amplitude
        )
    }

    private static func lowPass(sampleRate: Double, frequency: Double) -> Coefficients {
        pass(sampleRate: sampleRate, frequency: frequency, high: false)
    }

    private static func highPass(sampleRate: Double, frequency: Double) -> Coefficients {
        pass(sampleRate: sampleRate, frequency: frequency, high: true)
    }

    private static func pass(sampleRate: Double, frequency: Double, high: Bool) -> Coefficients {
        let omega = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cosine = cos(omega)
        let alpha = sin(omega) / (2 * 0.707)
        let b0 = (high ? 1 + cosine : 1 - cosine) / 2
        let b1 = high ? -(1 + cosine) : 1 - cosine
        let b2 = b0
        return normalized(b0: b0, b1: b1, b2: b2, a0: 1 + alpha, a1: -2 * cosine, a2: 1 - alpha)
    }

    private static func normalized(
        b0: Double,
        b1: Double,
        b2: Double,
        a0: Double,
        a1: Double,
        a2: Double
    ) -> Coefficients {
        Coefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}
