import Foundation
import BeatDropperDomain

public enum MixPlanScheduler {
    public static func secondsUntilTransition(plan: MixPlan, elapsedSec: Double) -> Double {
        max(0, plan.transitionStartSec - (elapsedSec.isFinite ? elapsedSec : 0))
    }

    public static func shouldStartTransition(
        plan: MixPlan,
        elapsedSec: Double,
        toleranceSec: Double = 0.2
    ) -> Bool {
        plan.transitionStartSec - (elapsedSec.isFinite ? elapsedSec : 0) <= max(0, toleranceSec)
    }
}
