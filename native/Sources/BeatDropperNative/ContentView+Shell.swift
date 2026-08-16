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
            Divider()
            playbackControlBar
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var mainStage: some View {
        ScrollView(.vertical, showsIndicators: true) {
            workspaceContent
                .frame(minHeight: 620, alignment: .top)
                .layoutPriority(1)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarWideLayout
            toolbarCompactLayout
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityLabel("Primary toolbar")
    }

    var toolbarWideLayout: some View {
        HStack(spacing: 10) {
            toolbarBrand
            workspaceModePicker

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
    }

    var toolbarCompactLayout: some View {
        HStack(spacing: 10) {
            toolbarBrand
            workspaceModePicker
                .frame(width: 170)
            Spacer(minLength: 4)
            Menu("Actions", systemImage: "ellipsis.circle") {
                Button("New Set", systemImage: "folder") {
                    model.newSet()
                }
                .keyboardShortcut("o", modifiers: [.command])

                if !model.playlist.isEmpty {
                    Button("Add Tracks", systemImage: "plus.circle") {
                        model.addTracks()
                    }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                }

                Button("Import Folder", systemImage: "folder.badge.plus") {
                    model.importFolder()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Show Library", systemImage: "rectangle.stack") {
                    model.workspaceMode = .creative
                    model.isLibraryBrowserVisible = true
                }

                if model.workspaceMode == .playing {
                    Button(model.isInspectorVisible ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") {
                        model.isInspectorVisible.toggle()
                    }
                    .keyboardShortcut("3", modifiers: [.command])
                }
            }
            .help("Set, import, library, and inspector actions")
        }
    }

    var toolbarBrand: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BeatDropper")
                .font(.title2.weight(.semibold))
            if let analysisQueueStatus = model.analysisQueueStatus {
                Text(analysisQueueStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    var workspaceModePicker: some View {
        Picker("Mode", selection: $model.workspaceMode) {
            ForEach(NativeWorkspaceMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 190)
        .accessibilityLabel("Workspace mode")
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
            mixMonitor
                .frame(height: 326)
                .clipped()
                .layoutPriority(3)

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
