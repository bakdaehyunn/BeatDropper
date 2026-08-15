import AVFoundation
import AudioToolbox
import BeatDropperCore
import Foundation
import Testing

struct NativePlaybackDSPRenderTests {
    @Test func appleEQAppliesBandsAndTransitionFilter() throws {
        let sampleRate = 48_000.0
        let low = sine(frequency: 80, sampleRate: sampleRate)
        let mid = sine(frequency: 1_000, sampleRate: sampleRate)
        let high = sine(frequency: 8_000, sampleRate: sampleRate)

        func renderThreeBand(_ samples: [Float]) throws -> [Float] {
            try render(samples: samples, sampleRate: sampleRate) { engine, player, format in
                let eq = AVAudioUnitEQ(numberOfBands: 3)
                eq.globalGain = 3
                eq.bands[0].filterType = .lowShelf
                eq.bands[0].frequency = 200
                eq.bands[0].gain = 6
                eq.bands[0].bypass = false
                eq.bands[1].filterType = .parametric
                eq.bands[1].frequency = 1_000
                eq.bands[1].bandwidth = 1
                eq.bands[1].gain = -6
                eq.bands[1].bypass = false
                eq.bands[2].filterType = .highShelf
                eq.bands[2].frequency = 6_000
                eq.bands[2].gain = 6
                eq.bands[2].bypass = false
                engine.attach(eq)
                engine.connect(player, to: eq, format: format)
                engine.connect(eq, to: engine.mainMixerNode, format: format)
            }
        }

        let boostedLow = try renderThreeBand(low)
        let reducedMid = try renderThreeBand(mid)
        let boostedHigh = try renderThreeBand(high)
        let rejectedLow = try render(samples: low, sampleRate: sampleRate) { engine, player, format in
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .highPass
            eq.bands[0].frequency = 1_000
            eq.bands[0].bypass = false
            engine.attach(eq)
            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
        }

        #expect(levelDeltaDb(input: low, output: boostedLow) > 7)
        #expect(levelDeltaDb(input: mid, output: reducedMid) < 0)
        #expect(levelDeltaDb(input: high, output: boostedHigh) > 7)
        #expect(levelDeltaDb(input: low, output: rejectedLow) < -20)
    }

    @Test func appleEQNeutralBypassPreservesPCM() throws {
        let sampleRate = 48_000.0
        let input = sine(frequency: 997, sampleRate: sampleRate)
        let output = try render(samples: input, sampleRate: sampleRate) { engine, player, format in
            let eq = AVAudioUnitEQ(numberOfBands: 4)
            eq.globalGain = 0
            for band in eq.bands {
                band.gain = 0
                band.bypass = true
            }
            engine.attach(eq)
            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
        }
        #expect(abs(levelDeltaDb(input: input, output: output)) < 0.01)
    }

