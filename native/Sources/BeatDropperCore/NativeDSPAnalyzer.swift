import Foundation

public struct PCMAnalysisBuffer: Sendable {
    public var samples: [Float]
    public var channelSamples: [[Float]]
    public var sampleRate: Double
    public var durationSec: Double

    public init(samples: [Float], channelSamples: [[Float]] = [], sampleRate: Double, durationSec: Double) {
        self.samples = samples
        self.channelSamples = channelSamples
        self.sampleRate = sampleRate
        self.durationSec = durationSec
    }
}

public struct NativeDSPAnalyzer: Sendable {
    public init() {}

    public func analyze(
        track: Track,
        buffer: PCMAnalysisBuffer,
        fileRevision: TrackFileRevision? = nil,
        generatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> TrackAnalysis {
        let durationSec = resolveDuration(track: track, buffer: buffer)
        let energyProfile = buildEnergyProfile(samples: buffer.samples, durationSec: durationSec)
        let waveformPeaks = buildWaveformPeaks(samples: buffer.samples, durationSec: durationSec)
        let waveformDetail = buildWaveformDetail(samples: buffer.samples, durationSec: durationSec)
        let spectralBands = buildSpectralBands(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate,
            durationSec: durationSec,
            bucketCount: waveformDetail.count
        )
        let musicalKey = estimateMusicalKey(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate,
            durationSec: durationSec
        )
        let loudness = buildLoudnessAnalysis(buffer: buffer, durationSec: durationSec)
        let stereo = buildStereoAnalysis(buffer: buffer)
        let onsetEnvelope = buildOnsetEnvelope(
            waveformDetail: waveformDetail,
            spectralBands: spectralBands,
            durationSec: durationSec
        )
        let transientMarkers = buildTransientMarkers(onsetEnvelope: onsetEnvelope, durationSec: durationSec)
        let bpmEstimate = estimateBPM(transientMarkers: transientMarkers)
        let resolvedBPM = resolveAnalysisBPM(track: track, estimate: bpmEstimate)
        let bpm = resolvedBPM.bpm
        let beatIntervalSec = bpm.map { 60 / $0 }
        let beatPhase = beatIntervalSec.map {
            resolveBeatPhaseOffset(beatIntervalSec: $0, transientMarkers: transientMarkers)
        } ?? (offsetSec: 0, confidence: 0)
        let beatGridSec = beatIntervalSec.map {
            buildBeatGrid(durationSec: durationSec, beatIntervalSec: $0, beatOffsetSec: beatPhase.offsetSec)
        } ?? []
        let downbeatGrid = buildDownbeatGrid(
            beatGridSec: beatGridSec,
            transientMarkers: transientMarkers,
            energyProfile: energyProfile,
            spectralBands: spectralBands,
            durationSec: durationSec
        )
        let beatGridQuality = beatGridSec.isEmpty ? 0 : clamped(
            (resolvedBPM.confidence * 0.44) +
                (beatPhase.confidence * 0.2) +
                (downbeatGrid.confidence * 0.24) +
                min(0.12, Double(beatGridSec.count) / 900),
            min: 0,
            max: 1
        )
        let phraseMarkers = buildPhraseMarkers(
            barGrid: downbeatGrid.barGrid,
            energyProfile: energyProfile,
            durationSec: durationSec,
            beatGridQuality: beatGridQuality,
            downbeatConfidence: downbeatGrid.confidence
        )
        let introCueSec = 0.0
        let firstDownbeatSec = downbeatGrid.downbeatsSec.first
        let outroCueSec = resolveOutroCueSec(barGrid: downbeatGrid.barGrid, durationSec: durationSec)
        let lowEnergyBreakSecRaw = findEnergyTime(
            energyProfile: energyProfile,
            durationSec: durationSec,
            findMax: false,
            startRatio: 0.35,
            endRatio: 0.8
        )
        let lowEnergyBreakSec = lowEnergyBreakSecRaw.map {
            snapToNearestBar(barGrid: downbeatGrid.barGrid, timeSec: $0) ?? $0
        }
        let highEnergyDropSecRaw = findEnergyTime(
            energyProfile: energyProfile,
            durationSec: durationSec,
            findMax: true,
            startRatio: 0.05,
            endRatio: 0.55
        )
        let highEnergyDropSec = highEnergyDropSecRaw.map {
            snapToNearestBar(barGrid: downbeatGrid.barGrid, timeSec: $0) ?? $0
        }
        let transientQuality = scoreTransientMarkerQuality(
            transientMarkers: transientMarkers,
            beatGridSec: beatGridSec,
            durationSec: durationSec,
            beatPhaseConfidence: beatPhase.confidence,
            downbeatConfidence: downbeatGrid.confidence
        )
        let analysisQuality = AnalysisQuality(
            waveformDetail: clamped(Double(waveformDetail.count) / Double(Self.waveformDetailMaxBuckets), min: 0, max: 1),
            spectralBands: clamped(Double(spectralBands.count) / Double(Self.waveformDetailMaxBuckets), min: 0, max: 1),
            transientMarkers: transientQuality,
            beatGrid: beatGridQuality,
            harmonicKey: musicalKey?.confidence ?? 0
        )
        let analysisConfidence = clamped(
            0.2 +
                (bpm == nil ? 0 : 0.22) +
                beatGridQuality * 0.2 +
                (energyProfile.count > 8 ? 0.14 : 0) +
                (waveformPeaks.count > 8 ? 0.1 : 0) +
                (spectralBands.count > 8 ? 0.08 : 0) +
                transientQuality * 0.06 +
                (musicalKey?.confidence ?? 0) * 0.03 +
                (loudness?.confidence ?? 0) * 0.03,
            min: 0,
            max: 1
        )

        return TrackAnalysis(
            trackId: track.id,
            generatedAt: generatedAt,
            source: resolvedBPM.source,
            fileRevision: fileRevision,
            bpm: bpm,
            bpmConfidence: resolvedBPM.confidence,
            beatGridSec: beatGridSec,
            downbeatsSec: downbeatGrid.downbeatsSec,
            barGrid: downbeatGrid.barGrid,
            phraseMarkers: phraseMarkers,
            introCueSec: introCueSec,
            outroCueSec: outroCueSec,
            energyProfile: energyProfile,
            waveformPeaks: waveformPeaks,
            waveformDetail: waveformDetail,
            spectralBands: spectralBands,
            transientMarkers: transientMarkers,
            cueCandidates: buildCueCandidates(
                durationSec: durationSec,
                introCueSec: introCueSec,
                firstDownbeatSec: firstDownbeatSec,
                outroCueSec: outroCueSec,
                lowEnergyBreakSec: lowEnergyBreakSec,
                highEnergyDropSec: highEnergyDropSec,
                barGrid: downbeatGrid.barGrid,
                energyProfile: energyProfile,
                spectralBands: spectralBands,
                transientMarkers: transientMarkers,
                beatGridQuality: beatGridQuality,
                downbeatConfidence: downbeatGrid.confidence,
                transientQuality: transientQuality
            ),
            musicalKey: musicalKey,
            loudness: loudness,
            stereo: stereo,
            analysisConfidence: analysisConfidence,
            analysisQuality: analysisQuality,
            analysisWarnings: buildWarnings(
                bpm: bpm,
                bpmConfidence: resolvedBPM.confidence,
                metadataMismatch: resolvedBPM.metadataMismatch,
                durationSec: durationSec,
                energyProfile: energyProfile,
                musicalKey: musicalKey,
                loudness: loudness
            )
        )
    }

    private static let waveformBuckets = 160
    private static let waveformDetailMaxBuckets = 1_200
    private static let waveformDetailBucketsPerSec = 12
    private static let energyBuckets = 64
    private static let spectralFFTSize = 2_048
    private static let minValidBPM = 60.0
    private static let maxValidBPM = 200.0
    private static let derivedBPMConfidencePriority = 0.58
    private static let bpmMismatchDelta = 3.0
    private static let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let majorKeyProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorKeyProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    private static let keyLowConfidenceThreshold = 0.35
    private static let loudnessLowConfidenceThreshold = 0.45
    private static let headroomLowThresholdDb = 1.0

    private func resolveDuration(track: Track, buffer: PCMAnalysisBuffer) -> Double {
        if buffer.durationSec.isFinite && buffer.durationSec > 0 {
            return buffer.durationSec
        }
        if buffer.sampleRate.isFinite && buffer.sampleRate > 0 {
            return Double(buffer.samples.count) / buffer.sampleRate
        }
        return max(0, track.durationSec)
    }

    private func buildWaveformPeaks(samples: [Float], durationSec: Double) -> [WaveformPeak] {
        guard !samples.isEmpty, durationSec > 0 else {
            return []
        }

        let bucketCount = min(Self.waveformBuckets, max(1, Int(durationSec * 2)))
        let samplesPerBucket = max(1, samples.count / bucketCount)

        return (0..<bucketCount).map { bucketIndex in
            let start = bucketIndex * samplesPerBucket
            let end = min(samples.count, start + samplesPerBucket)
            let stats = sampleStats(samples: samples, start: start, end: end)
            return WaveformPeak(
                timeSec: (Double(start) / Double(max(1, samples.count))) * durationSec,
                peak: clamped(stats.peak, min: 0, max: 1),
                rms: clamped(stats.rms, min: 0, max: 1)
            )
        }
    }

    private func buildEnergyProfile(samples: [Float], durationSec: Double) -> [Double] {
        guard !samples.isEmpty, durationSec > 0 else {
            return []
        }

        let bucketCount = min(Self.energyBuckets, max(1, Int(durationSec)))
        let samplesPerBucket = max(1, samples.count / bucketCount)
        let rawValues = (0..<bucketCount).map { bucketIndex in
            let start = bucketIndex * samplesPerBucket
            let end = min(samples.count, start + samplesPerBucket)
            return sampleStats(samples: samples, start: start, end: end).rms
        }
        let maxValue = max(0.000_001, rawValues.max() ?? 0)
        return rawValues.map { clamped($0 / maxValue, min: 0, max: 1) }
    }

    private func buildWaveformDetail(samples: [Float], durationSec: Double) -> [WaveformDetailPoint] {
        guard !samples.isEmpty, durationSec > 0 else {
            return []
        }

        let bucketCount = min(
            Self.waveformDetailMaxBuckets,
            max(Self.waveformBuckets, Int(durationSec * Double(Self.waveformDetailBucketsPerSec)))
        )
        let samplesPerBucket = max(1, samples.count / bucketCount)

        return (0..<bucketCount).map { bucketIndex in
            let start = bucketIndex * samplesPerBucket
            let end = min(samples.count, start + samplesPerBucket)
            let stats = sampleStats(samples: samples, start: start, end: end)
            return WaveformDetailPoint(
                timeSec: (Double(start) / Double(max(1, samples.count))) * durationSec,
                peak: clamped(stats.peak, min: 0, max: 1),
                rms: clamped(stats.rms, min: 0, max: 1),
                min: clamped(stats.min, min: -1, max: 1),
                max: clamped(stats.max, min: -1, max: 1)
            )
        }
    }

    private func buildSpectralBands(
        samples: [Float],
        sampleRate: Double,
        durationSec: Double,
        bucketCount: Int
    ) -> [SpectralBandPoint] {
        guard
            !samples.isEmpty,
            sampleRate > 0,
            durationSec > 0,
            bucketCount > 0
        else {
            return []
        }

        let fftSize = Self.spectralFFTSize
        let window = hannWindow(size: fftSize)
        let samplesPerBucket = max(1, samples.count / bucketCount)
        let binHz = sampleRate / Double(fftSize)
        let nyquistBin = fftSize / 2
        let lowMaxBin = clampedInt(Int(250 / binHz), min: 1, max: nyquistBin)
        let midMaxBin = clampedInt(Int(4_000 / binHz), min: lowMaxBin + 1, max: nyquistBin)
        let highMaxBin = clampedInt(Int(min(16_000, sampleRate / 2) / binHz), min: midMaxBin + 1, max: nyquistBin)

        var points: [SpectralBandPoint] = []
        points.reserveCapacity(bucketCount)

        for bucketIndex in 0..<bucketCount {
            let bucketStart = bucketIndex * samplesPerBucket
            let bucketEnd = min(samples.count, bucketStart + samplesPerBucket)
            let windowStart = ((bucketStart + bucketEnd) / 2) - (fftSize / 2)
            var real = Array(repeating: 0.0, count: fftSize)
            var imag = Array(repeating: 0.0, count: fftSize)

            for index in 0..<fftSize {
                let sampleIndex = windowStart + index
                let sample = sampleIndex >= 0 && sampleIndex < samples.count ? Double(samples[sampleIndex]) : 0
                real[index] = sample * window[index]
            }

            fftInPlace(real: &real, imag: &imag)

            var low = 0.0
            var lowCount = 0
            var mid = 0.0
            var midCount = 0
            var high = 0.0
            var highCount = 0

            if highMaxBin >= 1 {
                for bin in 1...highMaxBin {
                    let power = real[bin] * real[bin] + imag[bin] * imag[bin]
                    if bin <= lowMaxBin {
                        low += power
                        lowCount += 1
                    } else if bin <= midMaxBin {
                        mid += power
                        midCount += 1
                    } else {
                        high += power
                        highCount += 1
                    }
                }
            }

            points.append(SpectralBandPoint(
                timeSec: (Double(bucketStart) / Double(max(1, samples.count))) * durationSec,
                low: lowCount > 0 ? sqrt(low / Double(lowCount)) : 0,
                mid: midCount > 0 ? sqrt(mid / Double(midCount)) : 0,
                high: highCount > 0 ? sqrt(high / Double(highCount)) : 0
            ))
        }

        let maxEnergy = max(0.000_001, points.flatMap { [$0.low, $0.mid, $0.high] }.max() ?? 0)
        return points.map {
            SpectralBandPoint(
                timeSec: $0.timeSec,
                low: clamped($0.low / maxEnergy, min: 0, max: 1),
                mid: clamped($0.mid / maxEnergy, min: 0, max: 1),
                high: clamped($0.high / maxEnergy, min: 0, max: 1)
            )
        }
    }

    private func estimateMusicalKey(
        samples: [Float],
        sampleRate: Double,
        durationSec: Double
    ) -> MusicalKeyEstimate? {
        guard samples.count >= Self.spectralFFTSize, sampleRate > 0, durationSec >= 2 else {
            return nil
        }

        let fftSize = Self.spectralFFTSize
        let window = hannWindow(size: fftSize)
        let hop = max(fftSize / 2, Int(sampleRate * 0.5))
        let maxWindows = 64
        let binHz = sampleRate / Double(fftSize)
        let nyquistBin = fftSize / 2
        let minBin = max(1, Int((55 / binHz).rounded(.up)))
        let maxBin = min(nyquistBin, Int((5_000 / binHz).rounded(.down)))
        guard minBin < maxBin else {
            return nil
        }

        var chroma = Array(repeating: 0.0, count: 12)
        var totalEnergy = 0.0
        var windowStart = 0
        var windowCount = 0
        while windowStart < samples.count && windowCount < maxWindows {
            var real = Array(repeating: 0.0, count: fftSize)
            var imag = Array(repeating: 0.0, count: fftSize)
            for index in 0..<fftSize {
                let sampleIndex = windowStart + index
                let sample = sampleIndex < samples.count ? Double(samples[sampleIndex]) : 0
                real[index] = sample * window[index]
            }
            fftInPlace(real: &real, imag: &imag)

            for bin in minBin...maxBin {
                let frequency = Double(bin) * binHz
                guard frequency > 0 else {
                    continue
                }
                let midi = Int((69 + 12 * log2(frequency / 440)).rounded())
                let pitchClass = ((midi % 12) + 12) % 12
                let power = real[bin] * real[bin] + imag[bin] * imag[bin]
                let weight = sqrt(power) * pitchWeight(frequency)
                chroma[pitchClass] += weight
                totalEnergy += weight
            }

            windowCount += 1
            windowStart += hop
        }

        guard totalEnergy > 0.000_001 else {
            return nil
        }

        let normalized = chroma.map { $0 / totalEnergy }
        let candidates = keyCorrelationCandidates(chroma: normalized)
        guard let best = candidates.first else {
            return nil
        }
        let second = candidates.dropFirst().first?.score ?? 0
        let separation = best.score > 0 ? clamped((best.score - second) / best.score, min: 0, max: 1) : 0
        let concentration = normalized.max() ?? 0
        let confidence = clamped(0.15 + separation * 0.58 + concentration * 1.2, min: 0, max: 0.96)
        guard confidence >= 0.24 else {
            return nil
        }

        return MusicalKeyEstimate(
            tonic: Self.pitchClassNames[best.root],
            mode: best.mode,
            confidence: rounded(confidence),
            chromaEnergy: rounded(clamped(totalEnergy / Double(max(1, windowCount)), min: 0, max: 1_000_000), digits: 3)
        )
    }

    private func buildLoudnessAnalysis(buffer: PCMAnalysisBuffer, durationSec: Double) -> LoudnessAnalysis? {
        let channels = loudnessChannels(buffer: buffer)
        let measurement = channels.count > 1
            ? "ebu_r128_k_weighted_gated_multichannel"
            : "ebu_r128_k_weighted_gated_mono"
        guard !channels.isEmpty, durationSec > 0 else {
            return nil
        }

        let stats = multichannelStats(channels: channels)
        guard stats.peak > 0.000_01, stats.rms > 0.000_01 else {
            return LoudnessAnalysis(
                integratedRMSDb: -60,
                integratedLUFS: -70,
                peakDb: -60,
                truePeakDb: -60,
                headroomDb: 60,
                crestFactorDb: 0,
                dynamicRangeDb: 0,
                loudnessRangeLU: 0,
                measurement: measurement,
                confidence: 0
            )
        }

        let frameCount = min(256, max(8, Int(durationSec * 2)))
        let samplesPerFrame = max(1, stats.frameCount / frameCount)
        var frameRMSDb: [Double] = []
        frameRMSDb.reserveCapacity(frameCount)
        for frameIndex in 0..<frameCount {
            let start = frameIndex * samplesPerFrame
            let end = min(stats.frameCount, start + samplesPerFrame)
            guard start < end else {
                continue
            }
            let frameRMS = multichannelStats(channels: channels, start: start, end: end).rms
            if frameRMS > 0.000_01 {
                frameRMSDb.append(db(frameRMS))
            }
        }

        let integratedRMSDb = db(stats.rms)
        let peakDb = db(stats.peak)
        let ebuR128 = measureEBUR128(channels: channels, sampleRate: buffer.sampleRate)
        let truePeakDb = ebuR128.truePeakDb ?? peakDb
        let dynamicRangeDb = max(0, percentile(frameRMSDb, 0.95) - percentile(frameRMSDb, 0.10))
        let confidence = clamped(
            min(0.42, durationSec / 30) +
                min(0.28, Double(frameRMSDb.count) / 180) +
                min(0.24, stats.rms / 0.12) +
                min(0.04, Double(ebuR128.gatedBlockCount) / 120) +
                (channels.count > 1 ? 0.02 : 0),
            min: 0,
            max: 0.96
        )

        return LoudnessAnalysis(
            integratedRMSDb: rounded(integratedRMSDb, digits: 2),
            integratedLUFS: ebuR128.integratedLUFS.map { rounded($0, digits: 2) },
            peakDb: rounded(peakDb, digits: 2),
            truePeakDb: rounded(truePeakDb, digits: 2),
            headroomDb: rounded(max(0, -truePeakDb), digits: 2),
            crestFactorDb: rounded(max(0, peakDb - integratedRMSDb), digits: 2),
            dynamicRangeDb: rounded(dynamicRangeDb, digits: 2),
            loudnessRangeLU: ebuR128.loudnessRangeLU.map { rounded($0, digits: 2) },
            measurement: measurement,
            confidence: rounded(confidence)
        )
    }

    private func loudnessChannels(buffer: PCMAnalysisBuffer) -> [[Float]] {
        let channels = buffer.channelSamples.filter { !$0.isEmpty }
        if channels.isEmpty {
            return buffer.samples.isEmpty ? [] : [buffer.samples]
        }
        return channels
    }

    private func multichannelStats(channels: [[Float]]) -> (peak: Double, rms: Double, frameCount: Int) {
        let frameCount = channels.map(\.count).min() ?? 0
        return multichannelStats(channels: channels, start: 0, end: frameCount)
    }

    private func multichannelStats(
        channels: [[Float]],
        start: Int,
        end: Int
    ) -> (peak: Double, rms: Double, frameCount: Int) {
        let frameCount = channels.map(\.count).min() ?? 0
        let clampedStart = clampedInt(start, min: 0, max: frameCount)
        let clampedEnd = clampedInt(end, min: clampedStart, max: frameCount)
        guard !channels.isEmpty, clampedEnd > clampedStart else {
            return (0, 0, frameCount)
        }

        var peak = 0.0
        var sumSquares = 0.0
        var count = 0
        for channel in channels {
            for index in clampedStart..<clampedEnd {
                let value = Double(channel[index])
                peak = max(peak, abs(value))
                sumSquares += value * value
                count += 1
            }
        }
        return (
            peak,
            count > 0 ? sqrt(sumSquares / Double(count)) : 0,
            frameCount
        )
    }

    private func buildStereoAnalysis(buffer: PCMAnalysisBuffer) -> StereoAnalysis? {
        let channels = buffer.channelSamples.filter { !$0.isEmpty }
        if channels.count < 2 {
            let stats = sampleStats(samples: buffer.samples, start: 0, end: buffer.samples.count)
            return StereoAnalysis(
                channelCount: max(1, channels.count),
                leftPeakDb: db(stats.peak),
                rightPeakDb: nil,
                leftRMSDb: db(stats.rms),
                rightRMSDb: nil,
                stereoWidth: 0,
                phaseCorrelation: 1,
                midSideBalance: 1,
                confidence: buffer.samples.isEmpty ? 0 : 0.62
            )
        }

        let left = channels[0]
        let right = channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else {
            return nil
        }

        let leftStats = sampleStats(samples: left, start: 0, end: count)
        let rightStats = sampleStats(samples: right, start: 0, end: count)
        var sumLeftSquares = 0.0
        var sumRightSquares = 0.0
        var sumCross = 0.0
        var sumMidSquares = 0.0
        var sumSideSquares = 0.0

        for index in 0..<count {
            let leftValue = Double(left[index])
            let rightValue = Double(right[index])
            let mid = (leftValue + rightValue) * 0.5
            let side = (leftValue - rightValue) * 0.5
            sumLeftSquares += leftValue * leftValue
            sumRightSquares += rightValue * rightValue
            sumCross += leftValue * rightValue
            sumMidSquares += mid * mid
            sumSideSquares += side * side
        }

        let denominator = sqrt(max(0, sumLeftSquares * sumRightSquares))
        let phaseCorrelation = denominator > 0 ? clamped(sumCross / denominator, min: -1, max: 1) : 1
        let midRMS = sqrt(sumMidSquares / Double(count))
        let sideRMS = sqrt(sumSideSquares / Double(count))
        let stereoWidth = clamped(sideRMS / max(0.000_001, midRMS + sideRMS), min: 0, max: 1)
        let midSideBalance = clamped(midRMS / max(0.000_001, sideRMS), min: 0, max: 12)
        let activeChannels = [leftStats.rms, rightStats.rms].filter { $0 > 0.000_01 }.count
        let confidence = clamped(
            0.4 +
                min(0.22, Double(count) / max(1, buffer.sampleRate * 20)) +
                (activeChannels == 2 ? 0.28 : 0) +
                min(0.1, Double(channels.count) / 20),
            min: 0,
            max: 0.96
        )

        return StereoAnalysis(
            channelCount: channels.count,
            leftPeakDb: rounded(db(leftStats.peak), digits: 2),
            rightPeakDb: rounded(db(rightStats.peak), digits: 2),
            leftRMSDb: rounded(db(leftStats.rms), digits: 2),
            rightRMSDb: rounded(db(rightStats.rms), digits: 2),
            stereoWidth: rounded(stereoWidth),
            phaseCorrelation: rounded(phaseCorrelation),
            midSideBalance: rounded(midSideBalance),
            confidence: rounded(confidence)
        )
    }

    private func measureEBUR128(
        channels: [[Float]],
        sampleRate: Double
    ) -> (integratedLUFS: Double?, loudnessRangeLU: Double?, truePeakDb: Double?, gatedBlockCount: Int) {
        let activeChannels = channels.filter { $0.count >= 2 }
        let frameCount = activeChannels.map(\.count).min() ?? 0
        guard !activeChannels.isEmpty, frameCount >= 2, sampleRate > 0 else {
            return (nil, nil, nil, 0)
        }

        let absoluteGateMeanSquare = pow(10, (-70 + 0.691) / 10)
        let blockSize = max(1, Int((0.400 * sampleRate).rounded()))
        let blockMeanSquares = ebuR128MultichannelBlockMeanSquares(
            channels: activeChannels,
            sampleRate: sampleRate,
            blockSize: blockSize,
            hopSize: max(1, Int((0.100 * sampleRate).rounded()))
        )
        let truePeakDb = estimateTruePeakDb(channels: activeChannels)
        guard frameCount >= blockSize else {
            let meanSquare = blockMeanSquares.first ?? 0
            let lufs = meanSquare > 0 ? -0.691 + 10 * log10(meanSquare) : -70
            return (max(-70, lufs), 0, truePeakDb, meanSquare >= absoluteGateMeanSquare ? 1 : 0)
        }

        let absoluteGatedBlocks = blockMeanSquares.filter { $0 >= absoluteGateMeanSquare }
        guard !absoluteGatedBlocks.isEmpty else {
            return (-70, 0, truePeakDb, 0)
        }

        let absoluteGatedMean = absoluteGatedBlocks.reduce(0, +) / Double(absoluteGatedBlocks.count)
        let relativeGateLUFS = (-0.691 + 10 * log10(absoluteGatedMean)) - 10
        let relativeGateMeanSquare = pow(10, (relativeGateLUFS + 0.691) / 10)
        let gatedBlocks = absoluteGatedBlocks.filter { $0 >= relativeGateMeanSquare }
        let finalBlocks = gatedBlocks.isEmpty ? absoluteGatedBlocks : gatedBlocks
        let integratedMeanSquare = finalBlocks.reduce(0, +) / Double(finalBlocks.count)
        let integratedLUFS = -0.691 + 10 * log10(integratedMeanSquare)
        let blockLoudness = finalBlocks.map { -0.691 + 10 * log10($0) }
        let loudnessRange = blockLoudness.count >= 2
            ? max(0, percentile(blockLoudness, 0.95) - percentile(blockLoudness, 0.10))
            : 0

        return (
            max(-70, integratedLUFS),
            loudnessRange,
            truePeakDb,
            finalBlocks.count
        )
    }

    private func ebuR128MultichannelBlockMeanSquares(
        channels: [[Float]],
        sampleRate: Double,
        blockSize: Int,
        hopSize: Int
    ) -> [Double] {
        let channelBlocks = channels.enumerated().map { index, samples in
            (
                weight: ebuR128ChannelWeight(channelIndex: index, channelCount: channels.count),
                blocks: ebuR128BlockMeanSquares(
                    samples: samples,
                    sampleRate: sampleRate,
                    blockSize: blockSize,
                    hopSize: hopSize
                )
            )
        }
        let blockCount = channelBlocks.map { $0.blocks.count }.min() ?? 0
        guard blockCount > 0 else {
            return []
        }
        return (0..<blockCount).map { blockIndex in
            channelBlocks.reduce(0.0) { sum, channel in
                sum + channel.blocks[blockIndex] * channel.weight
            }
        }
    }

    private func ebuR128ChannelWeight(channelIndex: Int, channelCount: Int) -> Double {
        if channelCount >= 6, channelIndex == 5 {
            return 0
        }
        if channelCount >= 5, channelIndex == 3 || channelIndex == 4 {
            return pow(10, 1.5 / 10)
        }
        return 1
    }

    private func ebuR128BlockMeanSquares(
        samples: [Float],
        sampleRate: Double,
        blockSize: Int,
        hopSize: Int
    ) -> [Double] {
        guard !samples.isEmpty, blockSize > 0, hopSize > 0 else {
            return []
        }

        var highShelf = BiquadProcessor(coefficients: highShelfCoefficients(
            sampleRate: sampleRate,
            frequency: 1_681.974,
            gainDb: 4,
            q: 0.707
        ))
        var highPass = BiquadProcessor(coefficients: highPassCoefficients(
            sampleRate: sampleRate,
            frequency: 38.135,
            q: 0.5
        ))
        var ring = Array(repeating: 0.0, count: blockSize)
        var ringIndex = 0
        var ringCount = 0
        var sumSquares = 0.0
        var blockMeanSquares: [Double] = []
        blockMeanSquares.reserveCapacity(max(1, samples.count / hopSize))

        for index in samples.indices {
            let weighted = highPass.process(highShelf.process(Double(samples[index])))
            let square = weighted * weighted
            if ringCount < blockSize {
                ringCount += 1
            } else {
                sumSquares -= ring[ringIndex]
            }
            ring[ringIndex] = square
            sumSquares += square
            ringIndex = (ringIndex + 1) % blockSize

            if ringCount == blockSize, (index - blockSize + 1).isMultiple(of: hopSize) {
                blockMeanSquares.append(sumSquares / Double(blockSize))
            }
        }

        if blockMeanSquares.isEmpty, ringCount > 0 {
            blockMeanSquares.append(sumSquares / Double(ringCount))
        }
        return blockMeanSquares
    }

    private func kWeightedSamples(samples: [Float], sampleRate: Double) -> [Double] {
        let prefiltered = applyBiquad(
            samples: samples.map(Double.init),
            coefficients: highShelfCoefficients(sampleRate: sampleRate, frequency: 1_681.974, gainDb: 4, q: 0.707)
        )
        return applyBiquad(
            samples: prefiltered,
            coefficients: highPassCoefficients(sampleRate: sampleRate, frequency: 38.135, q: 0.5)
        )
    }

    private func estimateTruePeakDb(channels: [[Float]]) -> Double? {
        let peaks = channels.compactMap { estimateOversampledTruePeak($0) }
        guard let peak = peaks.max() else {
            return nil
        }
        return db(peak)
    }

    private func estimateOversampledTruePeak(_ samples: [Float]) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }
        let samplePeak = samples.reduce(0.0) { max($0, abs(Double($1))) }
        guard samplePeak > 0 else {
            return 0
        }

