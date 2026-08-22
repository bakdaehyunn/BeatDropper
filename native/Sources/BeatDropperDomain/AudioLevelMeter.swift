/// A presentation-safe snapshot of an audio level. Measurement and smoothing
/// algorithms live in BeatDropperDSP; the playback session owns only the value.
public struct AudioLevelMeter: Equatable, Sendable {
    public var rms: Double
    public var peak: Double
    public var rmsDb: Double
    public var peakDb: Double
    public var clipped: Bool

    public init(rms: Double, peak: Double, rmsDb: Double, peakDb: Double, clipped: Bool) {
        self.rms = rms
        self.peak = peak
        self.rmsDb = rmsDb
        self.peakDb = peakDb
        self.clipped = clipped
    }

    public static let silence = AudioLevelMeter(
        rms: 0,
        peak: 0,
        rmsDb: -60,
        peakDb: -60,
        clipped: false
    )
}
