import BeatDropperCore
import Foundation
import Testing

struct NativeDSPAnalyzerTests {
    @Test func spectralBandsSeparateLowAndHighFrequencyEnergy() {
        let sampleRate = 44_100.0
        let lowAnalysis = analyze(samples: sineWave(frequency: 80, durationSec: 2, sampleRate: sampleRate), sampleRate: sampleRate)
        let highAnalysis = analyze(samples: sineWave(frequency: 8_000, durationSec: 2, sampleRate: sampleRate), sampleRate: sampleRate)

        #expect(average(lowAnalysis.spectralBands.map(\.low)) > average(lowAnalysis.spectralBands.map(\.high)) * 2)
        #expect(average(highAnalysis.spectralBands.map(\.high)) > average(highAnalysis.spectralBands.map(\.low)) * 2)
        #expect(lowAnalysis.analysisQuality.spectralBands > 0)
        #expect(highAnalysis.analysisQuality.spectralBands > 0)
    }

    @Test func pulseTrainBuildsTransientMarkersAndBeatGrid() {
        let sampleRate = 1_000.0
        let samples = pulseTrain(bpm: 120, durationSec: 16, sampleRate: sampleRate)
        let analysis = NativeDSPAnalyzer().analyze(
            track: Track(id: "pulse-track", title: "Pulse", durationSec: 16, format: .wav, bpm: 120),
            buffer: PCMAnalysisBuffer(samples: samples, sampleRate: sampleRate, durationSec: 16),
            generatedAt: "2026-05-25T00:00:00Z"
        )

        #expect(analysis.bpm == 120)
        #expect(analysis.transientMarkers.count >= 12)
        #expect(analysis.beatGridSec.count >= 24)
        #expect(!analysis.barGrid.isEmpty)
        #expect(analysis.cueCandidates.contains { $0.type == .firstDownbeat })
    }

    @Test func stableRMSFrequencyChangesBuildSpectralFluxTransients() {
        let sampleRate = 44_100.0
        let samples = frequencyStepSignal(
            frequencies: [120, 8_000, 120, 8_000],
            segmentDurationSec: 2,
            sampleRate: sampleRate
        )
        let analysis = analyze(samples: samples, sampleRate: sampleRate)

        #expect(analysis.analysisQuality.spectralBands > 0.1)
        #expect(analysis.transientMarkers.count >= 3)
        #expect(hasTransient(near: 2, in: analysis.transientMarkers, toleranceSec: 0.25))
        #expect(hasTransient(near: 4, in: analysis.transientMarkers, toleranceSec: 0.25))
        #expect(hasTransient(near: 6, in: analysis.transientMarkers, toleranceSec: 0.25))
    }

    @Test func phraseConfidenceHighlightsEnergySectionChanges() throws {
        let sampleRate = 1_000.0
        let samples = sectionedPulseTrain(
            bpm: 120,
            durationSec: 64,
            sampleRate: sampleRate,
            sectionDurationSec: 16,
            amplitudes: [0.35, 0.95, 0.35, 0.95]
        )
        let analysis = NativeDSPAnalyzer().analyze(
            track: Track(id: "sectioned-pulse", title: "Sectioned Pulse", durationSec: 64, format: .wav, bpm: 120),
            buffer: PCMAnalysisBuffer(samples: samples, sampleRate: sampleRate, durationSec: 64),
            generatedAt: "2026-05-25T00:00:00Z"
        )

        let introMarker = try #require(analysis.phraseMarkers.first { $0.index == 0 })
        let risingSectionMarker = try #require(analysis.phraseMarkers.first { $0.index == 1 })
        let fallingSectionMarker = try #require(analysis.phraseMarkers.first { $0.index == 2 })

        #expect(risingSectionMarker.confidence > introMarker.confidence + 0.05)
        #expect(fallingSectionMarker.confidence > introMarker.confidence + 0.05)
        #expect(analysis.phraseMarkers.sorted { $0.confidence > $1.confidence }.prefix(3).contains { $0.index == 2 })
    }

    @Test func downbeatPhasePrefersLowBandKickOverLouderHighBandBackbeat() throws {
        let sampleRate = 44_100.0
        let samples = kickAndBackbeatPattern(bpm: 120, durationSec: 16, sampleRate: sampleRate)
        let analysis = NativeDSPAnalyzer().analyze(
            track: Track(id: "kick-backbeat", title: "Kick Backbeat", durationSec: 16, format: .wav, bpm: 120),
            buffer: PCMAnalysisBuffer(samples: samples, sampleRate: sampleRate, durationSec: 16),
            generatedAt: "2026-05-25T00:00:00Z"
        )

        let firstBar = try #require(analysis.barGrid.first)
        #expect(abs(firstBar.startSec) <= 0.18)
        #expect(firstBar.beatIndex == 0)
        #expect(analysis.analysisQuality.beatGrid >= 0.4)
    }

