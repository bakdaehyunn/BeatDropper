import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct PlannerProcessOutputTests {
    @Test func decodesValidStdoutEvenWhenStderrHasWarnings() throws {
        let response = PlannerResponse(
            mixPlan: MixPlan(
                transitionStartSec: 32,
                transitionEndSec: 40,
                nextTrackStartOffsetSec: 4,
                style: .smoothBlend,
                confidence: 0.72,
                reasoningSummary: "Valid plan",
                tempoSync: MixTempoSyncPlan(enabled: false, targetRate: nil),
                candidateId: "candidate-1",
                currentBarIndex: 16,
                nextBarIndex: 2,
                phraseAlignment: .aligned,
                energyStrategy: .maintain,
                evidence: ["stdout valid", "stderr warning ignored"]
            ),
            error: nil
        )
        let data = try JSONEncoder().encode(response)

        let decoded = try PlannerProcessOutputParser.decodePlannerResponse(
            stdoutData: data,
            stderrText: "warning: model warmed up slowly",
            terminationStatus: 0
        )

        #expect(decoded.mixPlan?.candidateId == "candidate-1")
        #expect(decoded.error == nil)
    }

    @Test func nonZeroExitIncludesStderrInReason() throws {
        #expect(throws: PlannerProcessOutputError.self) {
            _ = try PlannerProcessOutputParser.decodePlannerResponse(
                stdoutData: Data(),
                stderrText: "codex unavailable",
                terminationStatus: 7
            )
        }
    }

    @Test func invalidStdoutIncludesStderrAndStdoutPreview() throws {
        do {
            _ = try PlannerProcessOutputParser.decodePlannerResponse(
                stdoutData: Data("not json".utf8),
                stderrText: "diagnostic",
                terminationStatus: 0
            )
            Issue.record("Expected invalid JSON error")
        } catch let error as PlannerProcessOutputError {
            #expect(error.errorDescription?.contains("diagnostic") == true)
            #expect(error.errorDescription?.contains("not json") == true)
        }
    }
}
