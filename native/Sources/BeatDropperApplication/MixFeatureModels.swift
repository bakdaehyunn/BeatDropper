import BeatDropperDomain
import BeatDropperDSP
import BeatDropperReview
import Foundation

public struct PlannedMixPair: Equatable, Sendable {
    public var currentTrackId: String
    public var nextTrackId: String

    public init(currentTrackId: String, nextTrackId: String) {
        self.currentTrackId = currentTrackId
        self.nextTrackId = nextTrackId
    }
}

public struct PlannedMixReview: Equatable, Sendable {
    public var pair: PlannedMixPair
    public var source: String
    public var fallbackReason: String?
    public var selectionReason: String?
    public var renderedQuality: RenderedTransitionQualityReport
    public var shadowFallbackComparison: PlannedMixReviewPlanComparison?

    public init(
        pair: PlannedMixPair,
        source: String,
        fallbackReason: String?,
        selectionReason: String?,
        renderedQuality: RenderedTransitionQualityReport,
        shadowFallbackComparison: PlannedMixReviewPlanComparison?
    ) {
        self.pair = pair
        self.source = source
        self.fallbackReason = fallbackReason
        self.selectionReason = selectionReason
        self.renderedQuality = renderedQuality
        self.shadowFallbackComparison = shadowFallbackComparison
    }
}

public struct AcceptedMixPlan: Equatable, Sendable {
    public var plan: MixPlan
    public var review: PlannedMixReview

    public init(plan: MixPlan, review: PlannedMixReview) {
        self.plan = plan
        self.review = review
    }
}

public struct PlannedMixReviewPlanComparison: Equatable, Sendable {
    public var source: String
    public var reason: String?
    public var transitionStartSec: Double
    public var transitionEndSec: Double
    public var nextTrackStartOffsetSec: Double
    public var style: MixStyle
    public var confidence: Double
    public var candidateId: String?
    public var renderedQuality: RenderedTransitionQualityReport

    public init(
        source: String,
        reason: String?,
        transitionStartSec: Double,
        transitionEndSec: Double,
        nextTrackStartOffsetSec: Double,
        style: MixStyle,
        confidence: Double,
        candidateId: String?,
        renderedQuality: RenderedTransitionQualityReport
    ) {
        self.source = source
        self.reason = reason
        self.transitionStartSec = transitionStartSec
        self.transitionEndSec = transitionEndSec
        self.nextTrackStartOffsetSec = nextTrackStartOffsetSec
        self.style = style
        self.confidence = confidence
        self.candidateId = candidateId
        self.renderedQuality = renderedQuality
    }
}

public struct PlannedMixReviewEvent: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var pair: PlannedMixPair
    public var source: String
    public var fallbackReason: String?
    public var selectionReason: String?
    public var transitionStartSec: Double
    public var transitionEndSec: Double
    public var nextTrackStartOffsetSec: Double
    public var style: MixStyle
    public var confidence: Double
    public var candidateId: String?
    public var renderedQuality: RenderedTransitionQualityReport
    public var shadowFallbackComparison: PlannedMixReviewPlanComparison?

    public init(
        id: UUID,
        createdAt: Date,
        pair: PlannedMixPair,
        source: String,
        fallbackReason: String?,
        selectionReason: String?,
        transitionStartSec: Double,
        transitionEndSec: Double,
        nextTrackStartOffsetSec: Double,
        style: MixStyle,
        confidence: Double,
        candidateId: String?,
        renderedQuality: RenderedTransitionQualityReport,
        shadowFallbackComparison: PlannedMixReviewPlanComparison?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.pair = pair
        self.source = source
        self.fallbackReason = fallbackReason
        self.selectionReason = selectionReason
        self.transitionStartSec = transitionStartSec
        self.transitionEndSec = transitionEndSec
        self.nextTrackStartOffsetSec = nextTrackStartOffsetSec
        self.style = style
        self.confidence = confidence
        self.candidateId = candidateId
        self.renderedQuality = renderedQuality
        self.shadowFallbackComparison = shadowFallbackComparison
    }
}

