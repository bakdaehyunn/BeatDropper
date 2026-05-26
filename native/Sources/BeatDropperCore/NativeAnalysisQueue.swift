import Foundation

public struct NativeAnalysisQueueSnapshot: Equatable, Sendable {
    public var pendingCount: Int
    public var runningCount: Int
    public var activeCount: Int

    public init(pendingCount: Int, runningCount: Int) {
        self.pendingCount = max(0, pendingCount)
        self.runningCount = max(0, runningCount)
        self.activeCount = self.pendingCount + self.runningCount
    }
}

public struct NativeAnalysisQueueState: Equatable, Sendable {
    private var pendingIds: [String] = []
    private var pendingIdSet: Set<String> = []
    private var runningIds: Set<String> = []

    public init() {}

    public var snapshot: NativeAnalysisQueueSnapshot {
        NativeAnalysisQueueSnapshot(
            pendingCount: pendingIds.count,
            runningCount: runningIds.count
        )
    }

    public var activeIds: Set<String> {
        pendingIdSet.union(runningIds)
    }

    public func isPending(_ id: String) -> Bool {
        pendingIdSet.contains(id)
    }

    public func isRunning(_ id: String) -> Bool {
        runningIds.contains(id)
    }

    public func contains(_ id: String) -> Bool {
        isPending(id) || isRunning(id)
    }

    public mutating func enqueue(_ ids: [String]) {
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !pendingIdSet.contains(trimmed),
                  !runningIds.contains(trimmed)
            else {
                continue
            }
            pendingIds.append(trimmed)
            pendingIdSet.insert(trimmed)
        }
    }

    public mutating func startAvailable(maxConcurrent: Int) -> [String] {
        let limit = max(1, maxConcurrent)
        let openSlots = max(0, limit - runningIds.count)
        guard openSlots > 0, !pendingIds.isEmpty else {
            return []
        }

        let started = Array(pendingIds.prefix(openSlots))
        pendingIds.removeFirst(started.count)
        for id in started {
            pendingIdSet.remove(id)
            runningIds.insert(id)
        }
        return started
    }

    public mutating func finish(_ id: String) {
        runningIds.remove(id)
        if pendingIdSet.remove(id) != nil {
            pendingIds.removeAll { $0 == id }
        }
    }

    public mutating func clear() {
        pendingIds.removeAll()
        pendingIdSet.removeAll()
        runningIds.removeAll()
    }

    public static func recommendedConcurrency(activeProcessorCount: Int) -> Int {
        let processorCount = max(1, activeProcessorCount)
        return min(4, max(1, processorCount / 2))
    }
}
