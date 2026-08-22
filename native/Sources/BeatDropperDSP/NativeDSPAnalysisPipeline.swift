import BeatDropperDomain
import Foundation

public struct NativeDSPAnalyzer: Sendable {
    private let pipeline = NativeDSPAnalysisPipeline()

    public init() {}

    public func analyze(
        track: Track,
        buffer: PCMAnalysisBuffer,
        fileRevision: TrackFileRevision? = nil,
        generatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> TrackAnalysis {
        pipeline.analyze(track: track, buffer: buffer, fileRevision: fileRevision, generatedAt: generatedAt)
    }
}

private struct NativeDSPAnalysisPipeline: Sendable {
    private let kernel = NativeDSPAnalysisKernel()

    func analyze(
        track: Track,
        buffer: PCMAnalysisBuffer,
        fileRevision: TrackFileRevision?,
        generatedAt: String
    ) -> TrackAnalysis {
        let pcm = PCMPreparationStage(kernel: kernel).run(track: track, buffer: buffer)
        let waveform = WaveformSpectralExtractionStage(kernel: kernel).run(
            buffer: buffer,
            durationSec: pcm.durationSec
        )
        let dynamics = LoudnessStereoAnalysisStage(kernel: kernel).run(
            buffer: buffer,
            durationSec: pcm.durationSec
        )
        let transients = TransientTempoAnalysisStage(kernel: kernel).run(
            track: track,
            waveform: waveform,
            durationSec: pcm.durationSec
        )
        let rhythm = BeatPhraseAnalysisStage(kernel: kernel).run(
            transients: transients,
            waveform: waveform,
            durationSec: pcm.durationSec
        )
        let quality = AnalysisQualityWarningStage(kernel: kernel).run(
            transients: transients,
            rhythm: rhythm,
            waveform: waveform,
            dynamics: dynamics,
            durationSec: pcm.durationSec
        )
        let cues = CueGenerationStage(kernel: kernel).run(
            rhythm: rhythm,
            transients: transients,
            waveform: waveform,
            transientQuality: quality.transientQuality,
            durationSec: pcm.durationSec
        )

        return TrackAnalysis(
            trackId: track.id,
            generatedAt: generatedAt,
            source: transients.source,
            fileRevision: fileRevision,
            bpm: transients.bpm,
            bpmConfidence: transients.bpmConfidence,
            beatGridSec: rhythm.beatGridSec,
            downbeatsSec: rhythm.downbeatsSec,
            barGrid: rhythm.barGrid,
            phraseMarkers: rhythm.phraseMarkers,
            introCueSec: cues.introCueSec,
            outroCueSec: cues.outroCueSec,
            energyProfile: waveform.energyProfile,
            waveformPeaks: waveform.waveformPeaks,
            waveformDetail: waveform.waveformDetail,
            spectralBands: waveform.spectralBands,
            transientMarkers: transients.markers,
            cueCandidates: cues.candidates,
            musicalKey: waveform.musicalKey,
            loudness: dynamics.loudness,
            stereo: dynamics.stereo,
            analysisConfidence: quality.analysisConfidence,
            analysisQuality: quality.analysisQuality,
            analysisWarnings: quality.warnings
        )
    }
}

private struct PCMPreparationResult: Sendable {
    let durationSec: Double
}

private struct PCMPreparationStage: Sendable {
    let kernel: NativeDSPAnalysisKernel

    func run(track: Track, buffer: PCMAnalysisBuffer) -> PCMPreparationResult {
        PCMPreparationResult(durationSec: kernel.resolveDuration(track: track, buffer: buffer))
    }
}

private struct WaveformSpectralResult: Sendable {
    let energyProfile: [Double]
    let waveformPeaks: [WaveformPeak]
    let waveformDetail: [WaveformDetailPoint]
    let spectralBands: [SpectralBandPoint]
    let musicalKey: MusicalKeyEstimate?
}

private struct WaveformSpectralExtractionStage: Sendable {
    let kernel: NativeDSPAnalysisKernel

    func run(buffer: PCMAnalysisBuffer, durationSec: Double) -> WaveformSpectralResult {
        let detail = kernel.buildWaveformDetail(samples: buffer.samples, durationSec: durationSec)
        return WaveformSpectralResult(
            energyProfile: kernel.buildEnergyProfile(samples: buffer.samples, durationSec: durationSec),
            waveformPeaks: kernel.buildWaveformPeaks(samples: buffer.samples, durationSec: durationSec),
            waveformDetail: detail,
            spectralBands: kernel.buildSpectralBands(
                samples: buffer.samples,
                sampleRate: buffer.sampleRate,
                durationSec: durationSec,
                bucketCount: detail.count
            ),
            musicalKey: kernel.estimateMusicalKey(
                samples: buffer.samples,
                sampleRate: buffer.sampleRate,
                durationSec: durationSec
            )
        )
    }
}

private struct LoudnessStereoResult: Sendable {
    let loudness: LoudnessAnalysis?
    let stereo: StereoAnalysis?
}

private struct LoudnessStereoAnalysisStage: Sendable {
    let kernel: NativeDSPAnalysisKernel

