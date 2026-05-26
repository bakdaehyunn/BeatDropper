import Foundation

public struct CrossfadeGains: Equatable, Sendable {
    public var outgoing: Double
    public var incoming: Double

    public init(outgoing: Double, incoming: Double) {
        self.outgoing = outgoing
        self.incoming = incoming
    }
}

public enum CrossfadeMath {
    public static func clampedProgress(_ rawProgress: Double) -> Double {
        min(1, max(0, rawProgress.isFinite ? rawProgress : 0))
    }

    public static func equalPowerGains(progress rawProgress: Double) -> CrossfadeGains {
        let progress = clampedProgress(rawProgress)
        let angle = progress * .pi / 2

        return CrossfadeGains(
            outgoing: cos(angle),
            incoming: sin(angle)
        )
    }
}

public enum PlaybackPositionMath {
    public static func clampedElapsed(_ elapsedSec: Double, durationSec: Double?) -> Double {
        let safeElapsed = elapsedSec.isFinite ? elapsedSec : 0
        let lowerBounded = max(0, safeElapsed)
        guard let durationSec, durationSec.isFinite, durationSec > 0 else {
            return lowerBounded
        }
        return min(durationSec, lowerBounded)
    }

    public static func remaining(elapsedSec: Double, durationSec: Double?) -> Double {
        guard let durationSec, durationSec.isFinite, durationSec > 0 else {
            return 0
        }
        return max(0, durationSec - clampedElapsed(elapsedSec, durationSec: durationSec))
    }
}

public struct AudioLevelMeter: Equatable, Sendable {
    public var rms: Double
    public var peak: Double
    public var rmsDb: Double
    public var peakDb: Double
    public var clipped: Bool

    public init(
        rms: Double,
        peak: Double,
        rmsDb: Double,
        peakDb: Double,
        clipped: Bool
    ) {
        self.rms = rms
        self.peak = peak
        self.rmsDb = rmsDb
        self.peakDb = peakDb
        self.clipped = clipped
    }

    public static let silence = AudioLevelMeter(
        rms: 0,
        peak: 0,
        rmsDb: LevelMeterMath.dbFloor,
        peakDb: LevelMeterMath.dbFloor,
        clipped: false
    )
}

public enum LevelMeterMath {
    public static let dbFloor: Double = -60
    public static let dbCeiling: Double = 0

    public static func measure(samples: [Float]) -> AudioLevelMeter {
        guard !samples.isEmpty else {
            return .silence
        }

        var peak: Double = 0
        var squareSum: Double = 0
        var validCount = 0

        for sample in samples {
            let value = Double(sample)
            guard value.isFinite else {
                continue
            }

            let absolute = abs(value)
            peak = max(peak, absolute)
            squareSum += value * value
            validCount += 1
        }

        guard validCount > 0 else {
            return .silence
        }

        let rmsLinear = sqrt(squareSum / Double(validCount))
        let peakDb = decibels(for: peak)
        let rmsDb = decibels(for: rmsLinear)

        return AudioLevelMeter(
            rms: normalized(db: rmsDb),
            peak: normalized(db: peakDb),
            rmsDb: rmsDb,
            peakDb: peakDb,
            clipped: peak >= 0.98
        )
    }

    public static func smooth(
        previous: AudioLevelMeter,
        current: AudioLevelMeter,
        attack: Double = 0.72,
        release: Double = 0.22
    ) -> AudioLevelMeter {
        let rms = smoothed(previous: previous.rms, current: current.rms, attack: attack, release: release)
        let peak = smoothed(previous: previous.peak, current: current.peak, attack: attack, release: release)
        let rmsDb = decibels(forNormalized: rms)
        let peakDb = decibels(forNormalized: peak)

        return AudioLevelMeter(
            rms: rms,
            peak: peak,
            rmsDb: rmsDb,
            peakDb: peakDb,
            clipped: current.clipped
        )
    }

    private static func decibels(for linearValue: Double) -> Double {
        guard linearValue.isFinite, linearValue > 0 else {
            return dbFloor
        }
        return min(dbCeiling, max(dbFloor, 20 * log10(linearValue)))
    }

    private static func normalized(db: Double) -> Double {
        guard db.isFinite else {
            return 0
        }
        return min(1, max(0, (db - dbFloor) / (dbCeiling - dbFloor)))
    }

    private static func decibels(forNormalized normalizedValue: Double) -> Double {
        let safeValue = min(1, max(0, normalizedValue.isFinite ? normalizedValue : 0))
        return dbFloor + safeValue * (dbCeiling - dbFloor)
    }

    private static func smoothed(
        previous: Double,
        current: Double,
        attack: Double,
        release: Double
    ) -> Double {
        let safePrevious = min(1, max(0, previous.isFinite ? previous : 0))
        let safeCurrent = min(1, max(0, current.isFinite ? current : 0))
        let coefficient = safeCurrent > safePrevious ? attack : release
        let safeCoefficient = min(1, max(0, coefficient.isFinite ? coefficient : 0))
        return safePrevious + (safeCurrent - safePrevious) * safeCoefficient
    }
}
