import BeatDropperCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: BeatDropperAppModel
    @State var isFileDropTargeted = false
    @State var creativeCueKind: TrackPreparationCueKind = .drop
    @State var creativeBPMDraft = ""
    @State var mixReviewExportPreview: MixReviewExportPreview?
    @State var mixReviewImportedArtifactPreview: ImportedMixReviewArtifact?
    @State var mixReviewImportedArtifactComparison: ImportedMixReviewArtifactComparison?

    var body: some View {
        GeometryReader { proxy in
            appShell
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .top
                )
        }
        .frame(
            minWidth: AppLayoutMetrics.minimumWindowWidth,
            minHeight: AppLayoutMetrics.minimumWindowHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isFileDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
            loadDroppedFileURLs(from: providers)
        }
        .sheet(item: $mixReviewExportPreview) { preview in
            mixReviewExportPreviewSheet(preview)
        }
        .sheet(item: $mixReviewImportedArtifactPreview) { artifact in
            mixReviewImportedArtifactPreviewSheet(artifact)
        }
        .sheet(item: $mixReviewImportedArtifactComparison) { comparison in
            mixReviewImportedArtifactComparisonSheet(comparison)
        }
        .accessibilityLabel("BeatDropper DJ workspace")
    }
}
