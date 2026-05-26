import Foundation

public enum NativeLibraryRelinkMatchLevel: String, Codable, Comparable, Sendable {
    case conflict
    case weak
    case likely
    case strong
    case exact

    public static func < (left: NativeLibraryRelinkMatchLevel, right: NativeLibraryRelinkMatchLevel) -> Bool {
        left.rank < right.rank
    }

    private var rank: Int {
        switch self {
        case .conflict:
            return 0
        case .weak:
            return 1
        case .likely:
            return 2
        case .strong:
            return 3
        case .exact:
            return 4
        }
    }
}

public struct NativeLibraryRelinkCandidateAssessment: Hashable, Sendable {
    public var level: NativeLibraryRelinkMatchLevel
    public var score: Double
    public var summary: String
    public var reasons: [String]
    public var warnings: [String]
    public var requiresUserConfirmation: Bool

    public init(
        level: NativeLibraryRelinkMatchLevel,
        score: Double,
        summary: String,
        reasons: [String],
        warnings: [String],
        requiresUserConfirmation: Bool
    ) {
        self.level = level
        self.score = score
        self.summary = summary
        self.reasons = reasons
        self.warnings = warnings
        self.requiresUserConfirmation = requiresUserConfirmation
    }
}

public struct NativeLibraryFolderRelinkAssessment: Hashable, Sendable {
    public var level: NativeLibraryRelinkMatchLevel
    public var score: Double
    public var summary: String
    public var reasons: [String]
    public var warnings: [String]
    public var requiresUserConfirmation: Bool
    public var existingTrackCount: Int
    public var importedTrackCount: Int
    public var matchedTrackCount: Int
    public var exactMatchCount: Int

    public init(
        level: NativeLibraryRelinkMatchLevel,
        score: Double,
        summary: String,
        reasons: [String],
        warnings: [String],
        requiresUserConfirmation: Bool,
        existingTrackCount: Int,
        importedTrackCount: Int,
        matchedTrackCount: Int,
        exactMatchCount: Int
    ) {
        self.level = level
        self.score = score
        self.summary = summary
        self.reasons = reasons
        self.warnings = warnings
        self.requiresUserConfirmation = requiresUserConfirmation
        self.existingTrackCount = existingTrackCount
        self.importedTrackCount = importedTrackCount
        self.matchedTrackCount = matchedTrackCount
        self.exactMatchCount = exactMatchCount
    }
}

public enum NativeLibraryRelinkAssessment {
    public static func assess(
        existing: NativeTrackRecord,
        replacement: NativeLibraryImportItem
    ) -> NativeLibraryRelinkCandidateAssessment {
        let existingFingerprint = normalizedOptional(existing.fileFingerprint)
        let replacementFingerprint = normalizedOptional(replacement.fileFingerprint)
        let existingTitle = normalizedTitle(existing.track.title)
        let replacementTitle = normalizedTitle(replacement.track.title)
        let durationDelta = durationDelta(existing.track.durationSec, replacement.track.durationSec)
        let sameFormat = existing.track.format == replacement.track.format

        var score = 0.0
        var reasons: [String] = []
        var warnings: [String] = []

        if let existingFingerprint,
           let replacementFingerprint,
           existingFingerprint == replacementFingerprint {
            score += 0.55
            reasons.append("file fingerprint matches")
        } else if existingFingerprint != nil, replacementFingerprint != nil {
            warnings.append("file fingerprint differs")
        }

        let titleOverlap = tokenOverlap(existingTitle, replacementTitle)
        if !existingTitle.isEmpty, existingTitle == replacementTitle {
            score += 0.40
            reasons.append("title matches")
        } else if titleOverlap >= 0.7 {
            score += 0.28
            reasons.append("title tokens mostly match")
        } else if titleOverlap >= 0.4 {
            score += 0.12
            warnings.append("title only partially matches")
        } else {
            warnings.append("title does not match")
        }

        if let durationDelta {
            if durationDelta <= 2 {
                score += 0.25
                reasons.append("duration matches within 2 seconds")
            } else if durationDelta <= 8 {
                score += 0.14
                reasons.append("duration is close")
            } else if durationDelta <= 20 {
                warnings.append("duration differs by \(Int(durationDelta.rounded())) seconds")
            } else {
                warnings.append("duration differs by more than 20 seconds")
            }
        } else {
            warnings.append("duration could not be compared")
        }

        if sameFormat {
            score += 0.10
            reasons.append("format matches")
        } else {
            warnings.append("format changes from \(existing.track.format.rawValue.uppercased()) to \(replacement.track.format.rawValue.uppercased())")
        }

        let safeScore = min(1, max(0, score))
        let level = level(for: safeScore, fingerprintsMatch: reasons.contains("file fingerprint matches"))
        let riskyTitleMismatch = titleOverlap < 0.4
        let riskyDurationMismatch = (durationDelta ?? 0) > 20
        let requiresConfirmation = level <= .weak || riskyTitleMismatch || riskyDurationMismatch

        return NativeLibraryRelinkCandidateAssessment(
            level: level,
            score: safeScore,
            summary: summary(for: level, score: safeScore),
            reasons: reasons,
            warnings: warnings,
            requiresUserConfirmation: requiresConfirmation
        )
    }