        var peak = samplePeak
        let threshold = samplePeak * 0.82
        let candidateCount = samples.dropLast().reduce(0) { count, sample in
            abs(Double(sample)) >= threshold ? count + 1 : count
        }
        let maxInterpolatedPairs = 500_000
        let candidateStride = max(1, candidateCount / maxInterpolatedPairs)
        var visitedCandidates = 0

        for index in samples.indices.dropLast() {
            guard abs(Double(samples[index])) >= threshold || abs(Double(samples[index + 1])) >= threshold else {
                continue
            }
            visitedCandidates += 1
            guard visitedCandidates.isMultiple(of: candidateStride) else {
                continue
            }

            let previous = index > samples.startIndex ? Double(samples[index - 1]) : Double(samples[index])
            let current = Double(samples[index])
            let next = Double(samples[index + 1])
            let following = index + 2 < samples.endIndex ? Double(samples[index + 2]) : next
            for phase in 1..<4 {
                let t = Double(phase) / 4
                peak = max(peak, abs(cubicInterpolatedValue(
                    previous: previous,
                    current: current,
                    next: next,
                    following: following,
                    t: t
                )))
            }
        }

        if visitedCandidates == 0, samples.count >= 2 {
            for index in stride(from: 0, to: samples.count - 1, by: max(1, samples.count / 256)) {
                let previous = index > samples.startIndex ? Double(samples[index - 1]) : Double(samples[index])
                let current = Double(samples[index])
                let next = Double(samples[index + 1])
                let following = index + 2 < samples.endIndex ? Double(samples[index + 2]) : next
                for phase in 1..<4 {
                    let t = Double(phase) / 4
                    peak = max(peak, abs(cubicInterpolatedValue(
                        previous: previous,
                        current: current,
                        next: next,
                        following: following,
                        t: t
                    )))
                }
            }
        }
        return peak
    }

    private func cubicInterpolatedValue(
        previous: Double,
        current: Double,
        next: Double,
        following: Double,
        t: Double
    ) -> Double {
        let a = -0.5 * previous + 1.5 * current - 1.5 * next + 0.5 * following
        let b = previous - 2.5 * current + 2 * next - 0.5 * following
        let c = -0.5 * previous + 0.5 * next
        return ((a * t + b) * t + c) * t + current
    }

    private func applyBiquad(
        samples: [Double],
        coefficients: (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double)
    ) -> [Double] {
        var output: [Double] = []
        output.reserveCapacity(samples.count)
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for sample in samples {
            let y = coefficients.b0 * sample +
                coefficients.b1 * x1 +
                coefficients.b2 * x2 -
                coefficients.a1 * y1 -
                coefficients.a2 * y2
            output.append(y)
            x2 = x1
            x1 = sample
            y2 = y1
            y1 = y
        }
        return output
    }

    private func highPassCoefficients(
        sampleRate: Double,
        frequency: Double,
        q: Double
    ) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        let resolvedFrequency = clamped(frequency, min: 1, max: max(1, sampleRate * 0.45))
        let omega = 2 * Double.pi * resolvedFrequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosOmega = cos(omega)
        let a0 = 1 + alpha
        return (
            b0: ((1 + cosOmega) / 2) / a0,
            b1: (-(1 + cosOmega)) / a0,
            b2: ((1 + cosOmega) / 2) / a0,
            a1: (-2 * cosOmega) / a0,
            a2: (1 - alpha) / a0
        )
    }

    private struct BiquadProcessor {
        var coefficients: (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double)
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0

        mutating func process(_ sample: Double) -> Double {
            let y = coefficients.b0 * sample +
                coefficients.b1 * x1 +
                coefficients.b2 * x2 -
                coefficients.a1 * y1 -
                coefficients.a2 * y2
            x2 = x1
            x1 = sample
            y2 = y1
            y1 = y
            return y
        }
    }

    private func highShelfCoefficients(
        sampleRate: Double,
        frequency: Double,
        gainDb: Double,
        q: Double
    ) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        let amplitude = pow(10, gainDb / 40)
        let resolvedFrequency = clamped(frequency, min: 1, max: max(1, sampleRate * 0.45))
        let omega = 2 * Double.pi * resolvedFrequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * q)
        let beta = 2 * sqrt(amplitude) * alpha
        let a0 = (amplitude + 1) - (amplitude - 1) * cosOmega + beta
        return (
            b0: amplitude * ((amplitude + 1) + (amplitude - 1) * cosOmega + beta) / a0,
            b1: -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosOmega) / a0,
            b2: amplitude * ((amplitude + 1) + (amplitude - 1) * cosOmega - beta) / a0,
            a1: 2 * ((amplitude - 1) - (amplitude + 1) * cosOmega) / a0,
            a2: ((amplitude + 1) - (amplitude - 1) * cosOmega - beta) / a0
        )
    }

    private func buildOnsetEnvelope(
        waveformDetail: [WaveformDetailPoint],
        spectralBands: [SpectralBandPoint],
        durationSec: Double
    ) -> [(timeSec: Double, strength: Double)] {
        guard waveformDetail.count >= 4, durationSec > 0 else {
            return []
        }

        let evidence = waveformDetail.enumerated().map { index, point in
            let previousPoint = waveformDetail[max(0, index - 1)]
            let band = resolveBandAt(spectralBands: spectralBands, waveformLength: waveformDetail.count, index: index)
            let previousBand = resolveBandAt(
                spectralBands: spectralBands,
                waveformLength: waveformDetail.count,
                index: max(0, index - 1)
            ) ?? band
            let spectralFlux: Double
            if let band, let previousBand {
                let highRise = max(0.0, band.high - previousBand.high)
                let midRise = max(0.0, band.mid - previousBand.mid)
                let lowRise = max(0.0, band.low - previousBand.low)
                let spectralMovement = abs(band.high - previousBand.high) * 0.34 +
                    abs(band.mid - previousBand.mid) * 0.22 +
                    abs(band.low - previousBand.low) * 0.18
                spectralFlux = highRise * 0.32 + midRise * 0.2 + lowRise * 0.08 + spectralMovement
            } else {
                spectralFlux = 0.0
            }

            return (
                timeSec: point.timeSec,
                rmsRise: max(0, point.rms - previousPoint.rms),
                peakRise: max(0, point.peak - previousPoint.peak),
                spectralFlux: spectralFlux
            )
        }

        let rmsScores = normalizeScores(evidence.map { $0.rmsRise })
        let peakScores = normalizeScores(evidence.map { $0.peakRise })
        let spectralScores = normalizeScores(evidence.map { $0.spectralFlux })
        let rawEnvelope = evidence.indices.map { index in
            let rmsScore = rmsScores[index] * 0.34
            let peakScore = peakScores[index] * 0.1
            let spectralScore = spectralScores[index] * 0.56
            return clamped(rmsScore + peakScore + spectralScore, min: 0, max: 1)
        }
        let smoothed = smoothScores(rawEnvelope, radius: 1)

        return evidence.indices.map { index in
            (
                timeSec: evidence[index].timeSec,
                strength: clamped(max(rawEnvelope[index], smoothed[index] * 0.92), min: 0, max: 1)
            )
        }
    }

    private func buildTransientMarkers(
        onsetEnvelope: [(timeSec: Double, strength: Double)],
        durationSec: Double
    ) -> [TransientMarker] {
        guard onsetEnvelope.count >= 4, durationSec > 0 else {
            return []
        }

        let strengths = onsetEnvelope.map(\.strength)
        let localAverage = smoothScores(strengths, radius: 3)
        var markers: [TransientMarker] = []
        var lastTimeSec = -Double.infinity

        for index in onsetEnvelope.indices {
            let point = onsetEnvelope[index]
            let previousStrength = strengths[max(0, index - 1)]
            let nextStrength = strengths[min(strengths.count - 1, index + 1)]
            let isLocalPeak = point.strength >= previousStrength && point.strength >= nextStrength
            let adaptiveThreshold = max(0.38, localAverage[index] + 0.08)
            guard isLocalPeak, point.strength >= adaptiveThreshold, point.timeSec - lastTimeSec >= 0.18 else {
                continue
            }

            markers.append(TransientMarker(
                index: markers.count,
                timeSec: point.timeSec,
                strength: point.strength
            ))
            lastTimeSec = point.timeSec
            if markers.count >= 256 {
                break
            }
        }

        return markers
    }

    private func estimateBPM(transientMarkers: [TransientMarker]) -> (bpm: Double?, confidence: Double) {
        let markers = transientMarkers
            .filter { $0.strength >= 0.35 }
            .prefix(160)
        guard markers.count >= 4 else {
            return (nil, 0)
        }

        var bins: [Int: Double] = [:]
        for leftIndex in markers.indices {
            let left = markers[leftIndex]
            for rightIndex in markers.index(after: leftIndex)..<markers.endIndex {
                let right = markers[rightIndex]
                let interval = right.timeSec - left.timeSec
                if interval < 0.3 {
                    continue
                }
                if interval > 2.2 {
                    break
                }

                var bpm = 60 / interval
                while bpm < 90 {
                    bpm *= 2
                }
                while bpm > 180 {
                    bpm /= 2
                }
                guard bpm >= Self.minValidBPM, bpm <= Self.maxValidBPM else {
                    continue
                }

                let bin = Int((bpm * 2).rounded())
                bins[bin, default: 0] += Double(left.strength * right.strength)
            }
        }

        guard let best = bins.max(by: { $0.value < $1.value }) else {
            return (nil, 0)
        }

        let total = max(0.000_001, bins.values.reduce(0, +))
        let bpm = Double(best.key) / 2
        let confidence = clamped((best.value / total) * 2.2, min: 0, max: 0.92)
        return (bpm, confidence)
    }

    private func resolveAnalysisBPM(
        track: Track,
        estimate: (bpm: Double?, confidence: Double)
    ) -> (bpm: Double?, confidence: Double, source: TrackAnalysisSource, metadataMismatch: Bool) {
        let metadataBPM = normalizeBPM(track.bpm)
        let derivedBPM = normalizeBPM(estimate.bpm)
        let metadataMismatch = if let metadataBPM, let derivedBPM {
            abs(metadataBPM - derivedBPM) > Self.bpmMismatchDelta
        } else {
            false
        }

        if let derivedBPM,
           (metadataBPM == nil || (estimate.confidence >= Self.derivedBPMConfidencePriority && metadataMismatch)) {
            return (derivedBPM, estimate.confidence, .derived, metadataMismatch)
        }

        if let metadataBPM {
            return (metadataBPM, max(0.62, min(0.76, estimate.confidence == 0 ? 0.72 : estimate.confidence)), .metadata, metadataMismatch)
        }

        return (derivedBPM, estimate.confidence, .derived, metadataMismatch)
    }

    private func normalizeBPM(_ candidate: Double?) -> Double? {
        guard let candidate,
              candidate.isFinite,
              candidate >= Self.minValidBPM,
              candidate <= Self.maxValidBPM else {
            return nil
        }
        return candidate
    }

    private func buildBeatGrid(durationSec: Double, beatIntervalSec: Double, beatOffsetSec: Double) -> [Double] {
        guard durationSec > 0, beatIntervalSec > 0 else {
            return []
        }

        var start = beatOffsetSec
        while start > 0 {
            start -= beatIntervalSec
        }
        while start < 0 {
            start += beatIntervalSec
        }

        var grid: [Double] = []
        var timeSec = start
        while timeSec <= durationSec + 0.001, grid.count < 2_200 {
            grid.append((timeSec * 10_000).rounded() / 10_000)
            timeSec += beatIntervalSec
        }
        return grid
    }

    private func resolveBeatPhaseOffset(
        beatIntervalSec: Double,
        transientMarkers: [TransientMarker]
    ) -> (offsetSec: Double, confidence: Double) {
        guard beatIntervalSec > 0 else {
            return (0, 0)
        }

        var candidates = Set<Double>([0])
        for marker in transientMarkers.filter({ $0.strength >= 0.45 }).prefix(80) {
            candidates.insert(marker.timeSec.truncatingRemainder(dividingBy: beatIntervalSec))
        }

        var bestOffset = 0.0
        var bestScore = scoreBeatPhase(phaseOffsetSec: 0, beatIntervalSec: beatIntervalSec, transientMarkers: transientMarkers)
        for candidate in candidates {
            let score = scoreBeatPhase(
                phaseOffsetSec: candidate,
                beatIntervalSec: beatIntervalSec,
                transientMarkers: transientMarkers
            )
            if score > bestScore {
                bestScore = score
                bestOffset = candidate
            }
        }
        return (bestOffset, clamped(bestScore, min: 0, max: 1))
    }

    private func scoreBeatPhase(
        phaseOffsetSec: Double,
        beatIntervalSec: Double,
        transientMarkers: [TransientMarker]
    ) -> Double {
        guard !transientMarkers.isEmpty else {
            return 0
        }

        let windowSec = min(0.14, beatIntervalSec * 0.3)
        var score = 0.0
        var weight = 0.0
        for marker in transientMarkers.prefix(160) {
            let beatIndex = ((marker.timeSec - phaseOffsetSec) / beatIntervalSec).rounded()
            let nearest = phaseOffsetSec + beatIndex * beatIntervalSec
            let distance = abs(nearest - marker.timeSec)
            weight += marker.strength
            if distance <= windowSec {
                score += marker.strength * (1 - distance / windowSec)
            }
        }
        return weight > 0 ? score / weight : 0
    }

    private func buildDownbeatGrid(
        beatGridSec: [Double],
        transientMarkers: [TransientMarker],
        energyProfile: [Double],
        spectralBands: [SpectralBandPoint],
        durationSec: Double
    ) -> (downbeatsSec: [Double], barGrid: [BarMarker], confidence: Double) {
        guard !beatGridSec.isEmpty else {
            return ([], [], 0)
        }

        let phaseScores = (0..<4).map { phase in
            (
                phase: phase,
                score: scoreDownbeatPhase(
                    beatGridSec: beatGridSec,
                    phase: phase,
                    transientMarkers: transientMarkers,
                    energyProfile: energyProfile,
                    spectralBands: spectralBands,
                    durationSec: durationSec
                )
            )
        }
        let ranked = phaseScores.sorted { $0.score > $1.score }
        let best = ranked.first ?? (phase: 0, score: 0)
        let second = ranked.dropFirst().first ?? (phase: 0, score: 0)
        let separation = best.score > 0 ? clamped((best.score - second.score) / best.score, min: 0, max: 1) : 0
        let confidence = clamped(best.score * 0.45 + separation * 0.55, min: 0, max: 1)
        let downbeats = beatGridSec.enumerated()
            .filter { $0.offset % 4 == best.phase }
            .map(\.element)
        let bars = downbeats.enumerated().map { index, startSec in
            BarMarker(index: index, startSec: startSec, beatIndex: best.phase + index * 4)
        }
        return (downbeats, bars, confidence)
    }

    private func scoreDownbeatPhase(
        beatGridSec: [Double],
        phase: Int,
        transientMarkers: [TransientMarker],
        energyProfile: [Double],
        spectralBands: [SpectralBandPoint],
        durationSec: Double
    ) -> Double {
        let bars = beatGridSec.enumerated()
            .filter { $0.offset % 4 == phase }
            .map(\.element)
        guard !bars.isEmpty else {
            return 0
        }

        let windowSec = 0.16
        var score = 0.0
        for barStartSec in bars.prefix(96) {
            let transientScore = transientMarkers.reduce(0.0) { sum, marker in
                let distance = abs(marker.timeSec - barStartSec)
                return distance <= windowSec
                    ? sum + marker.strength * (1 - distance / windowSec)
                    : sum
            }
            let energyScore = energyAt(energyProfile: energyProfile, durationSec: durationSec, timeSec: barStartSec)
            let kickScore = lowBandDownbeatScore(
                spectralBands: spectralBands,
                durationSec: durationSec,
                timeSec: barStartSec
            )
            score += transientScore * 0.72 + kickScore * 0.92 + energyScore * 0.06
        }
        return score / Double(max(1, bars.count))
    }

    private func lowBandDownbeatScore(
        spectralBands: [SpectralBandPoint],
        durationSec: Double,
        timeSec: Double
    ) -> Double {
        guard let band = spectralBandAt(spectralBands: spectralBands, durationSec: durationSec, timeSec: timeSec) else {
            return 0
        }
        let total = max(0.000_001, band.low + band.mid + band.high)
        let lowRatio = band.low / total
        let lowDominance = band.low - max(band.mid * 0.4, band.high * 0.26)
        return clamped(lowRatio * 0.72 + lowDominance * 0.48, min: 0, max: 1)
    }

    private func buildPhraseMarkers(
        barGrid: [BarMarker],
        energyProfile: [Double],
        durationSec: Double,
        beatGridQuality: Double,
        downbeatConfidence: Double
    ) -> [PhraseMarker] {
        barGrid
            .filter { $0.index % 8 == 0 && $0.startSec < durationSec - 0.001 }
            .map { bar in
                let localEnergy = energyAt(
                    energyProfile: energyProfile,
                    durationSec: durationSec,
                    timeSec: bar.startSec
                )
                let sectionChange = energySectionChangeScore(
                    energyProfile: energyProfile,
                    durationSec: durationSec,
                    timeSec: bar.startSec
                )
                let introBoost = bar.index == 0 ? 0.04 : 0
                return PhraseMarker(
                    index: bar.index / 8,
                    startSec: bar.startSec,
                    bars: 8,
                    confidence: clamped(
                        0.22 +
                            beatGridQuality * 0.38 +
                            downbeatConfidence * 0.12 +
                            localEnergy * 0.08 +
                            sectionChange * 0.22 +
                            introBoost,
                        min: 0,
                        max: 0.92
                    )
                )
            }
    }

    private func energySectionChangeScore(
        energyProfile: [Double],
        durationSec: Double,
        timeSec: Double
    ) -> Double {
        guard energyProfile.count >= 6, durationSec > 0, timeSec > 0, timeSec < durationSec else {
            return 0
        }

        let windowSec = min(16, max(4, durationSec * 0.08))
        let before = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: max(0, timeSec - windowSec),
            endSec: timeSec
        )
        let after = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: timeSec,
            endSec: min(durationSec, timeSec + windowSec)
        )
        guard let before, let after else {
            return 0
        }
        return clamped(abs(after - before) / 0.45, min: 0, max: 1)
    }

    private func averageEnergy(
        energyProfile: [Double],
        durationSec: Double,
        startSec: Double,
        endSec: Double
    ) -> Double? {
        guard !energyProfile.isEmpty, durationSec > 0, endSec > startSec else {
            return nil
        }
        let startIndex = clampedInt(
            Int(floor((startSec / durationSec) * Double(energyProfile.count))),
            min: 0,
            max: energyProfile.count - 1
        )
        let endIndex = clampedInt(
            Int(ceil((endSec / durationSec) * Double(energyProfile.count))) - 1,
            min: startIndex,
            max: energyProfile.count - 1
        )
        let values = energyProfile[startIndex...endIndex]
        return values.reduce(0, +) / Double(values.count)
    }

    private func scoreTransientMarkerQuality(
        transientMarkers: [TransientMarker],
        beatGridSec: [Double],
        durationSec: Double,
        beatPhaseConfidence: Double,
        downbeatConfidence: Double
    ) -> Double {
        guard !transientMarkers.isEmpty, durationSec > 0 else {
            return 0
        }

        let averageStrength = transientMarkers.reduce(0.0) { $0 + clamped($1.strength, min: 0, max: 1) } / Double(transientMarkers.count)
        let markerDensity = Double(transientMarkers.count) / max(1, durationSec)
        let expectedBeatDensity = beatGridSec.isEmpty ? 2 : Double(beatGridSec.count) / max(1, durationSec)
        let densityRatio = markerDensity / max(0.25, expectedBeatDensity)
        let densityScore = clamped(densityRatio <= 1 ? densityRatio : 1 - (densityRatio - 1) / 3, min: 0, max: 1)

        return clamped(
            densityScore * 0.24 +
                averageStrength * 0.22 +
                beatPhaseConfidence * 0.28 +
                downbeatConfidence * 0.26,
            min: 0,
            max: 1
        )
    }

    private func resolveOutroCueSec(barGrid: [BarMarker], durationSec: Double) -> Double? {
        guard durationSec > 0 else {
            return nil
        }
        let fallback = max(0, durationSec - min(16, durationSec * 0.12))
        return barGrid.last(where: { $0.startSec <= fallback })?.startSec ?? fallback
    }

    private func findEnergyTime(
        energyProfile: [Double],
        durationSec: Double,
        findMax: Bool,
        startRatio: Double,
        endRatio: Double
    ) -> Double? {
        guard !energyProfile.isEmpty, durationSec > 0 else {
            return nil
        }

        let start = max(0, Int(Double(energyProfile.count) * startRatio))
        let end = min(energyProfile.count - 1, max(start, Int(ceil(Double(energyProfile.count) * endRatio))))
        var bestIndex = start
        var bestValue = energyProfile[start]
        if start <= end {
            for index in start...end {
                let value = energyProfile[index]
                if findMax ? value > bestValue : value < bestValue {
                    bestIndex = index
                    bestValue = value
                }
            }
        }
        return (Double(bestIndex) / Double(max(1, energyProfile.count - 1))) * durationSec
    }

    private func snapToNearestBar(barGrid: [BarMarker], timeSec: Double) -> Double? {
        guard let first = barGrid.first else {
            return nil
        }
        var best = first
        var bestDistance = abs(first.startSec - timeSec)
        for bar in barGrid {
            let distance = abs(bar.startSec - timeSec)
            if distance < bestDistance {
                best = bar
                bestDistance = distance
            }
        }
        return best.startSec
    }

    private func buildCueCandidates(
        durationSec: Double,
        introCueSec: Double,
        firstDownbeatSec: Double?,
        outroCueSec: Double?,
        lowEnergyBreakSec: Double?,
        highEnergyDropSec: Double?,
        barGrid: [BarMarker],
        energyProfile: [Double],
        spectralBands: [SpectralBandPoint],
        transientMarkers: [TransientMarker],
        beatGridQuality: Double,
        downbeatConfidence: Double,
        transientQuality: Double
    ) -> [CueCandidate] {
        let introEvidence = scoreIntroEvidence(
            introCueSec: introCueSec,
            firstDownbeatSec: firstDownbeatSec,
            durationSec: durationSec,
            energyProfile: energyProfile,
            beatGridQuality: beatGridQuality,
            downbeatConfidence: downbeatConfidence
        )
        var cues = [
            CueCandidate(
                id: "intro",
                type: .intro,
                startSec: introCueSec,
                endSec: min(durationSec, introCueSec + 8),
                confidence: clamped(0.36 + introEvidence.score * 0.32, min: 0, max: 0.8),
                label: "Intro",
                origin: introEvidence.derived ? .derived : .heuristicPlaceholder
            )
        ]
        if let firstDownbeatSec {
            let evidence = scoreFirstDownbeatEvidence(
                timeSec: firstDownbeatSec,
                barGrid: barGrid,
                durationSec: durationSec,
                spectralBands: spectralBands,
                transientMarkers: transientMarkers,
                beatGridQuality: beatGridQuality,
                downbeatConfidence: downbeatConfidence,
                transientQuality: transientQuality
            )
            cues.append(CueCandidate(
                id: "first-downbeat",
                type: .firstDownbeat,
                startSec: firstDownbeatSec,
                endSec: min(durationSec, firstDownbeatSec + 4),
                confidence: clamped(0.3 + evidence.score * 0.58, min: 0, max: 0.88),
                label: "First downbeat",
                origin: evidence.derived ? .derived : .heuristicPlaceholder
            ))
        }
        if let outroCueSec {
            let evidence = scoreOutroEvidence(
                timeSec: outroCueSec,
                durationSec: durationSec,
                barGrid: barGrid,
                energyProfile: energyProfile,
                transientMarkers: transientMarkers,
                beatGridQuality: beatGridQuality,
                downbeatConfidence: downbeatConfidence
            )
            cues.append(CueCandidate(
                id: "outro",
                type: .outro,
                startSec: outroCueSec,
                endSec: durationSec,
                confidence: clamped(0.34 + evidence.score * 0.46, min: 0, max: 0.82),
                label: "Outro mix-out",
                origin: evidence.derived ? .derived : .heuristicPlaceholder
            ))
        }
        if let lowEnergyBreakSec {
            let evidence = scoreEnergyValleyEvidence(
                timeSec: lowEnergyBreakSec,
                durationSec: durationSec,
                energyProfile: energyProfile,
                barGrid: barGrid,
                beatGridQuality: beatGridQuality
            )
            cues.append(CueCandidate(
                id: "low-energy-break",
                type: .lowEnergyBreak,
                startSec: lowEnergyBreakSec,
                endSec: min(durationSec, lowEnergyBreakSec + 8),
                confidence: clamped(0.34 + evidence.score * 0.42, min: 0, max: 0.78),
                label: "Low-energy break",
                origin: evidence.derived ? .derived : .heuristicPlaceholder
            ))
        }
        if let highEnergyDropSec {
            let evidence = scoreEnergyDropEvidence(
                timeSec: highEnergyDropSec,
                durationSec: durationSec,
                energyProfile: energyProfile,
                spectralBands: spectralBands,
                transientMarkers: transientMarkers,
                barGrid: barGrid,
                beatGridQuality: beatGridQuality
            )
            cues.append(CueCandidate(
                id: "high-energy-drop",
                type: .highEnergyDrop,
                startSec: highEnergyDropSec,
                endSec: min(durationSec, highEnergyDropSec + 8),
                confidence: clamped(0.32 + evidence.score * 0.46, min: 0, max: 0.78),
                label: "High-energy drop",
                origin: evidence.derived ? .derived : .heuristicPlaceholder
            ))
        }
        return cues
    }

    private func scoreIntroEvidence(
        introCueSec: Double,
        firstDownbeatSec: Double?,
        durationSec: Double,
        energyProfile: [Double],
        beatGridQuality: Double,
        downbeatConfidence: Double
    ) -> (score: Double, derived: Bool) {
        guard let firstDownbeatSec, durationSec > 0, firstDownbeatSec >= 1.5 else {
            return (0, false)
        }
        let leadInEnergy = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: introCueSec,
            endSec: min(firstDownbeatSec, introCueSec + 12)
        )
        let postEnergy = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: firstDownbeatSec,
            endSec: min(durationSec, firstDownbeatSec + 12)
        )
        guard let leadInEnergy, let postEnergy else {
            return (0, false)
        }
        let leadInDrop = clamped((postEnergy - leadInEnergy) / 0.22, min: 0, max: 1)
        let downbeatScore = clamped(beatGridQuality * 0.5 + downbeatConfidence * 0.5, min: 0, max: 1)
        let score = clamped(leadInDrop * 0.62 + downbeatScore * 0.38, min: 0, max: 1)
        return (score, leadInDrop >= 0.45 && downbeatScore >= 0.45 && score >= 0.54)
    }

    private func scoreFirstDownbeatEvidence(
        timeSec: Double,
        barGrid: [BarMarker],
        durationSec: Double,
        spectralBands: [SpectralBandPoint],
        transientMarkers: [TransientMarker],
        beatGridQuality: Double,
        downbeatConfidence: Double,
        transientQuality: Double
    ) -> (score: Double, derived: Bool) {
        let transientScore = nearbyTransientScore(
            transientMarkers: transientMarkers,
            timeSec: timeSec,
            windowSec: 0.18
        )
        let kickScore = lowBandDownbeatScore(
            spectralBands: spectralBands,
            durationSec: durationSec,
            timeSec: timeSec
        )
        let phraseSupport = barGrid.first(where: { abs($0.startSec - timeSec) <= 0.25 }).map {
            $0.index == 0 ? 1.0 : ($0.index % 8 == 0 ? 0.82 : 0.42)
        } ?? 0
        let earlySupport = clamped(1 - timeSec / max(1, min(48, durationSec * 0.35)), min: 0, max: 1)
        let score = clamped(
            beatGridQuality * 0.24 +
                downbeatConfidence * 0.22 +
                transientScore * 0.24 +
                kickScore * 0.16 +
                phraseSupport * 0.08 +
                earlySupport * 0.06,
            min: 0,
            max: 1
        )
        let hasLocalAttack = transientScore >= 0.24 || kickScore >= 0.24
        let hasGridSupport = beatGridQuality >= 0.38 && downbeatConfidence >= 0.22 && transientQuality >= 0.18
        return (score, hasGridSupport && hasLocalAttack && score >= 0.48)
    }

    private func scoreOutroEvidence(
        timeSec: Double,
        durationSec: Double,
        barGrid: [BarMarker],
        energyProfile: [Double],
        transientMarkers: [TransientMarker],
        beatGridQuality: Double,
        downbeatConfidence: Double
    ) -> (score: Double, derived: Bool) {
        guard durationSec > 0 else {
            return (0, false)
        }
        let windowSec = min(18, max(6, durationSec * 0.08))
        let beforeEnergy = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: max(0, timeSec - windowSec),
            endSec: timeSec
        )
        let afterEnergy = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: timeSec,
            endSec: min(durationSec, timeSec + windowSec)
        )
        guard let beforeEnergy, let afterEnergy else {
            return (0, false)
        }
        let energyDrop = clamped((beforeEnergy - afterEnergy) / 0.22, min: 0, max: 1)
        let beforeDensity = transientDensity(
            transientMarkers: transientMarkers,
            startSec: max(0, timeSec - windowSec),
            endSec: timeSec
        )
        let afterDensity = transientDensity(
            transientMarkers: transientMarkers,
            startSec: timeSec,
            endSec: min(durationSec, timeSec + windowSec)
        )
        let densityDrop = clamped((beforeDensity - afterDensity) / max(0.12, beforeDensity), min: 0, max: 1)
        let remainingSec = durationSec - timeSec
        let remainingSupport = clamped(remainingSec / max(1, min(24, durationSec * 0.18)), min: 0, max: 1)
        let phraseSupport = barGrid.first(where: { abs($0.startSec - timeSec) <= 0.75 }).map {
            $0.index % 8 == 0 ? 1.0 : ($0.index % 4 == 0 ? 0.58 : 0.28)
        } ?? 0
        let gridSupport = clamped(beatGridQuality * 0.65 + downbeatConfidence * 0.35, min: 0, max: 1)
        let score = clamped(
            energyDrop * 0.34 +
                densityDrop * 0.22 +
                phraseSupport * 0.16 +
                remainingSupport * 0.14 +
                gridSupport * 0.14,
            min: 0,
            max: 1
        )
        return (
            score,
            energyDrop >= 0.28 &&
                densityDrop >= 0.18 &&
                remainingSec >= min(8, durationSec * 0.08) &&
                gridSupport >= 0.36 &&
                score >= 0.5
        )
    }

    private func scoreEnergyValleyEvidence(
        timeSec: Double,
        durationSec: Double,
        energyProfile: [Double],
        barGrid: [BarMarker],
        beatGridQuality: Double
    ) -> (score: Double, derived: Bool) {
        guard durationSec > 0 else {
            return (0, false)
        }
        let windowSec = min(12, max(4, durationSec * 0.06))
        let before = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: max(0, timeSec - windowSec),
            endSec: timeSec
        )
        let center = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: max(0, timeSec - windowSec * 0.35),
            endSec: min(durationSec, timeSec + windowSec * 0.35)
        )
        let after = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: timeSec,
            endSec: min(durationSec, timeSec + windowSec)
        )
        guard let before, let center, let after else {
            return (0, false)
        }
        let valleyDepth = clamped((min(before, after) - center) / 0.18, min: 0, max: 1)
        let surroundingEnergy = clamped(max(before, after) / 0.22, min: 0, max: 1)
        let phraseSupport = barGrid.first(where: { abs($0.startSec - timeSec) <= 0.75 }).map {
            $0.index % 4 == 0 ? 1.0 : 0.35
        } ?? 0
        let score = clamped(
            valleyDepth * 0.52 +
                surroundingEnergy * 0.2 +
                phraseSupport * 0.16 +
                beatGridQuality * 0.12,
            min: 0,
            max: 1
        )
        return (score, valleyDepth >= 0.42 && surroundingEnergy >= 0.45 && score >= 0.54)
    }

    private func scoreEnergyDropEvidence(
        timeSec: Double,
        durationSec: Double,
        energyProfile: [Double],
        spectralBands: [SpectralBandPoint],
        transientMarkers: [TransientMarker],
        barGrid: [BarMarker],
        beatGridQuality: Double
    ) -> (score: Double, derived: Bool) {
        guard durationSec > 0 else {
            return (0, false)
        }
        let windowSec = min(10, max(3, durationSec * 0.05))
        let before = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: max(0, timeSec - windowSec),
            endSec: timeSec
        )
        let after = averageEnergy(
            energyProfile: energyProfile,
            durationSec: durationSec,
            startSec: timeSec,
            endSec: min(durationSec, timeSec + windowSec)
        )
        guard let before, let after else {
            return (0, false)
        }
        let energyRise = clamped((after - before) / 0.2, min: 0, max: 1)
        let transientScore = nearbyTransientScore(
            transientMarkers: transientMarkers,
            timeSec: timeSec,
            windowSec: 0.25
        )
        let spectralScore = spectralChangeScore(
            spectralBands: spectralBands,
            durationSec: durationSec,
            timeSec: timeSec,
            windowSec: windowSec
        )
        let phraseSupport = barGrid.first(where: { abs($0.startSec - timeSec) <= 0.75 }).map {
            $0.index % 8 == 0 ? 1.0 : ($0.index % 4 == 0 ? 0.64 : 0.32)
        } ?? 0
        let score = clamped(
            energyRise * 0.38 +
                transientScore * 0.24 +
                spectralScore * 0.14 +
                phraseSupport * 0.14 +
                beatGridQuality * 0.1,
            min: 0,
            max: 1
        )
        return (score, energyRise >= 0.34 && (transientScore >= 0.22 || spectralScore >= 0.28) && score >= 0.52)
    }

    private func nearbyTransientScore(
        transientMarkers: [TransientMarker],
        timeSec: Double,
        windowSec: Double
    ) -> Double {
        guard windowSec > 0 else {
            return 0
        }
        return transientMarkers.reduce(0.0) { best, marker in
            let distance = abs(marker.timeSec - timeSec)
            guard distance <= windowSec else {
                return best
            }
            return max(best, marker.strength * (1 - distance / windowSec))
        }
    }

    private func transientDensity(
        transientMarkers: [TransientMarker],
        startSec: Double,
        endSec: Double
    ) -> Double {
        guard endSec > startSec else {
            return 0
        }
        let strength = transientMarkers.reduce(0.0) { sum, marker in
            marker.timeSec >= startSec && marker.timeSec < endSec
                ? sum + clamped(marker.strength, min: 0, max: 1)
                : sum
        }
        return strength / max(0.001, endSec - startSec)
    }

    private func spectralChangeScore(
        spectralBands: [SpectralBandPoint],
        durationSec: Double,
        timeSec: Double,
        windowSec: Double
    ) -> Double {
        guard let before = averageSpectralBand(
            spectralBands: spectralBands,
            durationSec: durationSec,
            startSec: max(0, timeSec - windowSec),
            endSec: timeSec
        ), let after = averageSpectralBand(
            spectralBands: spectralBands,
            durationSec: durationSec,
            startSec: timeSec,
            endSec: min(durationSec, timeSec + windowSec)
        ) else {
            return 0
        }
        let positiveDelta = max(0, after.low - before.low) +
            max(0, after.mid - before.mid) +
            max(0, after.high - before.high)
        return clamped(positiveDelta / 0.22, min: 0, max: 1)
    }

    private func averageSpectralBand(
        spectralBands: [SpectralBandPoint],
        durationSec: Double,
        startSec: Double,
        endSec: Double
    ) -> SpectralBandPoint? {
        guard !spectralBands.isEmpty, durationSec > 0, endSec > startSec else {
            return nil
        }
        let clampedStart = clamped(startSec, min: 0, max: durationSec)
        let clampedEnd = clamped(endSec, min: clampedStart, max: durationSec)
        guard clampedEnd > clampedStart else {
            return nil
        }
        var low = 0.0
        var mid = 0.0
        var high = 0.0
        var weight = 0.0
        for (index, band) in spectralBands.enumerated() {
            let bucketStart = (Double(index) / Double(spectralBands.count)) * durationSec
            let bucketEnd = (Double(index + 1) / Double(spectralBands.count)) * durationSec
            let overlap = min(bucketEnd, clampedEnd) - max(bucketStart, clampedStart)
            guard overlap > 0 else {
                continue
            }
            low += band.low * overlap
            mid += band.mid * overlap
            high += band.high * overlap
            weight += overlap
        }
        guard weight > 0 else {
            return nil
        }
        return SpectralBandPoint(timeSec: clampedStart, low: low / weight, mid: mid / weight, high: high / weight)
    }

    private func buildWarnings(
        bpm: Double?,
        bpmConfidence: Double,
        metadataMismatch: Bool,
        durationSec: Double,
        energyProfile: [Double],
        musicalKey: MusicalKeyEstimate?,
        loudness: LoudnessAnalysis?
    ) -> [AnalysisWarning] {
        var warnings: [AnalysisWarning] = []
        if bpm == nil {
            warnings.append(.bpmUnavailable)
        }
        if bpm != nil, bpmConfidence < 0.45 {
            warnings.append(.bpmLowConfidence)
        }
        if metadataMismatch {
            warnings.append(.bpmMetadataMismatch)
        }
        if bpm != nil {
            warnings.append(.beatGridEstimated)
        }
        if durationSec < 30 {
            warnings.append(.shortTrack)
        }
        if (energyProfile.max() ?? 0) < 0.05 {
            warnings.append(.flatEnergy)
        }
        if musicalKey == nil {
            warnings.append(.keyUnavailable)
        } else if (musicalKey?.confidence ?? 0) < Self.keyLowConfidenceThreshold {
            warnings.append(.keyLowConfidence)
        }
        if loudness == nil || (loudness?.confidence ?? 0) < Self.loudnessLowConfidenceThreshold {
            warnings.append(.loudnessLowConfidence)
        }
        if let loudness, loudness.headroomDb < Self.headroomLowThresholdDb {
            warnings.append(.headroomLow)
        }
        return warnings
    }

    private func pitchWeight(_ frequency: Double) -> Double {
        if frequency < 90 {
            return 0.35
        }
        if frequency > 2_500 {
            return 0.45
        }
        return 1
    }

    private func keyCorrelationCandidates(chroma: [Double]) -> [(root: Int, mode: MusicalKeyMode, score: Double)] {
        var candidates: [(root: Int, mode: MusicalKeyMode, score: Double)] = []
        for root in 0..<12 {
            candidates.append((root, .major, keyCorrelation(chroma: chroma, profile: Self.majorKeyProfile, root: root)))
            candidates.append((root, .minor, keyCorrelation(chroma: chroma, profile: Self.minorKeyProfile, root: root)))
        }
        return candidates.sorted { $0.score > $1.score }
    }

    private func keyCorrelation(chroma: [Double], profile: [Double], root: Int) -> Double {
        guard chroma.count == 12, profile.count == 12 else {
            return 0
        }
        let chromaMean = chroma.reduce(0, +) / 12
        let profileMean = profile.reduce(0, +) / 12
        var numerator = 0.0
        var chromaEnergy = 0.0
        var profileEnergy = 0.0
        for index in 0..<12 {
            let chromaValue = chroma[(index + root) % 12] - chromaMean
            let profileValue = profile[index] - profileMean
            numerator += chromaValue * profileValue
            chromaEnergy += chromaValue * chromaValue
            profileEnergy += profileValue * profileValue
        }
        guard chromaEnergy > 0, profileEnergy > 0 else {
            return 0
        }
        return max(0, numerator / sqrt(chromaEnergy * profileEnergy))
    }

    private func sampleStats(samples: [Float], start: Int, end: Int) -> (peak: Double, rms: Double, min: Double, max: Double) {
        guard start < end else {
            return (0, 0, 0, 0)
        }

        var peak = 0.0
        var sumSquares = 0.0
        var minValue = 0.0
        var maxValue = 0.0
        var count = 0
        for index in start..<end {
            let value = Double(samples[index])
            peak = max(peak, abs(value))
            sumSquares += value * value
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
            count += 1
        }
        return (
            peak,
            count > 0 ? sqrt(sumSquares / Double(count)) : 0,
            minValue,
            maxValue
        )
    }

    private func resolveBandAt(
        spectralBands: [SpectralBandPoint],
        waveformLength: Int,
        index: Int
    ) -> SpectralBandPoint? {
        guard !spectralBands.isEmpty else {
            return nil
        }
        if spectralBands.count == waveformLength {
            return spectralBands[index]
        }
        let spectralIndex = Int((Double(index) / Double(max(1, waveformLength - 1)) * Double(spectralBands.count - 1)).rounded())
        return spectralBands[clampedInt(spectralIndex, min: 0, max: spectralBands.count - 1)]
    }

    private func spectralBandAt(
        spectralBands: [SpectralBandPoint],
        durationSec: Double,
        timeSec: Double
    ) -> SpectralBandPoint? {
        guard !spectralBands.isEmpty, durationSec > 0 else {
            return nil
        }
        let index = clampedInt(
            Int(((timeSec / durationSec) * Double(spectralBands.count - 1)).rounded()),
            min: 0,
            max: spectralBands.count - 1
        )
        return spectralBands[index]
    }

    private func normalizeScores(_ values: [Double]) -> [Double] {
        let maxValue = max(0.000_001, values.max() ?? 0)
        return values.map { clamped($0 / maxValue, min: 0, max: 1) }
    }

    private func smoothScores(_ values: [Double], radius: Int) -> [Double] {
        guard values.count > 2, radius > 0 else {
            return values
        }

        return values.indices.map { index in
            var sum = 0.0
            var count = 0
            for offset in (-radius)...radius {
                let target = index + offset
                if values.indices.contains(target) {
                    sum += values[target]
                    count += 1
                }
            }
            return count > 0 ? sum / Double(count) : values[index]
        }
    }

    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        let clampedPercentile = clamped(percentile, min: 0, max: 1)
        let index = Int((Double(sorted.count - 1) * clampedPercentile).rounded())
        return sorted[clampedInt(index, min: 0, max: sorted.count - 1)]
    }

    private func db(_ linear: Double) -> Double {
        guard linear.isFinite, linear > 0 else {
            return -60
        }
        return max(-60, 20 * log10(linear))
    }

    private func rounded(_ value: Double, digits: Int = 3) -> Double {
        let multiplier = pow(10, Double(max(0, digits)))
        return (value * multiplier).rounded() / multiplier
    }

    private func hannWindow(size: Int) -> [Double] {
        guard size > 1 else {
            return [1]
        }
        return (0..<size).map { index in
            0.5 - 0.5 * cos((2 * .pi * Double(index)) / Double(size - 1))
        }
    }

    private func fftInPlace(real: inout [Double], imag: inout [Double]) {
        let size = real.count
        let bitCount = Int(log2(Double(size)))

        for index in 0..<size {
            let reversed = reverseBits(index, bitCount: bitCount)
            if reversed > index {
                real.swapAt(index, reversed)
                imag.swapAt(index, reversed)
            }
        }

        var width = 2
        while width <= size {
            let halfWidth = width / 2
            let phaseStep = (-2 * .pi) / Double(width)
            var start = 0
            while start < size {
                for offset in 0..<halfWidth {
                    let evenIndex = start + offset
                    let oddIndex = evenIndex + halfWidth
                    let angle = phaseStep * Double(offset)
                    let cosine = cos(angle)
                    let sine = sin(angle)
                    let oddReal = real[oddIndex] * cosine - imag[oddIndex] * sine
                    let oddImag = real[oddIndex] * sine + imag[oddIndex] * cosine
                    let evenReal = real[evenIndex]
                    let evenImag = imag[evenIndex]

                    real[evenIndex] = evenReal + oddReal
                    imag[evenIndex] = evenImag + oddImag
                    real[oddIndex] = evenReal - oddReal
                    imag[oddIndex] = evenImag - oddImag
                }
                start += width
            }
            width *= 2
        }
    }

    private func reverseBits(_ value: Int, bitCount: Int) -> Int {
        var value = value
        var reversed = 0
        for _ in 0..<bitCount {
            reversed = (reversed << 1) | (value & 1)
            value >>= 1
        }
        return reversed
    }

    private func energyAt(energyProfile: [Double], durationSec: Double, timeSec: Double) -> Double {
        guard !energyProfile.isEmpty, durationSec > 0 else {
            return 0
        }
        let index = clampedInt(
            Int(((timeSec / durationSec) * Double(energyProfile.count - 1)).rounded()),
            min: 0,
            max: energyProfile.count - 1
        )
        return energyProfile[index]
    }
}

private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    Swift.min(maxValue, Swift.max(minValue, value.isFinite ? value : minValue))
}

private func clampedInt(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
    Swift.min(maxValue, Swift.max(minValue, value))
}
