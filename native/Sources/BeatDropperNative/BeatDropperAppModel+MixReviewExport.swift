import AppKit
import BeatDropperCore
import Foundation
import UniformTypeIdentifiers

enum MixReviewExportFileFormat: Hashable {
    case markdown
    case json

    var defaultFilename: String {
        switch self {
        case .markdown:
            return "BeatDropper-Mix-Review-Notes.md"
        case .json:
            return "BeatDropper-Mix-Review-Notes.json"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .markdown:
            return [UTType(filenameExtension: "md") ?? .plainText]
        case .json:
            return [.json]
        }
    }

    var noticeLabel: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .json:
            return "JSON"
        }
    }

    var previewTitle: String {
        "\(noticeLabel) Export Preview"
    }
}

enum MixReviewExportPreviewScope: Hashable {
    case allRecent
    case latestSelectedPair

    var noticeLabel: String {
        switch self {
        case .allRecent:
            return "all recent"
        case .latestSelectedPair:
            return "selected pair"
        }
    }
}

struct MixReviewExportPreview: Identifiable, Hashable {
    var id = UUID()
    var format: MixReviewExportFileFormat
    var scope: MixReviewExportPreviewScope
    var content: String
    var reviewCount: Int
}

enum MixReviewImportError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported mix review export schema \(version)."
        }
    }
}

extension BeatDropperAppModel {
    var canExportMixReviewNotes: Bool {
        !recentMixReviewEvents.isEmpty
    }

    var canPreviewSelectedPairMixReviewNotes: Bool {
        selectedMixReviewPair.flatMap(latestMixReviewEventMatchingPair) != nil
    }

    var canFilterImportedMixReviewArtifactsBySelectedPair: Bool {
        selectedMixReviewPair != nil
    }

    var visibleImportedMixReviewArtifacts: [ImportedMixReviewArtifact] {
        let pairFilteredArtifacts: [ImportedMixReviewArtifact]
        if isImportedMixReviewArtifactPairFilterEnabled,
           let selectedMixReviewPair {
            pairFilteredArtifacts = importedMixReviewArtifacts.filter { $0.matches(pair: selectedMixReviewPair) }
        } else {
            pairFilteredArtifacts = importedMixReviewArtifacts
        }
        return pairFilteredArtifacts.filter { $0.matches(searchText: importedMixReviewArtifactSearchText) }
    }