    @Test func applePeakLimiterRespectsConfiguredCeilingChain() throws {
        let sampleRate = 48_000.0
        let input = Array(repeating: Float(1), count: 48_000)
        let ceilingDb = -1.0
        let output = try render(samples: input, sampleRate: sampleRate) { engine, player, format in
            let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_PeakLimiter,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            ))
            let ceilingMixer = AVAudioMixerNode()
            engine.attach(limiter)
            engine.attach(ceilingMixer)
            engine.connect(player, to: limiter, format: format)
            engine.connect(limiter, to: ceilingMixer, format: format)
            engine.connect(ceilingMixer, to: engine.mainMixerNode, format: format)
            ceilingMixer.outputVolume = Float(PlaybackDSPResolver.linearGain(db: ceilingDb))
            AudioUnitSetParameter(
                limiter.audioUnit,
                kLimiterParam_PreGain,
                kAudioUnitScope_Global,
                0,
                Float(-ceilingDb),
                0
            )
        }
        let peak = output.dropFirst(4_096).map { abs(Double($0)) }.max() ?? 0
        let ceiling = PlaybackDSPResolver.linearGain(db: ceilingDb)

        #expect(peak <= ceiling + 0.01)
        #expect(peak > 0.75)
    }

    @Test func timePitchChangesDurationWithoutChangingPitch() throws {
        let sampleRate = 48_000.0
        let sourceFrequency = 440.0
        let sourceFrames = 48_000
        let rate = 1.1
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ))
        let source = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sourceFrames)
        ))
        source.frameLength = AVAudioFrameCount(sourceFrames)
        let sourceData = try #require(source.floatChannelData?[0])
        for index in 0..<sourceFrames {
            sourceData[index] = Float(sin(2 * .pi * sourceFrequency * Double(index) / sampleRate) * 0.35)
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        timePitch.rate = Float(rate)
        timePitch.pitch = 0
        timePitch.overlap = 8

        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 4_096
        )
        player.scheduleBuffer(source)
        try engine.start()
        player.play()

        var rendered: [Float] = []
        let expectedFrames = Int(Double(sourceFrames) / rate)
        while rendered.count < expectedFrames {
            let requested = min(4_096, expectedFrames - rendered.count)
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: AVAudioFrameCount(requested)
            ))
            let status = try engine.renderOffline(AVAudioFrameCount(requested), to: buffer)
            guard status == .success else {
                continue
            }
            let channel = try #require(buffer.floatChannelData?[0])
            rendered.append(contentsOf: (0..<Int(buffer.frameLength)).map { channel[$0] })
        }
        player.stop()
        engine.stop()

        let firstSignal = rendered.firstIndex { abs($0) > 0.01 } ?? 0
        let stableStart = min(rendered.count, firstSignal + 4_096)
        let stableEnd = max(stableStart, rendered.count - 4_096)
        let stable = Array(rendered[stableStart..<stableEnd])
        let measuredFrequency = zeroCrossingFrequency(samples: stable, sampleRate: sampleRate)

        #expect(abs(Double(rendered.count) - Double(sourceFrames) / rate) < 4_096)
        #expect(abs(measuredFrequency - sourceFrequency) < 5)
    }

    private func zeroCrossingFrequency(samples: [Float], sampleRate: Double) -> Double {
        guard samples.count >= 2 else {
            return 0
        }
        var positiveCrossings = 0
        for index in 1..<samples.count where samples[index - 1] <= 0 && samples[index] > 0 {
            positiveCrossings += 1
        }
        return Double(positiveCrossings) * sampleRate / Double(samples.count)
    }

    private func sine(frequency: Double, sampleRate: Double, frameCount: Int = 48_000) -> [Float] {
        (0..<frameCount).map { index in
            Float(sin(2 * .pi * frequency * Double(index) / sampleRate) * 0.25)
        }
    }

    private func render(
        samples: [Float],
        sampleRate: Double,
        connect: (AVAudioEngine, AVAudioPlayerNode, AVAudioFormat) -> Void
    ) throws -> [Float] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let source = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ))
        source.frameLength = AVAudioFrameCount(samples.count)
        let sourceData = try #require(source.floatChannelData?[0])
        for index in samples.indices {
            sourceData[index] = samples[index]
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        connect(engine, player, format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        player.scheduleBuffer(source)
        try engine.start()
        player.play()

        var rendered: [Float] = []
        while rendered.count < samples.count {
            let requested = min(4_096, samples.count - rendered.count)
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: AVAudioFrameCount(requested)
            ))
            let status = try engine.renderOffline(AVAudioFrameCount(requested), to: buffer)
            guard status == .success else {
                continue
            }
            let channel = try #require(buffer.floatChannelData?[0])
            rendered.append(contentsOf: (0..<Int(buffer.frameLength)).map { channel[$0] })
        }
        player.stop()
        engine.stop()
        return rendered
    }

    private func levelDeltaDb(input: [Float], output: [Float]) -> Double {
        let skip = min(4_096, input.count / 4)
        return db(rms(Array(output.dropFirst(skip)))) - db(rms(Array(input.dropFirst(skip))))
    }

    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count)))
    }

    private func db(_ value: Double) -> Double {
        20 * log10(max(0.000_001, value))
    }
}
