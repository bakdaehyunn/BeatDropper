import Foundation

public enum PlannerProcessOutputError: LocalizedError, Equatable, Sendable {
    case exitCode(Int32, stderr: String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .exitCode(let code, let stderr):
            let detail = stderr.isEmpty ? "" : ":\(stderr)"
            return "planner_exit_code:\(code)\(detail)"
        case .invalidJSON(let detail):
            return "planner_invalid_json:\(detail)"
        }
    }
}

public enum PlannerProcessOutputParser {
    public static func decodePlannerResponse(
        stdoutData: Data,
        stderrText: String,
        terminationStatus: Int32,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> PlannerResponse {
        let trimmedStderr = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard terminationStatus == 0 else {
            throw PlannerProcessOutputError.exitCode(terminationStatus, stderr: trimmedStderr)
        }

        do {
            return try decoder.decode(PlannerResponse.self, from: stdoutData)
        } catch {
            let stdoutPreview = String(data: stdoutData.prefix(512), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = [
                error.localizedDescription,
                trimmedStderr.isEmpty ? nil : "stderr=\(trimmedStderr)",
                stdoutPreview.isEmpty ? nil : "stdout=\(stdoutPreview)"
            ].compactMap { $0 }
            throw PlannerProcessOutputError.invalidJSON(parts.joined(separator: "; "))
        }
    }
}
