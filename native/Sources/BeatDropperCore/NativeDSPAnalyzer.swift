import Foundation

public struct PCMAnalysisBuffer: Sendable {
    public var samples: [Float]
    public var sampleRate: Double
    public var durationSec: Double

    public init(samples: [Float], sampleRate: Double, durationSec: Double) {
        self.samples = samples
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
        let firstDownbeatSec = downbeatGrid.downbeatsSec.first ?? 0
        let outroCueSec = resolveOutroCueSec(barGrid: downbeatGrid.barGrid, durationSec: durationSec)
        let lowEnergyBreakSec = findEnergyTime(
            energyProfile: energyProfile,
            durationSec: durationSec,
            findMax: false,
            startRatio: 0.35,
            endRatio: 0.8
        )
        let highEnergyDropSec = findEnergyTime(
            energyProfile: energyProfile,
            durationSec: durationSec,
            findMax: true,
            startRatio: 0.05,
            endRatio: 0.55
        )
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
            beatGrid: beatGridQuality
        )
        let analysisConfidence = clamped(
            0.2 +
                (bpm == nil ? 0 : 0.22) +
                beatGridQuality * 0.2 +
                (energyProfile.count > 8 ? 0.14 : 0) +
                (waveformPeaks.count > 8 ? 0.1 : 0) +
                (spectralBands.count > 8 ? 0.08 : 0) +
                transientQuality * 0.06,
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
                beatGridQuality: beatGridQuality,
                transientQuality: transientQuality
            ),
            analysisConfidence: analysisConfidence,
            analysisQuality: analysisQuality,
            analysisWarnings: buildWarnings(
                bpm: bpm,
                bpmConfidence: resolvedBPM.confidence,
                metadataMismatch: resolvedBPM.metadataMismatch,
                durationSec: durationSec,
                energyProfile: energyProfile
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

    private func buildCueCandidates(
        durationSec: Double,
        introCueSec: Double,
        firstDownbeatSec: Double,
        outroCueSec: Double?,
        lowEnergyBreakSec: Double?,
        highEnergyDropSec: Double?,
        beatGridQuality: Double,
        transientQuality: Double
    ) -> [CueCandidate] {
        var cues = [
            CueCandidate(
                id: "intro",
                type: .intro,
                startSec: introCueSec,
                endSec: min(durationSec, introCueSec + 8),
                confidence: clamped(0.36 + beatGridQuality * 0.2, min: 0, max: 0.8),
                label: "Intro"
            ),
            CueCandidate(
                id: "first-downbeat",
                type: .firstDownbeat,
                startSec: firstDownbeatSec,
                endSec: min(durationSec, firstDownbeatSec + 4),
                confidence: clamped(0.34 + beatGridQuality * 0.32 + transientQuality * 0.16, min: 0, max: 0.86),
                label: "First downbeat"
            )
        ]
        if let outroCueSec {
            cues.append(CueCandidate(
                id: "outro",
                type: .outro,
                startSec: outroCueSec,
                endSec: durationSec,
                confidence: clamped(0.4 + beatGridQuality * 0.2, min: 0, max: 0.78),
                label: "Outro mix-out"
            ))
        }
        if let lowEnergyBreakSec {
            cues.append(CueCandidate(
                id: "low-energy-break",
                type: .lowEnergyBreak,
                startSec: lowEnergyBreakSec,
                endSec: min(durationSec, lowEnergyBreakSec + 8),
                confidence: clamped(0.42 + beatGridQuality * 0.18, min: 0, max: 0.72),
                label: "Low-energy break"
            ))
        }
        if let highEnergyDropSec {
            cues.append(CueCandidate(
                id: "high-energy-drop",
                type: .highEnergyDrop,
                startSec: highEnergyDropSec,
                endSec: min(durationSec, highEnergyDropSec + 8),
                confidence: clamped(0.4 + beatGridQuality * 0.18, min: 0, max: 0.72),
                label: "High-energy drop"
            ))
        }
        return cues
    }

    private func buildWarnings(
        bpm: Double?,
        bpmConfidence: Double,
        metadataMismatch: Bool,
        durationSec: Double,
        energyProfile: [Double]
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
        return warnings
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