public struct ImportedMixReviewArtifact: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var importedAt: Date
    public var fileName: String
    public var format: String
    public var content: String
    public var reviewCount: Int
    public var schemaVersion: Int?
    public var trackPairs: [MixReviewArtifactTrackPair]
    public var pairDetails: [MixReviewArtifactPairDetail]
    public var reviewAnnotation: String

    public init(
        id: UUID,
        importedAt: Date,
        fileName: String,
        format: String,
        content: String,
        reviewCount: Int,
        schemaVersion: Int?,
        trackPairs: [MixReviewArtifactTrackPair] = [],
        pairDetails: [MixReviewArtifactPairDetail] = [],
        reviewAnnotation: String = ""
    ) {
        self.id = id
        self.importedAt = importedAt
        self.fileName = fileName
        self.format = format
        self.content = content
        self.reviewCount = reviewCount
        self.schemaVersion = schemaVersion
        self.trackPairs = trackPairs
        self.pairDetails = pairDetails
        self.reviewAnnotation = reviewAnnotation
    }

    public init(persisted: PersistedMixReviewArtifact) {
        let extractedPairs = MixReviewArtifactPairExtractor.trackPairs(content: persisted.content)
        let pairDetails = MixReviewArtifactPairDetailExtractor.pairDetails(content: persisted.content)
        self.id = UUID(uuidString: persisted.id) ?? UUID()
        self.importedAt = ISO8601DateFormatter().date(from: persisted.importedAt) ?? Date()
        self.fileName = persisted.fileName
        self.format = persisted.format
        self.content = persisted.content
        self.reviewCount = persisted.reviewCount
        self.schemaVersion = persisted.schemaVersion
        self.trackPairs = persisted.trackPairs.isEmpty ? extractedPairs : persisted.trackPairs
        self.pairDetails = pairDetails
        self.reviewAnnotation = persisted.reviewAnnotation
    }

    public var persisted: PersistedMixReviewArtifact {
        PersistedMixReviewArtifact(
            id: id.uuidString,
            importedAt: ISO8601DateFormatter().string(from: importedAt),
            fileName: fileName,
            format: format,
            content: content,
            reviewCount: reviewCount,
            schemaVersion: schemaVersion,
            trackPairs: trackPairs,
            reviewAnnotation: reviewAnnotation
        )
    }

    public func matches(pair: PlannedMixPair) -> Bool {
        MixReviewArtifactPairFilter.matches(
            trackPairs: trackPairs,
            currentTrackId: pair.currentTrackId,
            nextTrackId: pair.nextTrackId
        )
    }

    public func matches(searchText: String) -> Bool {
        MixReviewArtifactSearch.matches(
            fileName: fileName,
            format: format,
            reviewCount: reviewCount,
            trackPairs: trackPairs,
            content: content,
            annotation: reviewAnnotation,
            query: searchText
        )
    }
}

public struct ImportedMixReviewArtifactComparison: Identifiable, Equatable, Sendable {
    public var pair: PlannedMixPair
    public var leftArtifact: ImportedMixReviewArtifact
    public var rightArtifact: ImportedMixReviewArtifact
    public var pairComparison: MixReviewArtifactPairComparison

    public init(
        pair: PlannedMixPair,
        leftArtifact: ImportedMixReviewArtifact,
        rightArtifact: ImportedMixReviewArtifact,
        pairComparison: MixReviewArtifactPairComparison
    ) {
        self.pair = pair
        self.leftArtifact = leftArtifact
        self.rightArtifact = rightArtifact
        self.pairComparison = pairComparison
    }

    public var id: String {
        [pair.currentTrackId, pair.nextTrackId, leftArtifact.id.uuidString, rightArtifact.id.uuidString]
            .joined(separator: "|")
    }
}
