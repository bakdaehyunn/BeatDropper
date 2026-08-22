import AVFoundation
import BeatDropperDomain
import BeatDropperDSP
import Foundation

struct PlaybackRecoverySnapshot {
    var state: NativeAudioEngine.PlaybackState
    var activeSlot: DeckSlot
    var active: DeckRecoverySnapshot
    var inactive: DeckRecoverySnapshot
    var crossfadeProgress: Double
    var fadeDurationSec: TimeInterval
    var fadeTargetSlot: DeckSlot?
    var stateBeforePause: NativeAudioEngine.PlaybackState
    var pausedCrossfadeProgress: Double?
    var masterDSPSettings: PlaybackMasterDSPSettings
}

struct DeckRecoverySnapshot {
    var url: URL?
    var track: Track?
    var positionSec: TimeInterval
    var volume: Float
    var appliedDSPSettings: PlaybackDeckDSPSettings
    var targetDSPSettings: PlaybackDeckDSPSettings
    var transitionStartDSPSettings: PlaybackDeckDSPSettings

    init(deck: Deck) {
        url = deck.url
        track = deck.track
        positionSec = deck.positionSec()
        volume = deck.mixer.outputVolume
        appliedDSPSettings = deck.appliedDSPSettings
        targetDSPSettings = deck.targetDSPSettings
        transitionStartDSPSettings = deck.transitionStartDSPSettings
    }
}

enum DeckSlot {
    case a
    case b

    var other: DeckSlot { self == .a ? .b : .a }
}

/// Owns one AVFoundation deck graph and its scheduling/position state.
final class Deck {
    let slot: DeckSlot
    let node = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    let eq = AVAudioUnitEQ(numberOfBands: 4)
    let mixer = AVAudioMixerNode()
    var file: AVAudioFile?
    var url: URL?
    var track: Track?
    var startFrame: AVAudioFramePosition = 0
    var lastKnownPositionSec: Double = 0
    var scheduled = false
    var appliedDSPSettings = PlaybackDeckDSPSettings.neutral
    var targetDSPSettings = PlaybackDeckDSPSettings.neutral
    var transitionStartDSPSettings = PlaybackDeckDSPSettings.neutral

    var lowBand: AVAudioUnitEQFilterParameters { eq.bands[0] }
    var midBand: AVAudioUnitEQFilterParameters { eq.bands[1] }
    var highBand: AVAudioUnitEQFilterParameters { eq.bands[2] }
    var filterBand: AVAudioUnitEQFilterParameters { eq.bands[3] }

    init(slot: DeckSlot) {
        self.slot = slot
        lowBand.filterType = .lowShelf
        lowBand.frequency = 200
        lowBand.bandwidth = 1
        lowBand.gain = 0
        lowBand.bypass = false
        midBand.filterType = .parametric
        midBand.frequency = 1_000
        midBand.bandwidth = 1
        midBand.gain = 0
        midBand.bypass = false
        highBand.filterType = .highShelf
        highBand.frequency = 6_000
        highBand.bandwidth = 1
        highBand.gain = 0
        highBand.bypass = false
        filterBand.bypass = true
    }

    func stopAndClearSchedule() {
        node.stop()
        scheduled = false
    }

    func clearFile() {
        file = nil
        url = nil
        track = nil
        startFrame = 0
        lastKnownPositionSec = 0
    }

    func resetDSP() {
        appliedDSPSettings = .neutral
        targetDSPSettings = .neutral
        transitionStartDSPSettings = .neutral
        eq.globalGain = 0
        lowBand.gain = 0
        midBand.gain = 0
        highBand.gain = 0
        filterBand.bypass = true
        timePitch.rate = 1
        timePitch.pitch = 0
    }

    func positionSec() -> Double {
        guard let file else { return 0 }
        let baseOffset = Double(startFrame) / file.processingFormat.sampleRate
        guard node.isPlaying,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else {
            return lastKnownPositionSec
        }
        lastKnownPositionSec = baseOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
        return lastKnownPositionSec
    }
}
