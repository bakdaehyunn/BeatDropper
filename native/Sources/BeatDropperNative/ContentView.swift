import BeatDropperCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: BeatDropperAppModel
    @State var isFileDropTargeted = false
    @State var creativeCueKind: TrackPreparationCueKind = .drop
    @State var creativeBPMDraft = ""

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                appShell
                    .frame(
                        width: max(proxy.size.width, AppLayoutMetrics.minimumContentWidth),
                        height: max(proxy.size.height, AppLayoutMetrics.minimumContentHeight),
                        alignment: .top
                    )
            }
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
        .accessibilityLabel("BeatDropper DJ workspace")
    }
}
