import BeatDropperApplication
import SwiftUI

extension ContentView {
    var inspectorPane: some View {
        inspectorContent
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Mix Pair Inspector")
                    .font(.title3.weight(.semibold))

                Spacer()

                centeredIconButton(
                    systemImage: "xmark",
                    help: "Close mix inspector",
                    accessibilityLabel: "Close mix inspector"
                ) {
                    navigation.isInspectorVisible = false
                }
            }

            if let selectedTrack = library.selectedTrack {
                GroupBox("Selected Track") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !library.isAvailable(selectedTrack) {
                            HStack {
                                Label("File unavailable", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                Spacer()
                                Button("Relink File", systemImage: "link") {
                                    model.libraryActions.relinkSelectedTrack()
                                }
                            }
                        }
                        Text(selectedTrack.track.title)
                            .font(.headline)
                            .lineLimit(2)
                        LabeledContent("Status", value: library.availabilityStatus(for: selectedTrack))
                        LabeledContent("BPM", value: selectedTrack.track.bpm.map { String(Int($0.rounded())) } ?? "--")
                        LabeledContent("Length", value: formatDuration(selectedTrack.track.durationSec))
                        LabeledContent("Format", value: selectedTrack.track.format.rawValue.uppercased())
                        LabeledContent("File", value: selectedTrack.url.lastPathComponent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Analysis") {
                    analysisSummary(for: selectedTrack)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("AI Mix Plan") {
                    mixPlanSummary
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Mix Review Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(review.recentEvents.count) saved · \(review.importedArtifacts.count) imported")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Import", systemImage: "tray.and.arrow.down") {
                                model.reviewActions.importMixReviewArtifact()
                            }
                            .controlSize(.small)
                            .help("Import exported mix review notes as review-only artifacts")
                            Menu {
                                Menu("All Recent") {
                                    Button("Markdown", systemImage: "doc.text") {
                                        mixReviewExportPreview = model.reviewActions.buildMixReviewExportPreview(format: .markdown)
                                    }
                                    Button("JSON", systemImage: "curlybraces") {
                                        mixReviewExportPreview = model.reviewActions.buildMixReviewExportPreview(format: .json)
                                    }
                                }
                                Menu("Latest Selected Pair") {
                                    Button("Markdown", systemImage: "doc.text") {
                                        mixReviewExportPreview = model.reviewActions.buildMixReviewExportPreview(format: .markdown, scope: .latestSelectedPair)
                                    }
                                    Button("JSON", systemImage: "curlybraces") {
                                        mixReviewExportPreview = model.reviewActions.buildMixReviewExportPreview(format: .json, scope: .latestSelectedPair)
                                    }
                                }
                                .disabled(!model.reviewActions.canPreviewSelectedPairMixReviewNotes)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .controlSize(.small)
                            .disabled(!model.reviewActions.canExportMixReviewNotes)
                            .help("Export recent AI and fallback review diffs as Markdown or JSON")
                        }
                        if !review.recentEvents.isEmpty {
                            recentMixReviewEventsSummary
                        } else {
                            Text("No recent in-app review notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !review.importedArtifacts.isEmpty {
                            Divider()
                            importedMixReviewArtifactsSummary
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No Selection", systemImage: "waveform")
            }

            Spacer()
        }
    }

    func mixReviewExportPreviewSheet(_ preview: MixReviewExportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.format.previewTitle)
                        .font(.headline)
                    Text("\(preview.reviewCount) \(preview.scope.noticeLabel) review\(preview.reviewCount == 1 ? "" : "s") ready for audition notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    mixReviewExportPreview = nil
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                Text(preview.content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minWidth: 640, minHeight: 360)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }

            HStack {
                Text("Preview only. Export does not change playback or planner behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy \(preview.format.noticeLabel)", systemImage: "doc.on.doc") {
                    model.reviewActions.copyMixReviewExportPreviewToClipboard(preview)
                }
                .help("Copy the previewed \(preview.format.noticeLabel) notes to the clipboard")
                Button("Export \(preview.format.noticeLabel)", systemImage: "square.and.arrow.down") {
                    mixReviewExportPreview = nil
                    model.reviewActions.exportMixReviewPreview(preview)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    func mixReviewImportedArtifactPreviewSheet(_ artifact: ImportedMixReviewArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(artifact.fileName)
                        .font(.headline)
                    Text("\(artifact.reviewCount) imported \(artifact.format) review\(artifact.reviewCount == 1 ? "" : "s") · \(artifactPairCountLabel(artifact))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    mixReviewImportedArtifactPreview = nil
                }
                .keyboardShortcut(.cancelAction)
            }

            importedArtifactAnnotationEditor(artifact)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    importedArtifactPairDetailPanel(artifact)

                    Divider()

                    Text("Raw Artifact")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(artifact.content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor))
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 640, minHeight: 360)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }

            Text("Imported notes are read-only review artifacts and do not affect playback or planner behavior.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    func mixReviewImportedArtifactComparisonSheet(_ comparison: ImportedMixReviewArtifactComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Imported Artifact Compare")
                        .font(.headline)
                    Text("\(comparison.pair.currentTrackId) -> \(comparison.pair.nextTrackId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    model.reviewActions.copyImportedMixReviewArtifactComparisonSummary(comparison)
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                }

                Button {
                    model.reviewActions.exportImportedMixReviewArtifactComparisonSummary(comparison)
                } label: {
                    Label("Export Summary", systemImage: "square.and.arrow.down")
                }

                Button("Close") {
                    mixReviewImportedArtifactComparison = nil
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        importedArtifactComparisonMetadata(
                            title: "Left",
                            artifact: comparison.leftArtifact,
                            detail: comparison.pairComparison.leftDetail
                        )
                        importedArtifactComparisonMetadata(
                            title: "Right",
                            artifact: comparison.rightArtifact,
                            detail: comparison.pairComparison.rightDetail
                        )
                    }

                    Divider()

                    importedArtifactComparisonRows(
                        title: "AI Plan",
                        rows: comparison.pairComparison.aiRows
                    )

                    if !comparison.pairComparison.fallbackRows.isEmpty {
                        Divider()
                        importedArtifactComparisonRows(
                            title: "Fallback Plan",
                            rows: comparison.pairComparison.fallbackRows
                        )
                    }

                    if !comparison.pairComparison.hasStructuredDetails {
                        Text("Structured pair details are unavailable for one or both artifacts; compare is limited to matching metadata and annotations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 760, minHeight: 420)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }

            Text("Imported artifact comparison is review-only and does not affect playback or planner behavior.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    func importedArtifactComparisonMetadata(
        title: String,
        artifact: ImportedMixReviewArtifact,
        detail: MixReviewArtifactPairDetail?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(artifact.fileName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            LabeledContent("Format", value: artifact.format)
            LabeledContent("Imported", value: importedArtifactDateLabel(artifact.importedAt))
            LabeledContent("Reviews", value: "\(artifact.reviewCount)")
            if let detail {
                LabeledContent("Planned", value: detail.createdAt)
            } else {
                LabeledContent("Detail", value: "metadata only")
            }
            if !artifact.reviewAnnotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(artifact.reviewAnnotation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    func importedArtifactComparisonRows(
        title: String,
        rows: [MixReviewArtifactComparisonRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("No structured \(title.lowercased()) details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("Field")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)
                    Text("Left")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Right")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Delta")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 112, alignment: .trailing)
                }

                ForEach(rows, id: \.label) { row in
                    importedArtifactComparisonRow(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func importedArtifactComparisonRow(_ row: MixReviewArtifactComparisonRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(row.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(row.leftValue)
                .font(.caption2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.rightValue)
                .font(.caption2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                ForEach(Array(importedArtifactComparisonDeltaParts(row.delta).enumerated()), id: \.offset) { _, part in
                    Text(part)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 112, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    func importedArtifactComparisonDeltaParts(_ delta: String) -> [String] {
        let tokens = delta.split(separator: " ").map(String.init)
        guard tokens.count >= 4, tokens.count.isMultiple(of: 2) else {
            return [delta]
        }
        return stride(from: 0, to: tokens.count, by: 2).map { index in
            "\(tokens[index]) \(tokens[index + 1])"
        }
    }

    func importedArtifactAnnotationEditor(_ artifact: ImportedMixReviewArtifact) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Review Annotation")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { model.reviewActions.importedMixReviewArtifactAnnotation(for: artifact.id) },
                set: { model.reviewActions.updateImportedMixReviewArtifactAnnotation(for: artifact.id, annotation: $0) }
            ))
            .font(.caption)
            .frame(minHeight: 58, maxHeight: 72)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }
        }
    }

    func importedArtifactPairDetailPanel(_ artifact: ImportedMixReviewArtifact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pair Drill-down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if !artifact.pairDetails.isEmpty {
                ForEach(artifact.pairDetails.prefix(8)) { detail in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(importedArtifactDetailPairTitle(detail))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Planned \(detail.createdAt)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        importedArtifactPlanDetailRow(label: "AI", plan: detail.aiPlan)
                        if let fallbackPlan = detail.fallbackPlan {
                            importedArtifactPlanDetailRow(label: "Fallback", plan: fallbackPlan)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            } else if !artifact.trackPairs.isEmpty {
                ForEach(Array(artifact.trackPairs.indices), id: \.self) { index in
                    Text(artifactPairLabel(artifact.trackPairs[index]))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("No pair-level details in this artifact")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func importedArtifactPlanDetailRow(label: String, plan: MixReviewExportPlan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text("\(plan.source) · \(plan.style.rawValue.replacingOccurrences(of: "_", with: " ")) · IN \(formatDuration(plan.nextTrackStartOffsetSec))")
                .font(.caption2)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(qualityLabel(plan.renderedQuality))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(renderedQualityColor(plan.renderedQuality.grade))
                .monospacedDigit()
        }
    }

    func importedArtifactDetailPairTitle(_ detail: MixReviewArtifactPairDetail) -> String {
        "\(trackDisplayLabel(title: detail.currentTrackTitle, id: detail.currentTrackId)) -> \(trackDisplayLabel(title: detail.nextTrackTitle, id: detail.nextTrackId))"
    }

    func trackDisplayLabel(title: String?, id: String) -> String {
        guard let title, !title.isEmpty else {
            return id
        }
        return "\(title) (\(id))"
    }

    @ViewBuilder
    func analysisSummary(for selectedTrack: ImportedTrack) -> some View {
        if !library.isAvailable(selectedTrack) {
            Text("--")
                .foregroundStyle(.secondary)
        } else if library.analyzingTrackIDs.contains(selectedTrack.id) {
            ProgressView("Analyzing")
                .controlSize(.small)
        } else if let analysis = library.selectedTrackAnalysis {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Ready", value: analysis.analysisConfidence >= 0.65 ? "Yes" : "Low")
                LabeledContent("BPM", value: analysis.bpm.map { String(Int($0.rounded())) } ?? "--")
                LabeledContent("Conf", value: "\(Int((analysis.analysisConfidence * 100).rounded()))%")
                LabeledContent("Grid", value: "\(Int((analysis.analysisQuality.beatGrid * 100).rounded()))%")
                LabeledContent("Cue", value: cueSummary(for: analysis))
                if let intro = analysis.introCueSec {
                    LabeledContent("Intro", value: formatDuration(intro))
                }
                if let outro = analysis.outroCueSec {
                    LabeledContent("Outro", value: formatDuration(outro))
                }
            }
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var mixPlanSummary: some View {
        if planning.isPlanning {
            ProgressView("Planning")
                .controlSize(.small)
        } else if let plan = planning.currentPlan {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Transition", value: "\(formatDuration(plan.transitionStartSec)) -> \(formatDuration(plan.transitionEndSec))")
                LabeledContent("Next In", value: formatDuration(plan.nextTrackStartOffsetSec))
                LabeledContent("Style", value: plan.style.rawValue.replacingOccurrences(of: "_", with: " "))
                LabeledContent("Confidence", value: "\(Int((plan.confidence * 100).rounded()))%")
                if let countdown = planning.scheduledCountdownSec {
                    LabeledContent("Starts", value: formatDuration(countdown))
                }
                if let review = planning.currentReview {
                    Divider()
                    mixReviewSummary(plan: plan, review: review)
                }
            }
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    var recentMixReviewEventsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(review.recentEvents.prefix(5)) { event in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(formatDuration(event.transitionStartSec)) -> \(formatDuration(event.transitionEndSec)) · \(event.style.rawValue.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(mixReviewSourceLabel(event.source)) · IN \(formatDuration(event.nextTrackStartOffsetSec)) · \(Int((event.confidence * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let comparison = event.shadowFallbackComparison {
                            compactReviewDiff(ai: event, fallback: comparison)
                        }
                    }

                    Spacer(minLength: 8)

                    Text("\(event.renderedQuality.grade.rawValue) \(Int((event.renderedQuality.score * 100).rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(renderedQualityColor(event.renderedQuality.grade))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    var importedMixReviewArtifactsSummary: some View {
        let artifacts = model.reviewActions.visibleImportedMixReviewArtifacts
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Imported Review Artifacts")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.reviewActions.importedMixReviewArtifactFilterSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Toggle("Selected Pair", isOn: Binding(
                    get: { review.isPairFilterEnabled },
                    set: { review.isPairFilterEnabled = $0 }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(!model.reviewActions.canFilterImportedMixReviewArtifactsBySelectedPair)
                .help("Show only imported review artifacts that include the selected current-to-next track pair")

                Button("Clear", systemImage: "xmark.circle") {
                    model.reviewActions.clearImportedMixReviewArtifactComparisonSelection()
                }
                .controlSize(.small)
                .disabled(review.selectedComparisonArtifactIDs.isEmpty)
                .help("Clear imported artifact comparison selection")

                Button("Compare", systemImage: "rectangle.split.2x1") {
                    mixReviewImportedArtifactComparison = model.reviewActions.buildImportedMixReviewArtifactComparison()
                }
                .controlSize(.small)
                .disabled(!model.reviewActions.canCompareImportedMixReviewArtifacts)
                .help("Compare two selected imported review artifacts for the selected pair")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search imports", text: Binding(
                    get: { review.searchText },
                    set: { review.searchText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                if !review.searchText.isEmpty {
                    Button("", systemImage: "xmark.circle.fill") {
                        review.searchText = ""
                    }
                    .buttonStyle(.plain)
                    .help("Clear imported artifact search")
                    .accessibilityLabel("Clear imported artifact search")
                }
            }

            if artifacts.isEmpty {
                Text(importedArtifactEmptyStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(artifacts.prefix(4)) { artifact in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { model.reviewActions.isImportedMixReviewArtifactSelectedForComparison(artifact.id) },
                        set: { _ in model.reviewActions.toggleImportedMixReviewArtifactComparisonSelection(artifact.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!model.reviewActions.canSelectImportedMixReviewArtifactForComparison(artifact))
                    .help("Select imported artifact for side-by-side comparison")
                    .accessibilityLabel("Select \(artifact.fileName) for comparison")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.fileName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(artifact.format) · \(artifact.reviewCount) review\(artifact.reviewCount == 1 ? "" : "s") · \(artifactPairCountLabel(artifact))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !artifact.trackPairs.isEmpty {
                            importedArtifactPairChips(artifact)
                        }
                        if hasImportedArtifactAnnotation(artifact) {
                            Label("Annotated", systemImage: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("View", systemImage: "doc.text.magnifyingglass") {
                        mixReviewImportedArtifactPreview = artifact
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    var importedArtifactEmptyStateLabel: String {
        if !review.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No imported artifacts match this search"
        }
        return review.isPairFilterEnabled ? "No imported artifacts for this pair" : "No imported artifacts"
    }

    func hasImportedArtifactAnnotation(_ artifact: ImportedMixReviewArtifact) -> Bool {
        !artifact.reviewAnnotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func importedArtifactPairChips(_ artifact: ImportedMixReviewArtifact) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(artifact.trackPairs.prefix(2)).indices, id: \.self) { index in
                Text(artifactPairLabel(artifact.trackPairs[index]))
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .separatorColor).opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            if artifact.trackPairs.count > 2 {
                Text("+\(artifact.trackPairs.count - 2)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func artifactPairLabel(_ pair: MixReviewArtifactTrackPair) -> String {
        "\(pair.currentTrackId) -> \(pair.nextTrackId)"
    }

    func artifactPairCountLabel(_ artifact: ImportedMixReviewArtifact) -> String {
        switch artifact.trackPairs.count {
        case 0:
            return "no pairs"
        case 1:
            return "1 pair"
        default:
            return "\(artifact.trackPairs.count) pairs"
        }
    }

    func importedArtifactDateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    func mixReviewSummary(plan: MixPlan, review: PlannedMixReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Source", value: mixReviewSourceLabel(review.source))
            if let fallbackReason = review.fallbackReason {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selection")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(fallbackReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            LabeledContent {
                Text("\(review.renderedQuality.grade.rawValue) · \(Int((review.renderedQuality.score * 100).rounded()))%")
                    .foregroundStyle(renderedQualityColor(review.renderedQuality.grade))
                    .fontWeight(.semibold)
            } label: {
                Text("Rendered Q")
            }
            Text(review.renderedQuality.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let comparison = review.shadowFallbackComparison {
                aiFallbackDiffView(plan: plan, review: review, fallback: comparison)
            }
            ForEach(review.renderedQuality.metrics, id: \.name) { metric in
                LabeledContent(metricLabel(metric.name), value: metric.summary)
                    .font(.caption)
            }
            if !review.renderedQuality.issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Issues")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(review.renderedQuality.issues.prefix(3)), id: \.self) { issue in
                        Label(issue.message, systemImage: issueIcon(issue.severity))
                            .font(.caption)
                            .foregroundStyle(issueColor(issue.severity))
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    func compactReviewDiff(
        ai event: PlannedMixReviewEvent,
        fallback: PlannedMixReviewPlanComparison
    ) -> some View {
        HStack(spacing: 6) {
            Text("\(mixReviewSourceLabel(event.source)) \(Int((event.renderedQuality.score * 100).rounded()))")
                .foregroundStyle(renderedQualityColor(event.renderedQuality.grade))
            Text("\(mixReviewSourceLabel(fallback.source)) \(Int((fallback.renderedQuality.score * 100).rounded()))")
                .foregroundStyle(renderedQualityColor(fallback.renderedQuality.grade))
            Text(scoreDeltaLabel(selected: event.renderedQuality, fallback: fallback.renderedQuality))
                .foregroundStyle(.tertiary)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
    }

    func aiFallbackDiffView(
        plan: MixPlan,
        review: PlannedMixReview,
        fallback: PlannedMixReviewPlanComparison
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            let selectedLabel = mixReviewSourceLabel(review.source)
            let comparisonLabel = mixReviewSourceLabel(fallback.source)

            HStack(spacing: 8) {
                Text("Diff")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 68, alignment: .leading)
                Text(selectedLabel)
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(comparisonLabel)
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Delta")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }

            diffRow(
                label: "Window",
                aiValue: "\(formatDuration(plan.transitionStartSec)) -> \(formatDuration(plan.transitionEndSec))",
                fallbackValue: "\(formatDuration(fallback.transitionStartSec)) -> \(formatDuration(fallback.transitionEndSec))",
                delta: timingDeltaLabel(plan.transitionStartSec - fallback.transitionStartSec)
            )
            diffRow(
                label: "Next In",
                aiValue: formatDuration(plan.nextTrackStartOffsetSec),
                fallbackValue: formatDuration(fallback.nextTrackStartOffsetSec),
                delta: timingDeltaLabel(plan.nextTrackStartOffsetSec - fallback.nextTrackStartOffsetSec)
            )
            diffRow(
                label: "Candidate",
                aiValue: plan.candidateId ?? "--",
                fallbackValue: fallback.candidateId ?? "--",
                delta: plan.candidateId == fallback.candidateId ? "same" : "diff"
            )
            diffRow(
                label: "Style",
                aiValue: plan.style.rawValue.replacingOccurrences(of: "_", with: " "),
                fallbackValue: fallback.style.rawValue.replacingOccurrences(of: "_", with: " "),
                delta: plan.style == fallback.style ? "same" : "diff"
            )
            diffRow(
                label: "Conf",
                aiValue: "\(Int((plan.confidence * 100).rounded()))%",
                fallbackValue: "\(Int((fallback.confidence * 100).rounded()))%",
                delta: percentDeltaLabel(plan.confidence - fallback.confidence)
            )
            diffRow(
                label: "Quality",
                aiValue: qualityLabel(review.renderedQuality),
                fallbackValue: qualityLabel(fallback.renderedQuality),
                delta: scoreDeltaLabel(selected: review.renderedQuality, fallback: fallback.renderedQuality)
            )
            diffMetricRow("Peak", metricName: "estimated_peak", ai: review.renderedQuality, fallback: fallback.renderedQuality)
            diffMetricRow("Peak Jump", metricName: "peak_jump", ai: review.renderedQuality, fallback: fallback.renderedQuality)
            diffMetricRow("RMS Jump", metricName: "rms_jump", ai: review.renderedQuality, fallback: fallback.renderedQuality)
            diffMetricRow("Masking", metricName: "spectral_masking", ai: review.renderedQuality, fallback: fallback.renderedQuality)
        }
    }

    func diffMetricRow(
        _ label: String,
        metricName: String,
        ai: RenderedTransitionQualityReport,
        fallback: RenderedTransitionQualityReport
    ) -> some View {
        diffRow(
            label: label,
            aiValue: metricSummary(ai, metricName),
            fallbackValue: metricSummary(fallback, metricName),
            delta: scoreDeltaLabel(selectedScore: metricScore(ai, metricName), fallbackScore: metricScore(fallback, metricName))
        )
    }

    func diffRow(label: String, aiValue: String, fallbackValue: String, delta: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(aiValue)
                .font(.caption2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(fallbackValue)
                .font(.caption2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(delta)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    func cueSummary(for analysis: TrackAnalysis) -> String {
        let cueConfidence = analysis.cueCandidates.map(\.confidence).max() ?? 0
        return "\(Int((cueConfidence * 100).rounded()))%"
    }

    func mixReviewSourceLabel(_ source: String) -> String {
        switch source {
        case "cli":
            return "AI planner"
        case "local-fallback":
            return "Local fallback"
        default:
            return source
        }
    }

    func metricLabel(_ name: String) -> String {
        name
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func qualityLabel(_ report: RenderedTransitionQualityReport) -> String {
        "\(report.grade.rawValue) \(Int((report.score * 100).rounded()))%"
    }

    func metricSummary(_ report: RenderedTransitionQualityReport, _ metricName: String) -> String {
        report.metrics.first { $0.name == metricName }?.summary ?? "--"
    }

    func metricScore(_ report: RenderedTransitionQualityReport, _ metricName: String) -> Double {
        report.metrics.first { $0.name == metricName }?.score ?? 0
    }

    func scoreDeltaLabel(
        selected: RenderedTransitionQualityReport,
        fallback: RenderedTransitionQualityReport
    ) -> String {
        scoreDeltaLabel(selectedScore: selected.score, fallbackScore: fallback.score)
    }

    func scoreDeltaLabel(selectedScore: Double, fallbackScore: Double) -> String {
        let delta = selectedScore - fallbackScore
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Int((delta * 100).rounded()))"
    }

    func timingDeltaLabel(_ seconds: Double) -> String {
        if abs(seconds) < 0.05 {
            return "same"
        }
        let sign = seconds >= 0 ? "+" : "-"
        return "\(sign)\(formatDuration(abs(seconds)))"
    }

    func percentDeltaLabel(_ value: Double) -> String {
        if abs(value) < 0.005 {
            return "same"
        }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int((value * 100).rounded()))"
    }

    func renderedQualityColor(_ grade: RenderedTransitionQualityGrade) -> Color {
        switch grade {
        case .pass:
            return .green
        case .warn:
            return .orange
        case .reject:
            return .red
        }
    }

    func issueIcon(_ severity: RenderedTransitionQualityIssueSeverity) -> String {
        switch severity {
        case .warning:
            return "exclamationmark.circle"
        case .major:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }

    func issueColor(_ severity: RenderedTransitionQualityIssueSeverity) -> Color {
        switch severity {
        case .warning:
            return .secondary
        case .major:
            return .orange
        case .critical:
            return .red
        }
    }
}
