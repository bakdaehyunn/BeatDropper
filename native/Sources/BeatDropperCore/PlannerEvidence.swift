import Foundation

public enum PlannerEnergyTrendDirection: String, Codable, Sendable {
    case rising
    case falling
    case flat
    case unknown
}

public struct PlannerCueSummary: Codable, Hashable, Sendable {
    public var type: CueCandidateType
    public var startSec: Double
    public var confidence: Double
    public var label: String
    public var origin: CueCandidateOrigin

    public init(
        type: CueCandidateType,
        startSec: Double,
        confidence: Double,
        label: String,
        origin: CueCandidateOrigin = .derived
    ) {
        self.type = type
        self.startSec = startSec
        self.confidence = confidence
        self.label = label
        self.origin = origin
    }
}

public struct PlannerCueGroupSummary: Codable, Hashable, Sendable {
    public var intro: PlannerCueSummary?
    public var firstDownbeat: PlannerCueSummary?
    public var outro: PlannerCueSummary?

    public init(intro: PlannerCueSummary?, firstDownbeat: PlannerCueSummary?, outro: PlannerCueSummary?) {
        self.intro = intro
        self.firstDownbeat = firstDownbeat
        self.outro = outro
    }
}

public struct PlannerEnergyTrendSummary: Codable, Hashable, Sendable {
    public var early: Double?
    public var mid: Double?
    public var late: Double?
    public var direction: PlannerEnergyTrendDirection

    public init(early: Double?, mid: Double?, late: Double?, direction: PlannerEnergyTrendDirection) {
        self.early = early
        self.mid = mid
        self.late = late
        self.direction = direction
    }
}

public struct PlannerBeatStabilitySummary: Codable, Hashable, Sendable {
    public var score: Double
    public var label: String
    public var beatGridQuality: Double
    public var transientQuality: Double

    public init(score: Double, label: String, beatGridQuality: Double, transientQuality: Double) {
        self.score = score
        self.label = label
        self.beatGridQuality = beatGridQuality
        self.transientQuality = transientQuality
    }
}

public struct PlannerTransientSummary: Codable, Hashable, Sendable {
    public var count: Int
    public var strongCount: Int
    public var densityPerSec: Double

    public init(count: Int, strongCount: Int, densityPerSec: Double) {
        self.count = count
        self.strongCount = strongCount
        self.densityPerSec = densityPerSec
    }
}

public struct PlannerPhraseBoundarySummary: Codable, Hashable, Sendable {
    public var index: Int
    public var startSec: Double
    public var bars: Int
    public var confidence: Double

    public init(index: Int, startSec: Double, bars: Int, confidence: Double) {
        self.index = index
        self.startSec = startSec
        self.bars = bars
        self.confidence = confidence
    }
}

public struct PlannerPhraseSummary: Codable, Hashable, Sendable {
    public var barCount: Int
    public var phraseCount: Int
    public var strongestBoundaries: [PlannerPhraseBoundarySummary]

    public init(barCount: Int, phraseCount: Int, strongestBoundaries: [PlannerPhraseBoundarySummary]) {
        self.barCount = barCount
        self.phraseCount = phraseCount
        self.strongestBoundaries = strongestBoundaries
    }
}

public struct PlannerHarmonicSummary: Codable, Hashable, Sendable {
    public var key: String?
    public var mode: MusicalKeyMode?
    public var confidence: Double
    public var evidence: MixEvidenceLevel

