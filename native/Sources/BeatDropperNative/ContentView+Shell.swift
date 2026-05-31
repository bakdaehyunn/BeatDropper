import BeatDropperCore
import SwiftUI

extension ContentView {
    var appShell: some View {
        VStack(spacing: 0) {
            toolbar
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(4)
            Divider()
            ZStack(alignment: .trailing) {
                mainStage

                if shouldShowInspectorDrawer {
                    inspectorDrawer
                        .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: AppLayoutMetrics.minimumContentWidth,
            minHeight: AppLayoutMetrics.minimumContentHeight
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var mainStage: some View {
        VStack(spacing: 12) {
            if shouldShowMixMonitor {
                mixMonitor
                    .frame(height: 360)
                    .clipped()
                    .layoutPriority(3)
            }
            workspaceContent
                .frame(minHeight: 0, maxHeight: .infinity)
                .layoutPriority(1)
            if shouldShowStatusBar {
                statusBar
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BeatDropper")
                    .font(.title2.weight(.semibold))
                if let analysisQueueStatus = model.analysisQueueStatus {
                    Text(analysisQueueStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Mode", selection: $model.workspaceMode) {
                ForEach(NativeWorkspaceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .accessibilityLabel("Workspace mode")

            Spacer()

            Button("New Set", systemImage: "folder") {
                model.newSet()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .help("Start a new set from selected audio files")

            if !model.playlist.isEmpty {
                Button("Add Tracks", systemImage: "plus.circle") {
                    model.addTracks()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("Add tracks to the current set")
            }

            Button("Import Folder", systemImage: "folder.badge.plus") {
                model.importFolder()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help("Import a music folder into the library")

            if model.workspaceMode == .playing || !model.isLibraryBrowserVisible {
                Button("Library", systemImage: "rectangle.stack") {
                    model.workspaceMode = .creative
                    model.isLibraryBrowserVisible = true
                }
                .help("Show library browser")
            }

            if model.workspaceMode == .playing {
                Button(model.isInspectorVisible ? "Hide Inspector" : "Inspector", systemImage: "sidebar.right") {
                    model.isInspectorVisible.toggle()
                }
                .keyboardShortcut("3", modifiers: [.command])
                .help(model.isInspectorVisible ? "Hide mix inspector" : "Show mix inspector")
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Primary toolbar")
    }

    @ViewBuilder
    var workspaceContent: some View {
        if model.workspaceMode == .creative {
            creativeWorkspace
        } else {
            playingWorkspace
        }
    }

    var playingWorkspace: some View {
        VStack(spacing: 12) {
            playbackControlBar
                .fixedSize(horizontal: false, vertical: true)

            playlistPane
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.32), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    var shouldShowInspectorDrawer: Bool {
        model.workspaceMode == .playing && model.isInspectorVisible
    }

    var inspectorDrawer: some View {
        inspectorPane
            .frame(width: 360)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .leading)
            .shadow(color: .black.opacity(0.28), radius: 14, x: -8, y: 0)
            .accessibilityLabel("Mix inspector drawer")
    }
}
