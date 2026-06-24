import BeatDropperCore
import Foundation

struct NativeMixPlannerResult: Sendable {
    var plan: MixPlan?
    var source: String
    var reason: String?
    var request: PlannerRequest
    var response: PlannerResponse?
    var shadowFallbackPlan: MixPlan?
    var shadowFallbackReason: String?
}

struct NativeMixPlannerBridge: Sendable {
    var timeoutSec: TimeInterval = 45

    func requestMixPlan(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext
    ) async -> NativeMixPlannerResult {
        do {
            let response = try await executePlanner(request: request)
            guard let mixPlan = response.mixPlan else {
                return fallbackResult(
                    request: request,
                    validationContext: validationContext,
                    response: response,
                    reason: response.error ?? "planner_returned_no_plan"
                )
            }

            let validated = MixPlanValidator.validateAndClamp(mixPlan, context: validationContext)
            guard let plan = validated.plan else {
                return fallbackResult(
                    request: request,
                    validationContext: validationContext,
                    response: response,
                    reason: validated.reason ?? "mix_plan_invalid"
                )
            }

            let shadowFallbackReason = "shadow_fallback_comparison"
            let shadowFallbackPlan = NativeFallbackMixPlanner.buildPlan(
                request: request,
                validationContext: validationContext,
                failureReason: shadowFallbackReason
            )
            return NativeMixPlannerResult(
                plan: plan,
                source: "cli",
                reason: nil,
                request: request,
                response: response,
                shadowFallbackPlan: shadowFallbackPlan,
                shadowFallbackReason: shadowFallbackPlan == nil ? nil : shadowFallbackReason
            )
        } catch {
            return fallbackResult(
                request: request,
                validationContext: validationContext,
                response: nil,
                reason: error.localizedDescription
            )
        }
    }

    private func fallbackResult(
        request: PlannerRequest,
        validationContext: MixPlanValidationContext,
        response: PlannerResponse?,
        reason: String
    ) -> NativeMixPlannerResult {
        let plan = NativeFallbackMixPlanner.buildPlan(
            request: request,
            validationContext: validationContext,
            failureReason: reason
        )
        return NativeMixPlannerResult(
            plan: plan,
            source: plan == nil ? "fallback-unavailable" : "local-fallback",
            reason: reason,
            request: request,
            response: response,
            shadowFallbackPlan: nil,
            shadowFallbackReason: nil
        )
    }

    private func executePlanner(request: PlannerRequest) async throws -> PlannerResponse {
        try await Task.detached(priority: .utility) {
            let scriptURL = try resolvePlannerScriptURL()
            let nodeInvocation = try resolveNodeInvocation(scriptURL: scriptURL)
            let requestData = try JSONEncoder().encode(request)
            let process = Process()
            process.executableURL = nodeInvocation.executableURL
            process.arguments = nodeInvocation.arguments
            process.currentDirectoryURL = scriptURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            process.environment = plannerProcessEnvironment()

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            stdin.fileHandleForWriting.write(requestData)
            try stdin.fileHandleForWriting.close()

            let deadline = Date().addingTimeInterval(timeoutSec)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                process.terminate()
                throw NativeMixPlannerError.timeout
            }

            process.waitUntilExit()
            let stderrText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()

            return try PlannerProcessOutputParser.decodePlannerResponse(
                stdoutData: stdoutData,
                stderrText: stderrText,
                terminationStatus: process.terminationStatus
            )
        }.value
    }
}

private func plannerProcessEnvironment(
    base: [String: String] = ProcessInfo.processInfo.environment
) -> [String: String] {
    var environment = base
    let existingPath = environment["PATH"] ?? ""
    let existingSegments = existingPath
        .split(separator: ":")
        .map(String.init)
    let pathSegments = uniquePathSegments(
        NativePlannerRuntimePath.defaultSearchPaths + existingSegments
    )
    environment["PATH"] = pathSegments.joined(separator: ":")
    return environment
}

private func uniquePathSegments(_ segments: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for segment in segments {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !seen.contains(trimmed) else {
            continue
        }
        seen.insert(trimmed)
        result.append(trimmed)
    }
    return result
}

private func resolvePlannerScriptURL() throws -> URL {
    let fileManager = FileManager.default
    let resourceURL = Bundle.main.resourceURL
    let resourceCandidates = [
        resourceURL?.appendingPathComponent("Scripts/codex-mix-planner.cjs"),
        resourceURL?.appendingPathComponent("codex-mix-planner.cjs")
    ].compactMap { $0 }

    for candidate in resourceCandidates where fileManager.fileExists(atPath: candidate.path) {
        return candidate
    }

    let bundleURL = Bundle.main.bundleURL
    let repoCandidate = bundleURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts/codex-mix-planner.cjs")
    if fileManager.fileExists(atPath: repoCandidate.path) {
        return repoCandidate
    }

    let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    let currentCandidates = [
        currentDirectory.appendingPathComponent("scripts/codex-mix-planner.cjs"),
        currentDirectory.deletingLastPathComponent().appendingPathComponent("scripts/codex-mix-planner.cjs")
    ]
    for candidate in currentCandidates where fileManager.fileExists(atPath: candidate.path) {
        return candidate
    }

    throw NativeMixPlannerError.scriptMissing
}

private func resolveNodeInvocation(scriptURL: URL) throws -> NativePlannerNodeInvocation {
    let fileManager = FileManager.default
    let resourceURL = Bundle.main.resourceURL
    let bundledCandidates = [
        resourceURL?.appendingPathComponent("Runtime/node")
    ].compactMap { $0 }

    for candidate in bundledCandidates where fileManager.isExecutableFile(atPath: candidate.path) {
        return NativePlannerNodeInvocation(executableURL: candidate, arguments: [scriptURL.path])
    }

    for path in NativePlannerRuntimePath.externalNodeCandidates
        where fileManager.isExecutableFile(atPath: path) {
        return NativePlannerNodeInvocation(
            executableURL: URL(fileURLWithPath: path),
            arguments: [scriptURL.path]
        )
    }

    let envURL = URL(fileURLWithPath: "/usr/bin/env")
    guard fileManager.isExecutableFile(atPath: envURL.path) else {
        throw NativeMixPlannerError.nodeMissing
    }
    return NativePlannerNodeInvocation(
        executableURL: envURL,
        arguments: ["node", scriptURL.path]
    )
}

private struct NativePlannerNodeInvocation: Sendable {
    var executableURL: URL
    var arguments: [String]
}

private enum NativePlannerRuntimePath {
    static let defaultSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    static let externalNodeCandidates = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node"
    ]
}

enum NativeMixPlannerError: LocalizedError {
    case scriptMissing
    case nodeMissing
    case timeout

    var errorDescription: String? {
        switch self {
        case .scriptMissing:
            return "Could not find codex-mix-planner.cjs."
        case .nodeMissing:
            return "Could not find a Node runtime for codex-mix-planner.cjs."
        case .timeout:
            return "planner_timeout"
        }
    }
}
