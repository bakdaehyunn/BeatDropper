import AudioToolbox
import BeatDropperDSP
import Foundation

/// Applies resolved deterministic DSP settings to concrete AVFoundation nodes.
@MainActor
final class PlaybackDSPApplicator {
    private let graph: NativeAudioGraph
    private(set) var masterSettings = PlaybackMasterDSPSettings.neutral

    init(graph: NativeAudioGraph) {
        self.graph = graph
    }

    func configure(
        deck: Deck,
        settings target: PlaybackDeckDSPSettings,
        filterProgress: Double,
        immediate: Bool
    ) {
        let rampProgress = min(1, CrossfadeMath.clampedProgress(filterProgress) / 0.15)
        let applied = immediate
            ? target
            : deck.transitionStartDSPSettings.interpolated(toward: target, progress: rampProgress)
        deck.eq.globalGain = Float(applied.gainDb)
        deck.lowBand.gain = Float(applied.lowEQDb)
        deck.midBand.gain = Float(applied.midEQDb)
        deck.highBand.gain = Float(applied.highEQDb)
        deck.timePitch.rate = Float(applied.playbackRate)
        deck.timePitch.pitch = 0
        deck.timePitch.overlap = 8

        if let frequency = target.filterFrequency(at: filterProgress) {
            deck.filterBand.bypass = false
            deck.filterBand.filterType = target.filterMode == .highPass ? .highPass : .lowPass
            deck.filterBand.frequency = Float(frequency)
        } else {
            deck.filterBand.bypass = true
        }
        deck.appliedDSPSettings = applied
    }

    func configureMaster(_ settings: PlaybackMasterDSPSettings) {
        masterSettings = settings
        graph.peakLimiter.auAudioUnit.shouldBypassEffect = !settings.softLimitEnabled
        graph.masterOutputMixer.outputVolume = settings.softLimitEnabled
            ? Float(PlaybackDSPResolver.linearGain(db: settings.ceilingDb))
            : 1
        let preGain = settings.softLimitEnabled ? Float(-settings.ceilingDb) : 0
        AudioUnitSetParameter(
            graph.peakLimiter.audioUnit,
            kLimiterParam_PreGain,
            kAudioUnitScope_Global,
            0,
            preGain,
            0
        )
    }
}