    public static func assessFolder(
        existingRecords: [NativeTrackRecord],
        sourceFolderPath: String,
        imported: [NativeLibraryImportItem]
    ) -> NativeLibraryFolderRelinkAssessment {
        let normalizedSourcePath = normalizedPath(sourceFolderPath)
        let existing = existingRecords.filter {
            normalizedPath($0.sourceFolderPath ?? "") == normalizedSourcePath
        }
        guard !existing.isEmpty else {
            return NativeLibraryFolderRelinkAssessment(
                level: .weak,
                score: 0,
                summary: "No saved tracks reference this source folder",
                reasons: [],
                warnings: ["no saved tracks reference this source folder"],
                requiresUserConfirmation: true,
                existingTrackCount: 0,
                importedTrackCount: imported.count,
                matchedTrackCount: 0,
                exactMatchCount: 0
            )
        }
        guard !imported.isEmpty else {
            return NativeLibraryFolderRelinkAssessment(
                level: .conflict,
                score: 0,
                summary: "Folder relink conflict (0%)",
                reasons: [],
                warnings: ["selected folder has no supported audio files"],
                requiresUserConfirmation: true,
                existingTrackCount: existing.count,
                importedTrackCount: 0,
                matchedTrackCount: 0,
                exactMatchCount: 0
            )
        }

        var bestAssessments: [NativeLibraryRelinkCandidateAssessment] = []
        for record in existing {
            let best = imported
                .map { replacement in assess(existing: record, replacement: replacement) }
                .max { $0.score < $1.score }
            if let best {
                bestAssessments.append(best)
            }
        }

        let exactCount = bestAssessments.filter { $0.level == .exact }.count
        let strongOrBetterCount = bestAssessments.filter { $0.level >= .strong }.count
        let likelyOrBetterCount = bestAssessments.filter { $0.level >= .likely }.count
        let conflictCount = bestAssessments.filter { $0.level == .conflict }.count
        let existingCoverage = Double(likelyOrBetterCount) / Double(existing.count)
        let importedCoverage = Double(likelyOrBetterCount) / Double(max(1, imported.count))
        let score = min(1, max(0, (existingCoverage * 0.75) + (min(1, importedCoverage) * 0.25)))

        let level: NativeLibraryRelinkMatchLevel
        if exactCount == existing.count, imported.count >= existing.count {
            level = .exact
        } else if existingCoverage >= 0.8, strongOrBetterCount >= max(1, Int(Double(existing.count) * 0.5)) {
            level = .strong
        } else if existingCoverage >= 0.5 {
            level = .likely
        } else if existingCoverage >= 0.25 {
            level = .weak
        } else {
            level = .conflict
        }

        var reasons: [String] = []
        var warnings: [String] = []
        if exactCount > 0 {
            reasons.append("\(exactCount) exact fingerprint match\(exactCount == 1 ? "" : "es")")
        }
        if likelyOrBetterCount > 0 {
            reasons.append("\(likelyOrBetterCount) of \(existing.count) saved tracks likely match")
        }
        if imported.count != existing.count {
            warnings.append("selected folder has \(imported.count) tracks; saved folder has \(existing.count)")
        }
        if conflictCount > 0 {
            warnings.append("\(conflictCount) saved track\(conflictCount == 1 ? "" : "s") did not match confidently")
        }
        if likelyOrBetterCount == 0 {
            warnings.append("no confident track matches found")
        }

        return NativeLibraryFolderRelinkAssessment(
            level: level,
            score: score,
            summary: folderSummary(for: level, score: score),
            reasons: reasons,
            warnings: warnings,
            requiresUserConfirmation: level <= .likely || conflictCount > 0,
            existingTrackCount: existing.count,
            importedTrackCount: imported.count,
            matchedTrackCount: likelyOrBetterCount,
            exactMatchCount: exactCount
        )
    }

    private static func level(for score: Double, fingerprintsMatch: Bool) -> NativeLibraryRelinkMatchLevel {
        if fingerprintsMatch {
            return .exact
        }
        if score >= 0.75 {
            return .strong
        }
        if score >= 0.55 {
            return .likely
        }
        if score >= 0.35 {
            return .weak
        }
        return .conflict
    }

    private static func summary(for level: NativeLibraryRelinkMatchLevel, score: Double) -> String {
        let percent = Int((score * 100).rounded())
        switch level {
        case .exact:
            return "Exact relink match (\(percent)%)"
        case .strong:
            return "Strong relink match (\(percent)%)"
        case .likely:
            return "Likely relink match (\(percent)%)"
        case .weak:
            return "Weak relink match (\(percent)%)"
        case .conflict:
            return "Relink conflict (\(percent)%)"
        }
    }

    private static func folderSummary(for level: NativeLibraryRelinkMatchLevel, score: Double) -> String {
        let percent = Int((score * 100).rounded())
        switch level {
        case .exact:
            return "Exact folder relink match (\(percent)%)"
        case .strong:
            return "Strong folder relink match (\(percent)%)"
        case .likely:
            return "Likely folder relink match (\(percent)%)"
        case .weak:
            return "Weak folder relink match (\(percent)%)"
        case .conflict:
            return "Folder relink conflict (\(percent)%)"
        }
    }

    private static func durationDelta(_ left: Double, _ right: Double) -> Double? {
        guard left.isFinite, right.isFinite, left > 0, right > 0 else {
            return nil
        }
        return abs(left - right)
    }

    private static func tokenOverlap(_ left: String, _ right: String) -> Double {
        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return 0
        }
        let intersection = leftTokens.intersection(rightTokens).count
        let denominator = max(leftTokens.count, rightTokens.count)
        return Double(intersection) / Double(denominator)
    }

    private static func normalizedTitle(_ title: String) -> String {
        let scalars = title.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar).lowercased() : " "
        }
        return scalars
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
