import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct PlaybackMathTests {
    @Test func equalPowerCrossfadeStartsAndEndsAtExpectedGains() {
        let start = CrossfadeMath.equalPowerGains(progress: 0)
        let end = CrossfadeMath.equalPowerGains(progress: 1)

        #expect(isApproximately(start.outgoing, 1))
        #expect(isApproximately(start.incoming, 0))
        #expect(isApproximately(end.outgoing, 0))
        #expect(isApproximately(end.incoming, 1))
    }

    @Test func equalPowerCrossfadeKeepsMidpointFromDippingTooFar() {
        let midpoint = CrossfadeMath.equalPowerGains(progress: 0.5)

        #expect(isApproximately(midpoint.outgoing, sqrt(0.5)))
        #expect(isApproximately(midpoint.incoming, sqrt(0.5)))
    }

    @Test func equalPowerCrossfadeClampsInvalidProgress() {
        let belowRange = CrossfadeMath.equalPowerGains(progress: -4)
        let aboveRange = CrossfadeMath.equalPowerGains(progress: 4)
        let invalid = CrossfadeMath.equalPowerGains(progress: .nan)

        #expect(isApproximately(belowRange.outgoing, 1))
        #expect(isApproximately(belowRange.incoming, 0))
        #expect(isApproximately(aboveRange.outgoing, 0))
        #expect(isApproximately(aboveRange.incoming, 1))
        #expect(isApproximately(invalid.outgoing, 1))
        #expect(isApproximately(invalid.incoming, 0))
    }

    @Test func crossfadeProgressSanitizerHandlesInvalidValues() {
        #expect(CrossfadeMath.clampedProgress(-0.5) == 0)
        #expect(CrossfadeMath.clampedProgress(0.25) == 0.25)
        #expect(CrossfadeMath.clampedProgress(1.5) == 1)
        #expect(CrossfadeMath.clampedProgress(.nan) == 0)
        #expect(CrossfadeMath.clampedProgress(.infinity) == 0)
    }

    @Test func playbackPositionClampsInvalidAndOutOfRangeElapsed() {
        #expect(PlaybackPositionMath.clampedElapsed(.nan, durationSec: 120) == 0)
        #expect(PlaybackPositionMath.clampedElapsed(-10, durationSec: 120) == 0)
        #expect(PlaybackPositionMath.clampedElapsed(130, durationSec: 120) == 120)
        #expect(PlaybackPositionMath.clampedElapsed(130, durationSec: nil) == 130)
    }

    @Test func playbackPositionComputesSafeRemainingTime() {
        #expect(PlaybackPositionMath.remaining(elapsedSec: 30, durationSec: 120) == 90)
        #expect(PlaybackPositionMath.remaining(elapsedSec: 130, durationSec: 120) == 0)
        #expect(PlaybackPositionMath.remaining(elapsedSec: .infinity, durationSec: 120) == 120)
        #expect(PlaybackPositionMath.remaining(elapsedSec: 30, durationSec: nil) == 0)
    }

    @Test func levelMeterMeasuresSilenceAndClipping() {
        let silence = LevelMeterMath.measure(samples: Array(repeating: 0, count: 256))
        let clipped = LevelMeterMath.measure(samples: [0, 0.25, -0.5, 0.99])

        #expect(silence.rms == 0)
        #expect(silence.peak == 0)
        #expect(silence.rmsDb == LevelMeterMath.dbFloor)
        #expect(clipped.peak > 0.95)
        #expect(clipped.clipped == true)
    }

    @Test func levelMeterIgnoresInvalidSamples() {
        let meter = LevelMeterMath.measure(samples: [.nan, .infinity, -0.5, 0.5])

        #expect(meter.rms > 0)
        #expect(meter.peak > 0)
        #expect(meter.clipped == false)
    }

    @Test func levelMeterSmoothingAttacksFasterThanItReleases() {
        let silence = AudioLevelMeter.silence
        let loud = LevelMeterMath.measure(samples: Array(repeating: 0.8, count: 128))
        let attacked = LevelMeterMath.smooth(previous: silence, current: loud)
        let released = LevelMeterMath.smooth(previous: loud, current: silence)

        #expect(attacked.rms > 0.4)
        #expect(released.rms > attacked.rms)
        #expect(released.rms < loud.rms)
    }

    private func isApproximately(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.000_001
    }
}
