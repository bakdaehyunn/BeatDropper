import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Testing

struct NativeAnalysisQueueTests {
    @Test func enqueuesUniqueTracksAndStartsWithinConcurrencyLimit() {
        var queue = NativeAnalysisQueueState()
        queue.enqueue(["a", "b", "a", "", " c "])

        #expect(queue.snapshot == NativeAnalysisQueueSnapshot(pendingCount: 3, runningCount: 0))
        #expect(queue.activeIds == Set(["a", "b", "c"]))

        let firstBatch = queue.startAvailable(maxConcurrent: 2)

        #expect(firstBatch == ["a", "b"])
        #expect(queue.isRunning("a"))
        #expect(queue.isRunning("b"))
        #expect(queue.isPending("c"))
        #expect(queue.snapshot == NativeAnalysisQueueSnapshot(pendingCount: 1, runningCount: 2))
    }

    @Test func finishingRunningTrackAllowsNextPendingTrackToStart() {
        var queue = NativeAnalysisQueueState()
        queue.enqueue(["a", "b", "c"])
        #expect(queue.startAvailable(maxConcurrent: 2) == ["a", "b"])

        queue.finish("a")
        #expect(queue.snapshot == NativeAnalysisQueueSnapshot(pendingCount: 1, runningCount: 1))
        #expect(queue.startAvailable(maxConcurrent: 2) == ["c"])
        #expect(queue.snapshot == NativeAnalysisQueueSnapshot(pendingCount: 0, runningCount: 2))
    }

    @Test func recommendedConcurrencyUsesBoundedCpuParallelism() {
        #expect(NativeAnalysisQueueState.recommendedConcurrency(activeProcessorCount: 1) == 1)
        #expect(NativeAnalysisQueueState.recommendedConcurrency(activeProcessorCount: 4) == 2)
        #expect(NativeAnalysisQueueState.recommendedConcurrency(activeProcessorCount: 12) == 4)
    }
}