    var importedMixReviewArtifactFilterSummary: String {
        let searchText = importedMixReviewArtifactSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            return "\(visibleImportedMixReviewArtifacts.count) of \(importedMixReviewArtifacts.count) matching"
        }
        guard isImportedMixReviewArtifactPairFilterEnabled else {
            return "\(importedMixReviewArtifacts.count) imported"
        }
        guard selectedMixReviewPair != nil else {
            return "No selected pair"
        }
        return "\(visibleImportedMixReviewArtifacts.count) of \(importedMixReviewArtifacts.count) pair-matched"
    }

    var importedMixReviewComparisonEligibleArtifacts: [ImportedMixReviewArtifact] {
        guard let pair = selectedMixReviewPair else {
            return []
        }
        return visibleImportedMixReviewArtifacts.filter {
            MixReviewArtifactComparisonBuilder.isEligible(
                trackPairs: $0.trackPairs,
                currentTrackId: pair.currentTrackId,
                nextTrackId: pair.nextTrackId
            )
        }
    }

    var selectedImportedMixReviewComparisonArtifacts: [ImportedMixReviewArtifact] {
        selectedImportedMixReviewComparisonArtifactIds.compactMap { selectedId in
            importedMixReviewComparisonEligibleArtifacts.first { $0.id == selectedId }
        }
    }

    var canCompareImportedMixReviewArtifacts: Bool {
        selectedImportedMixReviewComparisonArtifacts.count == 2
    }

    func isImportedMixReviewArtifactSelectedForComparison(_ artifactId: ImportedMixReviewArtifact.ID) -> Bool {
        selectedImportedMixReviewComparisonArtifactIds.contains(artifactId)
    }

    func canSelectImportedMixReviewArtifactForComparison(_ artifact: ImportedMixReviewArtifact) -> Bool {
        importedMixReviewComparisonEligibleArtifacts.contains { $0.id == artifact.id }
    }

    func toggleImportedMixReviewArtifactComparisonSelection(_ artifactId: ImportedMixReviewArtifact.ID) {
        selectedImportedMixReviewComparisonArtifactIds = selectedImportedMixReviewComparisonArtifactIds.filter { selectedId in
            importedMixReviewComparisonEligibleArtifacts.contains { $0.id == selectedId }
        }

        if selectedImportedMixReviewComparisonArtifactIds.contains(artifactId) {
            selectedImportedMixReviewComparisonArtifactIds.removeAll { $0 == artifactId }
            return
        }

        guard importedMixReviewComparisonEligibleArtifacts.contains(where: { $0.id == artifactId }) else {
            return
        }

        selectedImportedMixReviewComparisonArtifactIds.append(artifactId)
        selectedImportedMixReviewComparisonArtifactIds = Array(selectedImportedMixReviewComparisonArtifactIds.suffix(2))
    }

    func clearImportedMixReviewArtifactComparisonSelection() {
        selectedImportedMixReviewComparisonArtifactIds = []
    }

    func buildImportedMixReviewArtifactComparison() -> ImportedMixReviewArtifactComparison? {
        guard let pair = selectedMixReviewPair else {
            notice = "Select a current-to-next pair before comparing imports"
            return nil
        }
        let artifacts = selectedImportedMixReviewComparisonArtifacts
        guard artifacts.count == 2 else {
            notice = "Choose two imported artifacts for the selected pair"
            return nil
        }
        let pairComparison = MixReviewArtifactComparisonBuilder.compare(
            leftDetails: artifacts[0].pairDetails,
            rightDetails: artifacts[1].pairDetails,
            currentTrackId: pair.currentTrackId,
            nextTrackId: pair.nextTrackId
        )
        return ImportedMixReviewArtifactComparison(
            pair: pair,
            leftArtifact: artifacts[0],
            rightArtifact: artifacts[1],
            pairComparison: pairComparison
        )
    }

    func buildImportedMixReviewArtifactComparisonSummary(
        _ comparison: ImportedMixReviewArtifactComparison
    ) -> String {
        let summary = MixReviewArtifactComparisonSummary(
            currentTrackId: comparison.pair.currentTrackId,
            nextTrackId: comparison.pair.nextTrackId,
            left: importedMixReviewArtifactComparisonSummarySide(
                label: "Left",
                artifact: comparison.leftArtifact
            ),
            right: importedMixReviewArtifactComparisonSummarySide(
                label: "Right",
                artifact: comparison.rightArtifact
            ),
            pairComparison: comparison.pairComparison
        )
        return MixReviewArtifactComparisonSummaryRenderer.markdown(summary)
    }

    func copyImportedMixReviewArtifactComparisonSummary(_ comparison: ImportedMixReviewArtifactComparison) {
        let content = buildImportedMixReviewArtifactComparisonSummary(comparison)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(content, forType: .string) {
            notice = "Copied imported artifact comparison summary"
        } else {
            notice = "Could not copy imported artifact comparison summary"
        }
    }

    func exportImportedMixReviewArtifactComparisonSummary(_ comparison: ImportedMixReviewArtifactComparison) {
        let content = buildImportedMixReviewArtifactComparisonSummary(comparison)
        guard !content.isEmpty else {
            notice = "No imported artifact comparison summary to export"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Imported Artifact Comparison Summary"
        panel.nameFieldStringValue = "BeatDropper-Imported-Artifact-Compare.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = mixReviewArtifactFolderURL
        guard panel.runModal() == .OK, let url = panel.url else {
            notice = "Export canceled"
            return
        }

        do {
            try Data(content.utf8).write(to: url, options: .atomic)
            updateMixReviewArtifactFolder(url.deletingLastPathComponent())
            notice = "Exported imported artifact comparison summary"
        } catch {
            notice = "Could not export imported artifact comparison summary: \(error.localizedDescription)"
        }
    }

    func buildMixReviewExportPreview(
        format: MixReviewExportFileFormat,
        scope: MixReviewExportPreviewScope = .allRecent
    ) -> MixReviewExportPreview? {
        guard !recentMixReviewEvents.isEmpty else {
            notice = "No mix review notes to preview"
            return nil
        }

        do {
            let events = mixReviewEvents(for: scope)
            guard !events.isEmpty else {
                notice = "No selected pair mix review notes to preview"
                return nil
            }
            let document = buildMixReviewExportDocument(events: events)
            return MixReviewExportPreview(
                format: format,
                scope: scope,
                content: try exportContent(format: format, document: document),
                reviewCount: events.count
            )
        } catch {
            notice = "Could not preview mix review notes: \(error.localizedDescription)"
            return nil
        }
    }

    func copyMixReviewExportPreviewToClipboard(_ preview: MixReviewExportPreview) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(preview.content, forType: .string) {
            notice = "Copied \(preview.reviewCount) \(preview.format.noticeLabel) \(preview.scope.noticeLabel) mix review note\(preview.reviewCount == 1 ? "" : "s")"
        } else {
            notice = "Could not copy mix review notes"
        }
    }

    func exportMixReviewPreview(_ preview: MixReviewExportPreview) {
        guard !preview.content.isEmpty else {
            notice = "No mix review notes to export"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Mix Review Notes"
        panel.nameFieldStringValue = preview.format.defaultFilename
        panel.allowedContentTypes = preview.format.allowedContentTypes
        panel.canCreateDirectories = true
        panel.directoryURL = mixReviewArtifactFolderURL
        guard panel.runModal() == .OK, let url = panel.url else {
            notice = "Export canceled"
            return
        }

        do {
            try Data(preview.content.utf8).write(to: url, options: .atomic)
            updateMixReviewArtifactFolder(url.deletingLastPathComponent())
            notice = "Exported \(preview.reviewCount) \(preview.format.noticeLabel) \(preview.scope.noticeLabel) mix review note\(preview.reviewCount == 1 ? "" : "s")"
        } catch {
            notice = "Could not export mix review notes: \(error.localizedDescription)"
        }
    }

    func importMixReviewArtifact() {
        let panel = NSOpenPanel()
        panel.title = "Import Mix Review Notes"
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = mixReviewArtifactFolderURL
        guard panel.runModal() == .OK, let url = panel.url else {
            notice = "Import canceled"
            return
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let artifact = try buildImportedMixReviewArtifact(fileName: url.lastPathComponent, content: content)
            importedMixReviewArtifacts.insert(artifact, at: 0)
            importedMixReviewArtifacts = Array(importedMixReviewArtifacts.prefix(12))
            selectedImportedMixReviewComparisonArtifactIds = selectedImportedMixReviewComparisonArtifactIds.filter { selectedId in
                importedMixReviewArtifacts.contains { $0.id == selectedId }
            }
            updateMixReviewArtifactFolder(url.deletingLastPathComponent())
            persistMixReviewArtifacts()
            notice = "Imported \(artifact.reviewCount) \(artifact.format) mix review note\(artifact.reviewCount == 1 ? "" : "s")"
        } catch {
            notice = "Could not import mix review notes: \(error.localizedDescription)"
        }
    }

    private func importedMixReviewArtifactComparisonSummarySide(
        label: String,
        artifact: ImportedMixReviewArtifact
    ) -> MixReviewArtifactComparisonSummarySide {
        MixReviewArtifactComparisonSummarySide(
            label: label,
            fileName: artifact.fileName,
            format: artifact.format,
            importedAt: ISO8601DateFormatter().string(from: artifact.importedAt),
            reviewCount: artifact.reviewCount,
            annotation: artifact.reviewAnnotation
        )
    }

    func buildImportedMixReviewArtifact(fileName: String, content: String) throws -> ImportedMixReviewArtifact {
        if let data = content.data(using: .utf8),
           let document = try? JSONDecoder().decode(MixReviewExportDocument.self, from: data) {
            guard document.schemaVersion == mixReviewExportSchemaVersion else {
                throw MixReviewImportError.unsupportedSchema(document.schemaVersion)
            }
            let trackPairs = MixReviewArtifactPairExtractor.trackPairs(content: content)
            let pairDetails = MixReviewArtifactPairDetailExtractor.pairDetails(content: content)
            return ImportedMixReviewArtifact(
                id: UUID(),
                importedAt: Date(),
                fileName: fileName,
                format: "JSON",
                content: try exportContent(format: .json, document: document),
                reviewCount: document.events.count,
                schemaVersion: document.schemaVersion,
                trackPairs: trackPairs,
                pairDetails: pairDetails
            )
        }

        return ImportedMixReviewArtifact(
            id: UUID(),
            importedAt: Date(),
            fileName: fileName,
            format: "Markdown",
            content: content,
            reviewCount: markdownReviewCount(content),
            schemaVersion: markdownSchemaVersion(content),
            trackPairs: MixReviewArtifactPairExtractor.trackPairs(content: content),
            pairDetails: MixReviewArtifactPairDetailExtractor.pairDetails(content: content)
        )
    }

    func restoreMixReviewArtifacts() {
        do {
            let state = try mixReviewArtifactStore.load()
            importedMixReviewArtifacts = state.artifacts.map(ImportedMixReviewArtifact.init(persisted:))
        } catch {
            notice = "Could not restore mix review artifacts: \(error.localizedDescription)"
        }
    }

    func persistMixReviewArtifacts() {
        do {
            try mixReviewArtifactStore.save(
                MixReviewArtifactState(artifacts: importedMixReviewArtifacts.map(\.persisted))
            )
        } catch {
            notice = "Could not save mix review artifacts: \(error.localizedDescription)"
        }
    }

    func importedMixReviewArtifactAnnotation(for artifactId: ImportedMixReviewArtifact.ID) -> String {
        importedMixReviewArtifacts.first { $0.id == artifactId }?.reviewAnnotation ?? ""
    }

    func updateImportedMixReviewArtifactAnnotation(
        for artifactId: ImportedMixReviewArtifact.ID,
        annotation: String
    ) {
        guard let index = importedMixReviewArtifacts.firstIndex(where: { $0.id == artifactId }) else {
            return
        }
        importedMixReviewArtifacts[index].reviewAnnotation = String(
            annotation.prefix(mixReviewArtifactAnnotationCharacterLimit)
        )
        persistMixReviewArtifacts()
    }

    func buildMixReviewExportDocument() -> MixReviewExportDocument {
        buildMixReviewExportDocument(events: recentMixReviewEvents)
    }

    func buildMixReviewExportDocument(events: [PlannedMixReviewEvent]) -> MixReviewExportDocument {
        let formatter = ISO8601DateFormatter()
        return MixReviewExportDocument(
            generatedAt: formatter.string(from: Date()),
            events: events.map { event in
                let selectedPlan = exportPlan(
                    source: mixReviewSourceLabel(event.source),
                    reason: event.fallbackReason ?? event.selectionReason,
                    transitionStartSec: event.transitionStartSec,
                    transitionEndSec: event.transitionEndSec,
                    nextTrackStartOffsetSec: event.nextTrackStartOffsetSec,
                    style: event.style,
                    confidence: event.confidence,
                    candidateId: event.candidateId,
                    renderedQuality: event.renderedQuality
                )
                let comparisonPlan = event.shadowFallbackComparison.map { comparison in
                    exportPlan(
                        source: mixReviewSourceLabel(comparison.source),
                        reason: comparison.reason,
                        transitionStartSec: comparison.transitionStartSec,
                        transitionEndSec: comparison.transitionEndSec,
                        nextTrackStartOffsetSec: comparison.nextTrackStartOffsetSec,
                        style: comparison.style,
                        confidence: comparison.confidence,
                        candidateId: comparison.candidateId,
                        renderedQuality: comparison.renderedQuality
                    )
                }
                let aiPlan: MixReviewExportPlan
                let fallbackPlan: MixReviewExportPlan?
                if event.source == "local-fallback",
                   event.shadowFallbackComparison?.source == "cli",
                   let comparisonPlan {
                    aiPlan = comparisonPlan
                    fallbackPlan = selectedPlan
                } else {
                    aiPlan = selectedPlan
                    fallbackPlan = comparisonPlan
                }
                return MixReviewExportEvent(
                    createdAt: formatter.string(from: event.createdAt),
                    currentTrackId: event.pair.currentTrackId,
                    currentTrackTitle: trackTitle(for: event.pair.currentTrackId),
                    nextTrackId: event.pair.nextTrackId,
                    nextTrackTitle: trackTitle(for: event.pair.nextTrackId),
                    aiPlan: aiPlan,
                    fallbackPlan: fallbackPlan
                )
            }
        )
    }

    var selectedMixReviewPair: PlannedMixPair? {
        if let selectedTrack, let nextTrackAfterSelection {
            return PlannedMixPair(currentTrackId: selectedTrack.id, nextTrackId: nextTrackAfterSelection.id)
        }
        return currentMixPlanPair
    }

    private func mixReviewEvents(for scope: MixReviewExportPreviewScope) -> [PlannedMixReviewEvent] {
        switch scope {
        case .allRecent:
            return recentMixReviewEvents
        case .latestSelectedPair:
            guard let selectedMixReviewPair,
                  let latest = latestMixReviewEventMatchingPair(selectedMixReviewPair)
            else {
                return []
            }
            return [latest]
        }
    }

    private func latestMixReviewEventMatchingPair(_ pair: PlannedMixPair) -> PlannedMixReviewEvent? {
        recentMixReviewEvents.first { $0.pair == pair }
    }

    private func exportContent(format: MixReviewExportFileFormat, document: MixReviewExportDocument) throws -> String {
        switch format {
        case .markdown:
            return MixReviewExportRenderer.markdown(document: document)
        case .json:
            return try MixReviewExportRenderer.json(document: document)
        }
    }

    private func markdownReviewCount(_ content: String) -> Int {
        let pattern = "- Reviews: "
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.hasPrefix(pattern) }
            .flatMap { Int($0.dropFirst(pattern.count).trimmingCharacters(in: .whitespaces)) } ?? 0
    }

    private func markdownSchemaVersion(_ content: String) -> Int? {
        let pattern = "- Schema: "
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.hasPrefix(pattern) }
            .flatMap { Int($0.dropFirst(pattern.count).trimmingCharacters(in: .whitespaces)) }
    }

    private func exportPlan(
        source: String,
        reason: String?,
        transitionStartSec: Double,
        transitionEndSec: Double,
        nextTrackStartOffsetSec: Double,
        style: MixStyle,
        confidence: Double,
        candidateId: String?,
        renderedQuality: RenderedTransitionQualityReport
    ) -> MixReviewExportPlan {
        MixReviewExportPlan(
            source: source,
            reason: reason,
            transitionStartSec: transitionStartSec,
            transitionEndSec: transitionEndSec,
            nextTrackStartOffsetSec: nextTrackStartOffsetSec,
            style: style,
            confidence: confidence,
            candidateId: candidateId,
            renderedQuality: renderedQuality
        )
    }

    private func mixReviewSourceLabel(_ source: String) -> String {
        switch source {
        case "cli":
            return "AI planner"
        case "local-fallback":
            return "Local fallback"
        default:
            return source
        }
    }

    private func trackTitle(for trackId: String) -> String? {
        if let imported = playlist.first(where: { $0.id == trackId }) {
            return imported.track.title
        }
        if let record = libraryRecords.first(where: { $0.id == trackId }) {
            return record.track.title
        }
        return nil
    }
}
