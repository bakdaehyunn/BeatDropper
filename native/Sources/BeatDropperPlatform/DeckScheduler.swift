import AVFoundation
import BeatDropperDomain
import BeatDropperDSP
import Foundation

/// Owns file preparation and AVAudioPlayerNode scheduling policy for a deck.
struct DeckScheduler {
    func prepare(
        deck: Deck,
        url: URL,
        track: Track,
        volume: Float,
        startOffsetSec: TimeInterval = 0
    ) throws {
        deck.stopAndClearSchedule()
        deck.file = try AVAudioFile(forReading: url)
        deck.url = url
        deck.track = track
        let safeOffset = PlaybackPositionMath.clampedElapsed(startOffsetSec, durationSec: track.durationSec)
        deck.startFrame = frameOffset(for: deck.file, startOffsetSec: safeOffset)
        deck.lastKnownPositionSec = safeOffset
        deck.mixer.outputVolume = volume
    }

    func scheduleIfNeeded(_ deck: Deck) {
        guard let file = deck.file, !deck.scheduled else { return }
        if deck.startFrame > 0 {
            let remainingFrames = AVAudioFrameCount(max(0, file.length - deck.startFrame))
            if remainingFrames > 0 {
                deck.node.scheduleSegment(
                    file,
                    startingFrame: deck.startFrame,
                    frameCount: remainingFrames,
                    at: nil
                )
            } else {
                deck.node.scheduleFile(file, at: nil)
            }
        } else {
            deck.node.scheduleFile(file, at: nil)
        }
        deck.scheduled = true
    }

    private func frameOffset(
        for file: AVAudioFile?,
        startOffsetSec: TimeInterval
    ) -> AVAudioFramePosition {
        guard let file, startOffsetSec.isFinite, startOffsetSec > 0 else { return 0 }
        let frame = AVAudioFramePosition((startOffsetSec * file.processingFormat.sampleRate).rounded())
        return min(max(0, frame), max(0, file.length - 1))
    }
}
