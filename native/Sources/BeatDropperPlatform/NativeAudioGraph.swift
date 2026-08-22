import AVFoundation
import AudioToolbox
import Foundation

/// Owns the AVFoundation node graph and deck topology. Playback coordination
/// remains in `NativeAudioEngine`; concrete graph lifetime is isolated here.
@MainActor
final class NativeAudioGraph {
    let engine = AVAudioEngine()
    let deckA = Deck(slot: .a)
    let deckB = Deck(slot: .b)
    let masterDSPMixer = AVAudioMixerNode()
    let masterOutputMixer = AVAudioMixerNode()
    let peakLimiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    var activeSlot: DeckSlot = .a

    init() {
        attach(deck: deckA)
        attach(deck: deckB)
        engine.attach(masterDSPMixer)
        engine.attach(masterOutputMixer)
        engine.attach(peakLimiter)
        engine.connect(deckA.mixer, to: masterDSPMixer, format: nil)
        engine.connect(deckB.mixer, to: masterDSPMixer, format: nil)
        engine.connect(masterDSPMixer, to: peakLimiter, format: nil)
        engine.connect(peakLimiter, to: masterOutputMixer, format: nil)
        engine.connect(masterOutputMixer, to: engine.mainMixerNode, format: nil)
        deckA.mixer.outputVolume = 1
        deckB.mixer.outputVolume = 0
    }

    var activeDeck: Deck { deck(for: activeSlot) }
    var inactiveDeck: Deck { deck(for: activeSlot.other) }

    func deck(for slot: DeckSlot) -> Deck {
        switch slot {
        case .a: deckA
        case .b: deckB
        }
    }

    func startIfNeeded() throws {
        if !engine.isRunning { try engine.start() }
    }

    func setMasterGain(_ gain: Double) {
        engine.mainMixerNode.outputVolume = Float(gain)
    }

    private func attach(deck: Deck) {
        engine.attach(deck.node)
        engine.attach(deck.timePitch)
        engine.attach(deck.eq)
        engine.attach(deck.mixer)
        engine.connect(deck.node, to: deck.timePitch, format: nil)
        engine.connect(deck.timePitch, to: deck.eq, format: nil)
        engine.connect(deck.eq, to: deck.mixer, format: nil)
    }
}
