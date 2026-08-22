import Foundation
import BeatDropperDomain

/// Result of one planner attempt, including the compatibility fallback evidence
/// needed by review and acceptance workflows.
public struct NativeMixPlannerResult: Sendable {
    public var plan: MixPlan?
    public var source: String
    public var reason: String?
    public var request: PlannerRequest
    public var response: PlannerResponse?
    public var shadowFallbackPlan: MixPlan?
    public var shadowFallbackReason: String?

    public init(
        plan: MixPlan?,
        source: String,
        reason: String?,
        request: PlannerRequest,
        response: PlannerResponse?,
        shadowFallbackPlan: MixPlan?,
        shadowFallbackReason: String?
    ) {
        self.plan = plan
        self.source = source
        self.reason = reason
        self.request = request
        self.response = response
        self.shadowFallbackPlan = shadowFallbackPlan
        self.shadowFallbackReason = shadowFallbackReason
    }
}