    func run(buffer: PCMAnalysisBuffer, durationSec: Double) -> LoudnessStereoResult {
        LoudnessStereoResult(
            loudness: kernel.buildLoudnessAnalysis(buffer: buffer, durationSec: durationSec),
            stereo: kernel.buildStereoAnalysis(buffer: buffer)
        )
    }
}

private struct TransientTempoResult: Sendable {
    let markers: [TransientMarker]
    let bpm: Double?
    let bpmConfidence: Double
    let source: TrackAnalysisSource
    let metadataMismatch: Bool
}

private struct TransientTempoAnalysisStage: Sendable {
    let kernel: NativeDSPAnalysisKernel

    func run(
        track: Track,
        waveform: WaveformSpectralResult,
        durationSec: Double
    ) -> TransientTempoResult {
        let onset = kernel.buildOnsetEnvelope(
            waveformDetail: waveform.waveformDetail,
            spectralBands: waveform.spectralBands,
            durationSec: durationSec
        )
        let markers = kernel.buildTransientMarkers(onsetEnvelope: onset, durationSec: durationSec)
        let resolved = kernel.resolveAnalysisBPM(track: track, estimate: kernel.estimateBPM(transientMarkers: markers))
        return TransientTempoResult(
            markers: markers,
            bpm: resolved.bpm,
            bpmConfidence: resolved.confidence,
            source: resolved.source,
            metadataMismatch: resolved.metadataMismatch
        )
    }
}

private struct BeatPhraseResult: Sendable {
    let beatGridSec: [Double]
    let downbeatsSec: [Double]
    let barGrid: [BarMarker]
    let phraseMarkers: [PhraseMarker]
    let beatGridQuality: Double
    let beatPhaseConfidence: Double
    let downbeatConfidence: Double
}

private struct BeatPhraseAnalysisStage: Sendable {
    let kernel: NativeDSPAnalysisKernel

    func run(
        transients: TransientTempoResult,
        waveform: WaveformSpectralResult,
        durationSec: Double
    ) -> BeatPhraseResult {
        let beatIntervalSec = transients.bpm.map { 60 / $0 }
        let beatPhase = beatIntervalSec.map {
            kernel.resolveBeatPhaseOffset(beatIntervalSec: $0, transientMarkers: transients.markers)
        } ?? (offsetSec: 0, confidence: 0)
        let beatGridSec = beatIntervalSec.map {
            kernel.buildBeatGrid(durationSec: durationSec, beatIntervalSec: $0, beatOffsetSec: beatPhase.offsetSec)
        } ?? []
        let downbeats = kernel.buildDownbeatGrid(
            beatGridSec: beatGridSec,
            transientMarkers: transients.markers,
            energyProfile: waveform.energyProfile,
            spectralBands: waveform.spectralBands,
            durationSec: durationSec
        )
        let beatGridQuality = beatGridSec.isEmpty ? 0 : clamp(
            (transients.bpmConfidence * 0.44) +
                (beatPhase.confidence * 0.2) +
                (downbeats.confidence * 0.24) +
                min(0.12, Double(beatGridSec.count) / 900)
        )
        return BeatPhraseResult(
            beatGridSec: beatGridSec,
            downbeatsSec: downbeats.downbeatsSec,
            barGrid: downbeats.barGrid,
            phraseMarkers: kernel.buildPhraseMarkers(
                barGrid: downbeats.barGrid,
                energyProfile: waveform.energyProfile,
                durationSec: durationSec,
                beatGridQuality: beatGridQuality,
                downbeatConfidence: downbeats.confidence
            ),
            beatGridQuality: beatGridQuality,
            beatPhaseConfidence: beatPhase.confidence,
            downbeatConfidence: downbeats.confidence
        )
    }
}

private struct CueGenerationResult: Sendable {
    let introCueSec: Double
    let outroCueSec: Double?
    let candidates: [CueCandidate]
}

private struct CueGenerationStage: Sendable {
    let kernel: NativeDSPAnalysisKernel