    public init(key: String?, mode: MusicalKeyMode?, confidence: Double, evidence: MixEvidenceLevel) {
        self.key = key
        self.mode = mode
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct PlannerLoudnessSummary: Codable, Hashable, Sendable {
    public var integratedRMSDb: Double?
    public var peakDb: Double?
    public var headroomDb: Double?
    public var dynamicRangeDb: Double?
    public var confidence: Double
    public var evidence: MixEvidenceLevel

    public init(
        integratedRMSDb: Double?,
        peakDb: Double?,
        headroomDb: Double?,
        dynamicRangeDb: Double?,
        confidence: Double,
        evidence: MixEvidenceLevel
    ) {
        self.integratedRMSDb = integratedRMSDb
        self.peakDb = peakDb
        self.headroomDb = headroomDb
        self.dynamicRangeDb = dynamicRangeDb
        self.confidence = confidence
        self.evidence = evidence
    }
}

public enum PlannerMixWindowKind: String, Codable, Sendable {
    case intro
    case firstDownbeat = "first_downbeat"
    case outro
    case lowEnergyBreak = "low_energy_break"
    case highEnergyDrop = "high_energy_drop"
    case phrase
    case transient
    case trackStart = "track_start"
}

public struct PlannerMixWindowSummary: Codable, Hashable, Sendable {
    public var kind: PlannerMixWindowKind
    public var source: MixCandidateSource
    public var startSec: Double
    public var endSec: Double
    public var confidence: Double
    public var label: String

    public init(
        kind: PlannerMixWindowKind,
        source: MixCandidateSource,
        startSec: Double,
        endSec: Double,
        confidence: Double,
        label: String
    ) {
        self.kind = kind
        self.source = source
        self.startSec = startSec
        self.endSec = endSec
        self.confidence = confidence
        self.label = label
    }
}

public struct PlannerMixWindowGroupSummary: Codable, Hashable, Sendable {
    public var mixIn: [PlannerMixWindowSummary]
    public var mixOut: [PlannerMixWindowSummary]

    public init(mixIn: [PlannerMixWindowSummary], mixOut: [PlannerMixWindowSummary]) {
        self.mixIn = mixIn
        self.mixOut = mixOut
    }
}

public struct PlannerAnalysisTrackSummary: Codable, Hashable, Sendable {
    public var trackId: String
    public var source: TrackAnalysisSource
    public var plannerReady: Bool
    public var bpm: Double?
    public var bpmConfidence: Double
    public var analysisConfidence: Double
    public var analysisQuality: AnalysisQuality
    public var analysisWarnings: [AnalysisWarning]
    public var cues: PlannerCueGroupSummary
    public var energyTrend: PlannerEnergyTrendSummary
    public var beatStability: PlannerBeatStabilitySummary
    public var transients: PlannerTransientSummary
    public var phrases: PlannerPhraseSummary
    public var harmonic: PlannerHarmonicSummary
    public var loudness: PlannerLoudnessSummary
    public var mixWindows: PlannerMixWindowGroupSummary

    public init(
        trackId: String,
        source: TrackAnalysisSource,
        plannerReady: Bool,
        bpm: Double?,
        bpmConfidence: Double,
        analysisConfidence: Double,
        analysisQuality: AnalysisQuality,
        analysisWarnings: [AnalysisWarning],
        cues: PlannerCueGroupSummary,
        energyTrend: PlannerEnergyTrendSummary,
        beatStability: PlannerBeatStabilitySummary,
        transients: PlannerTransientSummary,
        phrases: PlannerPhraseSummary,
        harmonic: PlannerHarmonicSummary,
        loudness: PlannerLoudnessSummary,
        mixWindows: PlannerMixWindowGroupSummary
    ) {
        self.trackId = trackId
        self.source = source
        self.plannerReady = plannerReady
        self.bpm = bpm
        self.bpmConfidence = bpmConfidence
        self.analysisConfidence = analysisConfidence
        self.analysisQuality = analysisQuality
        self.analysisWarnings = analysisWarnings
        self.cues = cues
        self.energyTrend = energyTrend
        self.beatStability = beatStability
        self.transients = transients
        self.phrases = phrases
        self.harmonic = harmonic
        self.loudness = loudness
        self.mixWindows = mixWindows
    }
}

public struct PlannerAnalysisSummary: Codable, Hashable, Sendable {
    public var current: PlannerAnalysisTrackSummary?
    public var next: PlannerAnalysisTrackSummary?

    public init(current: PlannerAnalysisTrackSummary?, next: PlannerAnalysisTrackSummary?) {
        self.current = current
        self.next = next
    }
}

public enum MixCandidateSource: String, Codable, Sendable {
    case analysis
    case cue
    case tailFallback = "tail_fallback"
}

public enum MixEvidenceLevel: String, Codable, Sendable {
    case strong
    case partial
    case fallback
}

public enum MixPairReadiness: String, Codable, Sendable {
    case ready
    case analysisPending = "analysis_pending"
    case fallbackOnly = "fallback_only"
}

public struct MixCandidate: Codable, Hashable, Sendable {
    public var id: String
    public var currentTrackId: String
    public var nextTrackId: String
    public var source: MixCandidateSource
    public var evidenceLevel: MixEvidenceLevel
    public var requiresAnalysisUpgrade: Bool
    public var currentMixOutSec: Double
    public var nextMixInSec: Double
    public var currentBarIndex: Int?
    public var nextBarIndex: Int?
    public var phraseAlignment: PhraseAlignment
    public var bpmDelta: Double?
    public var tempoSyncRate: Double?
    public var energyDelta: Double?
    public var style: MixStyle
    public var score: Double
    public var confidence: Double
    public var reason: String

    public init(
        id: String,
        currentTrackId: String,
        nextTrackId: String,
        source: MixCandidateSource,
        evidenceLevel: MixEvidenceLevel,
        requiresAnalysisUpgrade: Bool,
        currentMixOutSec: Double,
        nextMixInSec: Double,
        currentBarIndex: Int?,
        nextBarIndex: Int?,
        phraseAlignment: PhraseAlignment,
        bpmDelta: Double?,
        tempoSyncRate: Double?,
        energyDelta: Double?,
        style: MixStyle,
        score: Double,
        confidence: Double,
        reason: String
    ) {
        self.id = id
        self.currentTrackId = currentTrackId
        self.nextTrackId = nextTrackId
        self.source = source
        self.evidenceLevel = evidenceLevel
        self.requiresAnalysisUpgrade = requiresAnalysisUpgrade
        self.currentMixOutSec = currentMixOutSec
        self.nextMixInSec = nextMixInSec
        self.currentBarIndex = currentBarIndex
        self.nextBarIndex = nextBarIndex
        self.phraseAlignment = phraseAlignment
        self.bpmDelta = bpmDelta
        self.tempoSyncRate = tempoSyncRate
        self.energyDelta = energyDelta
        self.style = style
        self.score = score
        self.confidence = confidence
        self.reason = reason
    }
}

public struct MixPairContext: Codable, Hashable, Sendable {
    public var currentTrackId: String
    public var nextTrackId: String
    public var candidates: [MixCandidate]
    public var recommendedCandidateId: String?
    public var readiness: MixPairReadiness

    public init(
        currentTrackId: String,
        nextTrackId: String,
        candidates: [MixCandidate],
        recommendedCandidateId: String?,
        readiness: MixPairReadiness
    ) {
        self.currentTrackId = currentTrackId
        self.nextTrackId = nextTrackId
        self.candidates = candidates
        self.recommendedCandidateId = recommendedCandidateId
        self.readiness = readiness
    }
}

public enum PlannerEvidenceBuilder {
    public static func buildPlannerAnalysisSummary(
        currentTrack: Track,
        nextTrack: Track,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?
    ) -> PlannerAnalysisSummary {
        PlannerAnalysisSummary(
            current: buildPlannerAnalysisTrackSummary(track: currentTrack, analysis: currentAnalysis),
            next: buildPlannerAnalysisTrackSummary(track: nextTrack, analysis: nextAnalysis)
        )
    }

    public static func buildMixPairContext(
        currentTrack: Track,
        nextTrack: Track,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?,
        maxCandidates: Int = 5
    ) -> MixPairContext {
        let currentDuration = max(0, currentTrack.durationSec)
        let nextDuration = max(0, nextTrack.durationSec)
        let currentAnalysisPoints = buildAnalysisOutPoints(analysis: currentAnalysis, durationSec: currentDuration)
        let nextAnalysisPoints = buildAnalysisInPoints(analysis: nextAnalysis, durationSec: nextDuration)
        let currentCuePoints = buildCueOutPoints(analysis: currentAnalysis)
        let nextCuePoints = buildCueInPoints(analysis: nextAnalysis)
        let tailFallbackPoints = [
            CandidatePoint(
                timeSec: max(0, currentDuration - 16),
                source: .tailFallback,
                evidenceLevel: .fallback,
                confidence: 0.22,
                reason: "tail fallback -16s"
            ),
            CandidatePoint(
                timeSec: max(0, currentDuration - 8),
                source: .tailFallback,
                evidenceLevel: .fallback,
                confidence: 0.18,
                reason: "tail fallback -8s"
            )
        ]
        let currentOutCandidates = currentAnalysisPoints.isEmpty
            ? (currentCuePoints.isEmpty ? tailFallbackPoints : currentCuePoints + tailFallbackPoints)
            : currentAnalysisPoints + currentCuePoints + tailFallbackPoints
        let nextInCandidates = nextAnalysisPoints.isEmpty ? nextCuePoints : nextAnalysisPoints + nextCuePoints
        let hasAnalysisCandidate = !currentAnalysisPoints.isEmpty && !nextAnalysisPoints.isEmpty
        let hasDerivedCueCandidate = currentCuePoints.contains { !$0.isPlaceholder } &&
            nextCuePoints.contains { !$0.isPlaceholder }
        let readiness: MixPairReadiness = if hasAnalysisCandidate || hasDerivedCueCandidate {
            .ready
        } else if hasPendingAnalysisUpgrade(currentAnalysis) || hasPendingAnalysisUpgrade(nextAnalysis) {
            .analysisPending
        } else {
            .fallbackOnly
        }
        let requiresAnalysisUpgrade = readiness != .ready
        let bpmCurrent = currentAnalysis?.bpm ?? currentTrack.bpm
        let bpmNext = nextAnalysis?.bpm ?? nextTrack.bpm
        let bpmDelta = if let bpmCurrent, let bpmNext {
            abs(bpmCurrent - bpmNext)
        } else {
            Optional<Double>.none
        }
        let tempoSyncRate = if let bpmCurrent, let bpmNext, bpmNext > 0 {
            clamped(bpmCurrent / bpmNext, min: 0.85, max: 1.15)
        } else {
            Optional<Double>.none
        }

        var candidates: [MixCandidate] = []
        for outPoint in currentOutCandidates.prefix(6) {
            for inPoint in nextInCandidates.prefix(4) {
                let currentMixOutSec = clamped(outPoint.timeSec, min: 0, max: currentDuration)
                let nextMixInSec = clamped(inPoint.timeSec, min: 0, max: nextDuration)
                let source: MixCandidateSource = outPoint.source == .tailFallback
                    ? .tailFallback
                    : (outPoint.source == .analysis || inPoint.source == .analysis ? .analysis : .cue)
                let evidenceLevel: MixEvidenceLevel = if source == .tailFallback {
                    .fallback
                } else if outPoint.evidenceLevel == .strong || inPoint.evidenceLevel == .strong {
                    .strong
                } else {
                    .partial
                }
                let currentBarIndex = nearestBarIndex(analysis: currentAnalysis, timeSec: currentMixOutSec)
                let nextBarIndex = nearestBarIndex(analysis: nextAnalysis, timeSec: nextMixInSec)
                let phraseAlignment = resolvePhraseAlignment(currentBarIndex: currentBarIndex, nextBarIndex: nextBarIndex)
                let currentEnergy = energyAt(analysis: currentAnalysis, timeSec: currentMixOutSec, durationSec: currentDuration)
                let nextEnergy = energyAt(analysis: nextAnalysis, timeSec: nextMixInSec, durationSec: nextDuration)
                let energyDelta = if let currentEnergy, let nextEnergy {
                    nextEnergy - currentEnergy
                } else {
                    Optional<Double>.none
                }
                let score = scoreCandidate(
                    source: source,
                    evidenceLevel: evidenceLevel,
                    phraseAlignment: phraseAlignment,
                    bpmDelta: bpmDelta,
                    energyDelta: energyDelta,
                    outConfidence: outPoint.confidence,
                    inConfidence: inPoint.confidence,
                    currentAnalysis: currentAnalysis,
                    nextAnalysis: nextAnalysis
                )
                let style = resolveStyle(phraseAlignment: phraseAlignment, bpmDelta: bpmDelta, energyDelta: energyDelta)
                let id = "\(source.rawValue):\(currentTrack.id):\(Int((currentMixOutSec * 100).rounded()))->\(nextTrack.id):\(Int((nextMixInSec * 100).rounded()))"
                let candidateRequiresAnalysisUpgrade = requiresAnalysisUpgrade || outPoint.isPlaceholder || inPoint.isPlaceholder
                candidates.append(MixCandidate(
                    id: id,
                    currentTrackId: currentTrack.id,
                    nextTrackId: nextTrack.id,
                    source: source,
                    evidenceLevel: evidenceLevel,
                    requiresAnalysisUpgrade: candidateRequiresAnalysisUpgrade,
                    currentMixOutSec: currentMixOutSec,
                    nextMixInSec: nextMixInSec,
                    currentBarIndex: currentBarIndex,
                    nextBarIndex: nextBarIndex,
                    phraseAlignment: phraseAlignment,
                    bpmDelta: bpmDelta,
                    tempoSyncRate: tempoSyncRate,
                    energyDelta: energyDelta,
                    style: style,
                    score: score,
                    confidence: score,
                    reason: "\(buildReason(phraseAlignment: phraseAlignment, bpmDelta: bpmDelta, energyDelta: energyDelta, currentBarIndex: currentBarIndex, nextBarIndex: nextBarIndex)); \(source == .tailFallback ? "tail fallback only" : "\(outPoint.reason) -> \(inPoint.reason)")"
                ))
            }
        }

        var seenIds = Set<String>()
        let deduped = candidates
            .filter { candidate in
                if seenIds.contains(candidate.id) {
                    return false
                }
                seenIds.insert(candidate.id)
                return true
            }
            .sorted { $0.score > $1.score }
            .prefix(maxCandidates)
        let recommended = deduped.first { $0.source != .tailFallback && !$0.requiresAnalysisUpgrade }

        return MixPairContext(
            currentTrackId: currentTrack.id,
            nextTrackId: nextTrack.id,
            candidates: Array(deduped),
            recommendedCandidateId: recommended?.id,
            readiness: readiness
        )
    }

    private static func buildPlannerAnalysisTrackSummary(
        track: Track,
        analysis: TrackAnalysis?
    ) -> PlannerAnalysisTrackSummary? {
        guard let analysis else {
            return nil
        }
        let durationSec = max(0, track.durationSec)
        let transientCount = analysis.transientMarkers.count
        let strongestBoundaries = analysis.phraseMarkers
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .map {
                PlannerPhraseBoundarySummary(
                    index: $0.index,
                    startSec: rounded($0.startSec, digits: 2),
                    bars: $0.bars,
                    confidence: rounded(clamped($0.confidence, min: 0, max: 1))
                )
            }
        let beatGridQuality = clamped(analysis.analysisQuality.beatGrid, min: 0, max: 1)
        let transientQuality = clamped(analysis.analysisQuality.transientMarkers, min: 0, max: 1)
        let beatScore = rounded(clamped(beatGridQuality * 0.66 + transientQuality * 0.22 + analysis.bpmConfidence * 0.12, min: 0, max: 1))
        let beatLabel = beatScore >= 0.72 ? "stable" : beatScore >= 0.48 ? "usable" : "weak"

        return PlannerAnalysisTrackSummary(
            trackId: analysis.trackId,
            source: analysis.source,
            plannerReady: hasPlannerReadyTrackAnalysis(analysis),
            bpm: analysis.bpm,
            bpmConfidence: rounded(clamped(analysis.bpmConfidence, min: 0, max: 1)),
            analysisConfidence: rounded(clamped(analysis.analysisConfidence, min: 0, max: 1)),
            analysisQuality: AnalysisQuality(
                waveformDetail: rounded(clamped(analysis.analysisQuality.waveformDetail, min: 0, max: 1)),
                spectralBands: rounded(clamped(analysis.analysisQuality.spectralBands, min: 0, max: 1)),
                transientMarkers: rounded(clamped(analysis.analysisQuality.transientMarkers, min: 0, max: 1)),
                beatGrid: rounded(beatGridQuality),
                harmonicKey: rounded(clamped(analysis.analysisQuality.harmonicKey, min: 0, max: 1))
            ),
            analysisWarnings: analysis.analysisWarnings,
            cues: PlannerCueGroupSummary(
                intro: pickBestCue(analysis: analysis, types: [.intro]),
                firstDownbeat: pickBestCue(analysis: analysis, types: [.firstDownbeat]),
                outro: pickBestCue(analysis: analysis, types: [.outro])
            ),
            energyTrend: buildEnergyTrend(analysis.energyProfile),
            beatStability: PlannerBeatStabilitySummary(
                score: beatScore,
                label: beatLabel,
                beatGridQuality: rounded(beatGridQuality),
                transientQuality: rounded(transientQuality)
            ),
            transients: PlannerTransientSummary(
                count: transientCount,
                strongCount: analysis.transientMarkers.filter { $0.strength >= 0.65 }.count,
                densityPerSec: durationSec > 0 ? rounded(Double(transientCount) / durationSec) : 0
            ),
            phrases: PlannerPhraseSummary(
                barCount: analysis.barGrid.count,
                phraseCount: analysis.phraseMarkers.count,
                strongestBoundaries: Array(strongestBoundaries)
            ),
            harmonic: buildHarmonicSummary(analysis: analysis),
            loudness: buildLoudnessSummary(analysis: analysis),
            mixWindows: buildMixWindows(analysis: analysis, durationSec: durationSec)
        )
    }

    private static func hasPlannerReadyTrackAnalysis(_ analysis: TrackAnalysis?) -> Bool {
        guard let analysis else {
            return false
        }
        return !analysis.waveformDetail.isEmpty &&
            !analysis.energyProfile.isEmpty &&
            !analysis.barGrid.isEmpty &&
            analysis.analysisQuality.waveformDetail >= 0.2 &&
            analysis.analysisQuality.beatGrid >= 0.35 &&
            analysis.bpmConfidence >= 0.45 &&
            !analysis.analysisWarnings.contains(.analysisUpgradeAvailable) &&
            !analysis.analysisWarnings.contains(.bpmLowConfidence) &&
            !analysis.analysisWarnings.contains(.flatEnergy)
    }

    private static func hasPendingAnalysisUpgrade(_ analysis: TrackAnalysis?) -> Bool {
        guard let analysis else {
            return true
        }
        return !hasPlannerReadyTrackAnalysis(analysis)
    }

    private static func buildAnalysisOutPoints(analysis: TrackAnalysis?, durationSec: Double) -> [CandidatePoint] {
        guard hasPlannerReadyTrackAnalysis(analysis), let analysis, durationSec > 0 else {
            return []
        }
        let phrasePoints = analysis.phraseMarkers
            .filter { $0.startSec >= durationSec * 0.45 && $0.startSec <= durationSec * 0.92 }
            .suffix(4)
            .map {
                CandidatePoint(
                    timeSec: $0.startSec,
                    source: .analysis,
                    evidenceLevel: $0.confidence >= 0.65 ? .strong : .partial,
                    confidence: $0.confidence,
                    reason: "phrase marker \($0.index + 1)"
                )
            }
        let transientPoints = analysis.transientMarkers
            .filter { $0.timeSec >= durationSec * 0.45 && $0.timeSec <= durationSec * 0.9 && $0.strength >= 0.55 }
            .suffix(3)
            .map {
                CandidatePoint(
                    timeSec: $0.timeSec,
                    source: .analysis,
                    evidenceLevel: $0.strength >= 0.75 ? .strong : .partial,
                    confidence: $0.strength,
                    reason: "transient \($0.index + 1)"
                )
            }
        return dedupePoints(Array(phrasePoints) + Array(transientPoints))
    }

    private static func buildAnalysisInPoints(analysis: TrackAnalysis?, durationSec: Double) -> [CandidatePoint] {
        guard hasPlannerReadyTrackAnalysis(analysis), let analysis, durationSec > 0 else {
            return []
        }
        let limit = min(48, durationSec * 0.35)
        let phrasePoints = analysis.phraseMarkers
            .filter { $0.startSec <= limit }
            .prefix(4)
            .map {
                CandidatePoint(
                    timeSec: $0.startSec,
                    source: .analysis,
                    evidenceLevel: $0.confidence >= 0.65 ? .strong : .partial,
                    confidence: $0.confidence,
                    reason: "phrase marker \($0.index + 1)"
                )
            }
        let transientPoints = analysis.transientMarkers
            .filter { $0.timeSec <= limit && $0.strength >= 0.55 }
            .prefix(3)
            .map {
                CandidatePoint(
                    timeSec: $0.timeSec,
                    source: .analysis,
                    evidenceLevel: $0.strength >= 0.75 ? .strong : .partial,
                    confidence: $0.strength,
                    reason: "transient \($0.index + 1)"
                )
            }
        return dedupePoints(Array(phrasePoints) + Array(transientPoints))
    }

    private static func buildCueOutPoints(analysis: TrackAnalysis?) -> [CandidatePoint] {
        var points = analysis?.cueCandidates
            .filter { $0.type == .outro || $0.type == .lowEnergyBreak }
            .map {
                CandidatePoint(
                    timeSec: $0.startSec,
                    source: .cue,
                    evidenceLevel: $0.confidence >= 0.65 ? .strong : .partial,
                    confidence: $0.confidence,
                    reason: cueReason($0),
                    isPlaceholder: isPlaceholderCue($0)
                )
            } ?? []
        if let outroCueSec = analysis?.outroCueSec {
            points.append(CandidatePoint(
                timeSec: outroCueSec,
                source: .cue,
                evidenceLevel: .partial,
                confidence: 0.48,
                reason: "outro cue (heuristic placeholder)",
                isPlaceholder: true
            ))
        }
        return dedupePoints(points)
    }

    private static func buildCueInPoints(analysis: TrackAnalysis?) -> [CandidatePoint] {
        var points = analysis?.cueCandidates
            .filter { $0.type == .intro || $0.type == .firstDownbeat }
            .map {
                CandidatePoint(
                    timeSec: $0.startSec,
                    source: .cue,
                    evidenceLevel: $0.confidence >= 0.65 ? .strong : .partial,
                    confidence: $0.confidence,
                    reason: cueReason($0),
                    isPlaceholder: isPlaceholderCue($0)
                )
            } ?? []
        if let introCueSec = analysis?.introCueSec {
            points.append(CandidatePoint(
                timeSec: introCueSec,
                source: .cue,
                evidenceLevel: .partial,
                confidence: 0.48,
                reason: "intro cue (heuristic placeholder)",
                isPlaceholder: true
            ))
        }
        let deduped = dedupePoints(points)
        return deduped.isEmpty
            ? [CandidatePoint(timeSec: 0, source: .cue, evidenceLevel: .partial, confidence: 0.36, reason: "track start (heuristic placeholder)", isPlaceholder: true)]
            : deduped
    }

    private static func buildMixWindows(
        analysis: TrackAnalysis,
        durationSec: Double
    ) -> PlannerMixWindowGroupSummary {
        guard durationSec > 0 else {
            return PlannerMixWindowGroupSummary(mixIn: [], mixOut: [])
        }

        let spanSec = mixWindowSpan(analysis: analysis, durationSec: durationSec)
        let earlyLimit = min(48, durationSec * 0.35)

        var mixIn = analysis.cueCandidates
            .filter { $0.type == .intro || $0.type == .firstDownbeat }
            .map { cueWindow(cue: $0, durationSec: durationSec, spanSec: spanSec, source: .cue) }
        if mixIn.isEmpty, let introCueSec = analysis.introCueSec {
            mixIn.append(window(
                kind: .intro,
                source: .cue,
                startSec: introCueSec,
                durationSec: durationSec,
                spanSec: spanSec,
                confidence: 0.42,
                label: "Intro"
            ))
        }
        if mixIn.isEmpty {
            mixIn.append(window(
                kind: .trackStart,
                source: .cue,
                startSec: 0,
                durationSec: durationSec,
                spanSec: spanSec,
                confidence: 0.34,
                label: "Track start"
            ))
        }
        mixIn += analysis.phraseMarkers
            .filter { $0.startSec <= earlyLimit }
            .prefix(4)
            .map {
                window(
                    kind: .phrase,
                    source: .analysis,
                    startSec: $0.startSec,
                    durationSec: durationSec,
                    spanSec: spanSec,
                    confidence: $0.confidence,
                    label: "Phrase marker \($0.index + 1)"
                )
            }
        mixIn += analysis.transientMarkers
            .filter { $0.timeSec <= earlyLimit && $0.strength >= 0.55 }
            .prefix(3)
            .map {
                window(
                    kind: .transient,
                    source: .analysis,
                    startSec: $0.timeSec,
                    durationSec: durationSec,
                    spanSec: min(spanSec, 6),
                    confidence: $0.strength,
                    label: "Transient \($0.index + 1)"
                )
            }

        var mixOut = analysis.cueCandidates
            .filter { $0.type == .outro || $0.type == .lowEnergyBreak }
            .map { cueWindow(cue: $0, durationSec: durationSec, spanSec: spanSec, source: .cue) }
        if let outroCueSec = analysis.outroCueSec {
            mixOut.append(window(
                kind: .outro,
                source: .cue,
                startSec: outroCueSec,
                durationSec: durationSec,
                spanSec: spanSec,
                confidence: 0.42,
                label: "Outro mix-out"
            ))
        }
        mixOut += analysis.phraseMarkers
            .filter { $0.startSec >= durationSec * 0.45 && $0.startSec <= durationSec * 0.92 }
            .suffix(4)
            .map {
                window(
                    kind: .phrase,
                    source: .analysis,
                    startSec: $0.startSec,
                    durationSec: durationSec,
                    spanSec: spanSec,
                    confidence: $0.confidence,
                    label: "Phrase marker \($0.index + 1)"
                )
            }
        mixOut += analysis.transientMarkers
            .filter { $0.timeSec >= durationSec * 0.45 && $0.timeSec <= durationSec * 0.9 && $0.strength >= 0.55 }
            .suffix(3)
            .map {
                window(
                    kind: .transient,
                    source: .analysis,
                    startSec: $0.timeSec,
                    durationSec: durationSec,
                    spanSec: min(spanSec, 6),
                    confidence: $0.strength,
                    label: "Transient \($0.index + 1)"
                )
            }

        return PlannerMixWindowGroupSummary(
            mixIn: dedupeWindows(mixIn).prefix(5).map { $0 },
            mixOut: dedupeWindows(mixOut).prefix(5).map { $0 }
        )
    }

    private static func cueWindow(
        cue: CueCandidate,
        durationSec: Double,
        spanSec: Double,
        source: MixCandidateSource
    ) -> PlannerMixWindowSummary {
        let kind: PlannerMixWindowKind
        switch cue.type {
        case .intro:
            kind = .intro
        case .firstDownbeat:
            kind = .firstDownbeat
        case .outro:
            kind = .outro
        case .lowEnergyBreak:
            kind = .lowEnergyBreak
        case .highEnergyDrop:
            kind = .highEnergyDrop
        }

        let startSec = clamped(cue.startSec, min: 0, max: durationSec)
        let preferredEnd = cue.endSec > cue.startSec ? cue.endSec : cue.startSec + spanSec
        return PlannerMixWindowSummary(
            kind: kind,
            source: source,
            startSec: rounded(startSec, digits: 2),
            endSec: rounded(clamped(preferredEnd, min: startSec + 0.25, max: min(durationSec, startSec + spanSec)), digits: 2),
            confidence: rounded(clamped(cue.confidence, min: 0, max: 1)),
            label: cue.label
        )
    }

    private static func window(
        kind: PlannerMixWindowKind,
        source: MixCandidateSource,
        startSec: Double,
        durationSec: Double,
        spanSec: Double,
        confidence: Double,
        label: String
    ) -> PlannerMixWindowSummary {
        let safeStart = clamped(startSec, min: 0, max: durationSec)
        return PlannerMixWindowSummary(
            kind: kind,
            source: source,
            startSec: rounded(safeStart, digits: 2),
            endSec: rounded(clamped(safeStart + spanSec, min: safeStart + 0.25, max: durationSec), digits: 2),
            confidence: rounded(clamped(confidence, min: 0, max: 1)),
            label: label
        )
    }

    private static func dedupeWindows(_ windows: [PlannerMixWindowSummary]) -> [PlannerMixWindowSummary] {
        let sorted = windows.sorted {
            if mixWindowSourceRank($0.source) == mixWindowSourceRank($1.source) {
                if $0.confidence != $1.confidence {
                    return $0.confidence > $1.confidence
                }
                return $0.startSec < $1.startSec
            }
            return mixWindowSourceRank($0.source) < mixWindowSourceRank($1.source)
        }
        var result: [PlannerMixWindowSummary] = []
        for candidate in sorted where !result.contains(where: { abs($0.startSec - candidate.startSec) < 0.75 }) {
            result.append(candidate)
        }
        return result
    }

    private static func mixWindowSourceRank(_ source: MixCandidateSource) -> Int {
        switch source {
        case .cue:
            return 0
        case .analysis:
            return 1
        case .tailFallback:
            return 2
        }
    }

    private static func mixWindowSpan(analysis: TrackAnalysis, durationSec: Double) -> Double {
        let barStarts = analysis.barGrid.map(\.startSec)
        let barIntervals = zip(barStarts, barStarts.dropFirst())
            .map { $1 - $0 }
            .filter { $0.isFinite && $0 > 0.5 && $0 < 20 }
        if let averageBar = average(barIntervals) {
            return clamped(averageBar * 2, min: 4, max: 16)
        }
        return clamped(durationSec * 0.05, min: 4, max: 12)
    }

    private static func dedupePoints(_ points: [CandidatePoint]) -> [CandidatePoint] {
        let sorted = points.sorted {
            if sourceRank($0.source) != sourceRank($1.source) {
                return sourceRank($0.source) < sourceRank($1.source)
            }
            if $0.isPlaceholder != $1.isPlaceholder {
                return !$0.isPlaceholder
            }
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return $0.timeSec < $1.timeSec
        }
        var result: [CandidatePoint] = []
        for point in sorted where !result.contains(where: { abs($0.timeSec - point.timeSec) < 0.75 }) {
            result.append(point)
        }
        return result
    }

    private static func sourceRank(_ source: MixCandidateSource) -> Int {
        switch source {
        case .analysis:
            return 0
        case .cue:
            return 1
        case .tailFallback:
            return 2
        }
    }

    private static func nearestBarIndex(analysis: TrackAnalysis?, timeSec: Double) -> Int? {
        guard let first = analysis?.barGrid.first else {
            return nil
        }
        var best = first
        var bestDistance = abs(first.startSec - timeSec)
        for marker in analysis?.barGrid ?? [] {
            let distance = abs(marker.startSec - timeSec)
            if distance < bestDistance {
                best = marker
                bestDistance = distance
            }
        }
        return best.index
    }

    private static func energyAt(analysis: TrackAnalysis?, timeSec: Double, durationSec: Double) -> Double? {
        guard let analysis, !analysis.energyProfile.isEmpty, durationSec > 0 else {
            return nil
        }
        let index = clampedInt(
            Int(floor((timeSec / durationSec) * Double(analysis.energyProfile.count))),
            min: 0,
            max: analysis.energyProfile.count - 1
        )
        return analysis.energyProfile[index]
    }

    private static func resolvePhraseAlignment(currentBarIndex: Int?, nextBarIndex: Int?) -> PhraseAlignment {
        guard let currentBarIndex, let nextBarIndex else {
            return .free
        }
        let currentPhrase = currentBarIndex % 8
        let nextPhrase = nextBarIndex % 8
        if currentPhrase == nextPhrase {
            return .aligned
        }
        return abs(currentPhrase - nextPhrase) <= 1 ? .near : .free
    }

    private static func resolveStyle(phraseAlignment: PhraseAlignment, bpmDelta: Double?, energyDelta: Double?) -> MixStyle {
        if let bpmDelta, bpmDelta > 10 {
            return .hardCut
        }
        if let energyDelta, energyDelta > 0.28, phraseAlignment != .free {
            return .energySwap
        }
        return .smoothBlend
    }

    private static func scoreCandidate(
        source: MixCandidateSource,
        evidenceLevel: MixEvidenceLevel,
        phraseAlignment: PhraseAlignment,
        bpmDelta: Double?,
        energyDelta: Double?,
        outConfidence: Double,
        inConfidence: Double,
        currentAnalysis: TrackAnalysis?,
        nextAnalysis: TrackAnalysis?
    ) -> Double {
        let phraseScore = phraseAlignment == .aligned ? 0.28 : phraseAlignment == .near ? 0.16 : 0.06
        let bpmScore = bpmDelta.map { clamped(1 - $0 / 18, min: 0, max: 1) * 0.24 } ?? 0.08
        let energyScore = energyDelta.map { clamped(1 - abs($0 - 0.12) / 0.5, min: 0, max: 1) * 0.2 } ?? 0.08
        let pointConfidenceScore = ((outConfidence + inConfidence) / 2) * (source == .tailFallback ? 0.06 : 0.16)
        let analysisQualityScore = (currentAnalysis?.analysisConfidence ?? 0.2) * 0.14 + (nextAnalysis?.analysisConfidence ?? 0.2) * 0.14
        let sourceScore = source == .analysis ? 0.12 : source == .cue ? 0.08 : -0.24
        let evidenceScore = evidenceLevel == .strong ? 0.08 : evidenceLevel == .partial ? 0.03 : -0.08
        let maxScore = source == .tailFallback ? 0.42 : source == .cue ? 0.72 : 1
        return clamped(
            phraseScore + bpmScore + energyScore + pointConfidenceScore + analysisQualityScore + sourceScore + evidenceScore,
            min: 0,
            max: maxScore
        )
    }

    private static func buildReason(
        phraseAlignment: PhraseAlignment,
        bpmDelta: Double?,
        energyDelta: Double?,
        currentBarIndex: Int?,
        nextBarIndex: Int?
    ) -> String {
        var parts: [String] = []
        if let currentBarIndex, let nextBarIndex {
            parts.append("bar \(currentBarIndex + 1) -> \(nextBarIndex + 1)")
        }
        parts.append(phraseAlignment == .aligned ? "phrase aligned" : phraseAlignment == .near ? "near phrase boundary" : "free timing")
        if let bpmDelta {
            parts.append("BPM delta \(String(format: "%.1f", bpmDelta))")
        }
        if let energyDelta {
            parts.append(energyDelta >= 0 ? "energy lift \(String(format: "%.2f", energyDelta))" : "energy drop \(String(format: "%.2f", abs(energyDelta)))")
        }
        return parts.joined(separator: "; ")
    }

    private static func buildEnergyTrend(_ energyProfile: [Double]) -> PlannerEnergyTrendSummary {
        guard !energyProfile.isEmpty else {
            return PlannerEnergyTrendSummary(early: nil, mid: nil, late: nil, direction: .unknown)
        }
        let third = max(1, energyProfile.count / 3)
        let early = average(Array(energyProfile.prefix(third)))
        let mid = average(Array(energyProfile.dropFirst(third).prefix(third)))
        let late = average(Array(energyProfile.dropFirst(min(energyProfile.count, third * 2))))
        let delta = (late ?? 0) - (early ?? 0)
        let direction: PlannerEnergyTrendDirection = abs(delta) < 0.12 ? .flat : delta > 0 ? .rising : .falling
        return PlannerEnergyTrendSummary(
            early: early.map { rounded(clamped($0, min: 0, max: 1)) },
            mid: mid.map { rounded(clamped($0, min: 0, max: 1)) },
            late: late.map { rounded(clamped($0, min: 0, max: 1)) },
            direction: direction
        )
    }

    private static func buildHarmonicSummary(analysis: TrackAnalysis) -> PlannerHarmonicSummary {
        guard let key = analysis.musicalKey else {
            return PlannerHarmonicSummary(key: nil, mode: nil, confidence: 0, evidence: .fallback)
        }
        let confidence = rounded(clamped(key.confidence, min: 0, max: 1))
        let evidence: MixEvidenceLevel = confidence >= 0.62 ? .strong : confidence >= 0.35 ? .partial : .fallback
        return PlannerHarmonicSummary(
            key: key.tonic,
            mode: key.mode,
            confidence: confidence,
            evidence: evidence
        )
    }

    private static func buildLoudnessSummary(analysis: TrackAnalysis) -> PlannerLoudnessSummary {
        guard let loudness = analysis.loudness else {
            return PlannerLoudnessSummary(
                integratedRMSDb: nil,
                peakDb: nil,
                headroomDb: nil,
                dynamicRangeDb: nil,
                confidence: 0,
                evidence: .fallback
            )
        }
        let confidence = rounded(clamped(loudness.confidence, min: 0, max: 1))
        let evidence: MixEvidenceLevel = confidence >= 0.68 ? .strong : confidence >= 0.45 ? .partial : .fallback
        return PlannerLoudnessSummary(
            integratedRMSDb: rounded(loudness.integratedRMSDb, digits: 2),
            peakDb: rounded(loudness.peakDb, digits: 2),
            headroomDb: rounded(loudness.headroomDb, digits: 2),
            dynamicRangeDb: rounded(loudness.dynamicRangeDb, digits: 2),
            confidence: confidence,
            evidence: evidence
        )
    }

    private static func pickBestCue(analysis: TrackAnalysis, types: [CueCandidateType]) -> PlannerCueSummary? {
        if let cue = analysis.cueCandidates
            .filter({ types.contains($0.type) })
            .sorted(by: {
                if isPlaceholderCue($0) != isPlaceholderCue($1) {
                    return !isPlaceholderCue($0)
                }
                return $0.confidence > $1.confidence
            })
            .first {
            return cueToSummary(cue)
        }
        if types.contains(.intro), let introCueSec = analysis.introCueSec {
            return PlannerCueSummary(type: .intro, startSec: rounded(introCueSec, digits: 2), confidence: 0.42, label: "Intro", origin: .heuristicPlaceholder)
        }
        if types.contains(.outro), let outroCueSec = analysis.outroCueSec {
            return PlannerCueSummary(type: .outro, startSec: rounded(outroCueSec, digits: 2), confidence: 0.42, label: "Outro mix-out", origin: .heuristicPlaceholder)
        }
        return nil
    }

    private static func cueToSummary(_ cue: CueCandidate) -> PlannerCueSummary {
        PlannerCueSummary(
            type: cue.type,
            startSec: rounded(cue.startSec, digits: 2),
            confidence: rounded(clamped(cue.confidence, min: 0, max: 1)),
            label: cue.label,
            origin: cue.origin
        )
    }

    private static func isPlaceholderCue(_ cue: CueCandidate) -> Bool {
        cue.origin == .heuristicPlaceholder
    }

    private static func cueReason(_ cue: CueCandidate) -> String {
        isPlaceholderCue(cue) ? "\(cue.label) (heuristic placeholder)" : cue.label
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct CandidatePoint {
    var timeSec: Double
    var source: MixCandidateSource
    var evidenceLevel: MixEvidenceLevel
    var confidence: Double
    var reason: String
    var isPlaceholder: Bool = false
}

private func rounded(_ value: Double, digits: Int = 3) -> Double {
    let multiplier = pow(10, Double(digits))
    return (value * multiplier).rounded() / multiplier
}

private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    Swift.min(maxValue, Swift.max(minValue, value.isFinite ? value : minValue))
}

private func clampedInt(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
    Swift.min(maxValue, Swift.max(minValue, value))
}