    @Test func silenceProducesLowConfidenceWarnings() {
        let analysis = analyze(samples: Array(repeating: 0, count: 2_000), sampleRate: 1_000)

        #expect(analysis.bpm == nil)
        #expect(analysis.analysisConfidence < 0.6)
        #expect(analysis.analysisWarnings.contains(.bpmUnavailable))
        #expect(analysis.analysisWarnings.contains(.flatEnergy))
    }

    private func analyze(samples: [Float], sampleRate: Double) -> TrackAnalysis {
        let durationSec = Double(samples.count) / sampleRate
        return NativeDSPAnalyzer().analyze(
            track: Track(id: UUID().uuidString, title: "Synthetic", durationSec: durationSec, format: .wav),
            buffer: PCMAnalysisBuffer(samples: samples, sampleRate: sampleRate, durationSec: durationSec),
            generatedAt: "2026-05-25T00:00:00Z"
        )
    }

    private func sineWave(frequency: Double, durationSec: Double, sampleRate: Double) -> [Float] {
        let sampleCount = Int(durationSec * sampleRate)
        return (0..<sampleCount).map { index in
            Float(sin((2 * Double.pi * frequency * Double(index)) / sampleRate) * 0.8)
        }
    }

    private func frequencyStepSignal(frequencies: [Double], segmentDurationSec: Double, sampleRate: Double) -> [Float] {
        var samples: [Float] = []
        for frequency in frequencies {
            samples.append(contentsOf: sineWave(
                frequency: frequency,
                durationSec: segmentDurationSec,
                sampleRate: sampleRate
            ))
        }
        return samples
    }

    private func sectionedPulseTrain(
        bpm: Double,
        durationSec: Double,
        sampleRate: Double,
        sectionDurationSec: Double,
        amplitudes: [Double]
    ) -> [Float] {
        let sampleCount = Int(durationSec * sampleRate)
        let intervalSamples = Int((60 / bpm) * sampleRate)
        var samples = Array(repeating: Float(0), count: sampleCount)
        var start = 0
        while start < sampleCount {
            let timeSec = Double(start) / sampleRate
            let sectionIndex = min(
                max(0, Int(timeSec / sectionDurationSec)),
                max(0, amplitudes.count - 1)
            )
            let amplitude = amplitudes.isEmpty ? 0.8 : amplitudes[sectionIndex]
            for offset in 0..<30 where start + offset < sampleCount {
                samples[start + offset] = Float(amplitude * (1 - (Double(offset) / 30)))
            }
            start += intervalSamples
        }
        return samples
    }

    private func kickAndBackbeatPattern(bpm: Double, durationSec: Double, sampleRate: Double) -> [Float] {
        let sampleCount = Int(durationSec * sampleRate)
        let beatIntervalSec = 60 / bpm
        var samples = Array(repeating: Float(0), count: sampleCount)
        var beatIndex = 0
        var beatTimeSec = 0.0
        while beatTimeSec < durationSec {
            let beatInBar = beatIndex % 4
            if beatInBar == 0 {
                addBurst(
                    to: &samples,
                    sampleRate: sampleRate,
                    startSec: beatTimeSec,
                    frequency: 90,
                    amplitude: 0.38,
                    durationSec: 0.11
                )
            } else if beatInBar == 1 {
                addBurst(
                    to: &samples,
                    sampleRate: sampleRate,
                    startSec: beatTimeSec,
                    frequency: 8_000,
                    amplitude: 1.0,
                    durationSec: 0.08
                )
            } else {
                addBurst(
                    to: &samples,
                    sampleRate: sampleRate,
                    startSec: beatTimeSec,
                    frequency: 240,
                    amplitude: 0.24,
                    durationSec: 0.06
                )
            }
            beatIndex += 1
            beatTimeSec += beatIntervalSec
        }
        return samples
    }

    private func addBurst(
        to samples: inout [Float],
        sampleRate: Double,
        startSec: Double,
        frequency: Double,
        amplitude: Double,
        durationSec: Double
    ) {
        let startIndex = Int(startSec * sampleRate)
        let count = Int(durationSec * sampleRate)
        guard count > 0, startIndex < samples.count else {
            return
        }
        for offset in 0..<count where startIndex + offset < samples.count {
            let envelope = 1 - (Double(offset) / Double(count))
            let sample = sin((2 * Double.pi * frequency * Double(offset)) / sampleRate) * amplitude * envelope
            samples[startIndex + offset] += Float(sample)
        }
    }

    private func pulseTrain(bpm: Double, durationSec: Double, sampleRate: Double) -> [Float] {
        let sampleCount = Int(durationSec * sampleRate)
        let intervalSamples = Int((60 / bpm) * sampleRate)
        var samples = Array(repeating: Float(0), count: sampleCount)
        var start = 0
        while start < sampleCount {
            for offset in 0..<30 where start + offset < sampleCount {
                samples[start + offset] = Float(1 - (Double(offset) / 30))
            }
            start += intervalSamples
        }
        return samples
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func hasTransient(near expectedSec: Double, in markers: [TransientMarker], toleranceSec: Double) -> Bool {
        markers.contains { abs($0.timeSec - expectedSec) <= toleranceSec }
    }

}