    func run(
        rhythm: BeatPhraseResult,
        transients: TransientTempoResult,
        waveform: WaveformSpectralResult,
        transientQuality: Double,
        durationSec: Double
    ) -> CueGenerationResult {
        let introCueSec = 0.0
        let outroCueSec = kernel.resolveOutroCueSec(barGrid: rhythm.barGrid, durationSec: durationSec)
        let lowEnergyRaw = kernel.findEnergyTime(
            energyProfile: waveform.energyProfile,
            durationSec: durationSec,
            findMax: false,
            startRatio: 0.35,
            endRatio: 0.8
        )
        let highEnergyRaw = kernel.findEnergyTime(
            energyProfile: waveform.energyProfile,
            durationSec: durationSec,
            findMax: true,
            startRatio: 0.05,
            endRatio: 0.55
        )
        let lowEnergy = lowEnergyRaw.map { kernel.snapToNearestBar(barGrid: rhythm.barGrid, timeSec: $0) ?? $0 }
        let highEnergy = highEnergyRaw.map { kernel.snapToNearestBar(barGrid: rhythm.barGrid, timeSec: $0) ?? $0 }
        return CueGenerationResult(
            introCueSec: introCueSec,
            outroCueSec: outroCueSec,
            candidates: kernel.buildCueCandidates(
                durationSec: durationSec,
                introCueSec: introCueSec,
                firstDownbeatSec: rhythm.downbeatsSec.first,
                outroCueSec: outroCueSec,
                lowEnergyBreakSec: lowEnergy,
                highEnergyDropSec: highEnergy,
                barGrid: rhythm.barGrid,
                energyProfile: waveform.energyProfile,
                spectralBands: waveform.spectralBands,
                transientMarkers: transients.markers,
                beatGridQuality: rhythm.beatGridQuality,
                downbeatConfidence: rhythm.downbeatConfidence,
                transientQuality: transientQuality
            )
        )
    }
}

private struct AnalysisQualityWarningResult: Sendable {
    let transientQuality: Double
    let analysisQuality: AnalysisQuality
    let analysisConfidence: Double
    let warnings: [AnalysisWarning]
}

private struct AnalysisQualityWarningStage: Sendable {
    let kernel: NativeDSPAnalysisKernel

    func run(
        transients: TransientTempoResult,
        rhythm: BeatPhraseResult,
        waveform: WaveformSpectralResult,
        dynamics: LoudnessStereoResult,
        durationSec: Double
    ) -> AnalysisQualityWarningResult {
        let transientQuality = kernel.scoreTransientMarkerQuality(
            transientMarkers: transients.markers,
            beatGridSec: rhythm.beatGridSec,
            durationSec: durationSec,
            beatPhaseConfidence: rhythm.beatPhaseConfidence,
            downbeatConfidence: rhythm.downbeatConfidence
        )
        let analysisQuality = AnalysisQuality(
            waveformDetail: clamp(Double(waveform.waveformDetail.count) / Double(NativeDSPAnalysisKernel.waveformDetailMaxBuckets)),
            spectralBands: clamp(Double(waveform.spectralBands.count) / Double(NativeDSPAnalysisKernel.waveformDetailMaxBuckets)),
            transientMarkers: transientQuality,
            beatGrid: rhythm.beatGridQuality,
            harmonicKey: waveform.musicalKey?.confidence ?? 0
        )
        var confidenceScore = 0.2
        confidenceScore += transients.bpm == nil ? 0 : 0.22
        confidenceScore += rhythm.beatGridQuality * 0.2
        confidenceScore += waveform.energyProfile.count > 8 ? 0.14 : 0
        confidenceScore += waveform.waveformPeaks.count > 8 ? 0.1 : 0
        confidenceScore += waveform.spectralBands.count > 8 ? 0.08 : 0
        confidenceScore += transientQuality * 0.06
        confidenceScore += (waveform.musicalKey?.confidence ?? 0) * 0.03
        confidenceScore += (dynamics.loudness?.confidence ?? 0) * 0.03
        let analysisConfidence = clamp(confidenceScore)
        return AnalysisQualityWarningResult(
            transientQuality: transientQuality,
            analysisQuality: analysisQuality,
            analysisConfidence: analysisConfidence,
            warnings: kernel.buildWarnings(
                bpm: transients.bpm,
                bpmConfidence: transients.bpmConfidence,
                metadataMismatch: transients.metadataMismatch,
                durationSec: durationSec,
                energyProfile: waveform.energyProfile,
                musicalKey: waveform.musicalKey,
                loudness: dynamics.loudness
            )
        )
    }
}

private func clamp(_ value: Double) -> Double {
    min(1, max(0, value))
}
