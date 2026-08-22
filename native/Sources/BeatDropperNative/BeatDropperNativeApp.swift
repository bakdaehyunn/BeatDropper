import AppKit
import BeatDropperApplication
import BeatDropperPlatform
import SwiftUI

public struct BeatDropperNativeApplication: App {
    @NSApplicationDelegateAdaptor(BeatDropperApplicationDelegate.self) private var appDelegate
    @StateObject private var model: BeatDropperAppModel

    public init() {
        let model = Self.makeModel()
        _model = StateObject(wrappedValue: model)
        BeatDropperApplicationDelegate.model = model
    }

    private static func makeModel() -> BeatDropperAppModel {
        BeatDropperAppModel()
    }

    public var body: some Scene {
        WindowGroup("BeatDropper") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.playing)
                .environmentObject(model.library)
                .environmentObject(model.creative)
                .environmentObject(model.mixPlanning)
                .environmentObject(model.mixReview)
                .environmentObject(model.navigation)
                .environmentObject(model.shell)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Set...") {
                    model.libraryActions.newSet()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Add Tracks...") {
                    model.libraryActions.addTracks()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.library.playlist.isEmpty)

                Button("Import Music Folder...") {
                    model.libraryActions.importFolder()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandMenu("Set") {
                Button("Move Selected Track Up") {
                    model.libraryActions.moveSelectedTrack(offset: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!model.library.canMoveSelectedTrackUp)

                Button("Move Selected Track Down") {
                    model.libraryActions.moveSelectedTrack(offset: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!model.library.canMoveSelectedTrackDown)

                Button("Remove Selected Track") {
                    model.libraryActions.removeSelectedTrack()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!model.library.canRemoveSelectedTrack)

                Button("Clear Set") {
                    model.libraryActions.clearPlaylist()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(!model.library.canClearPlaylist)

                Divider()

                Button("Add Selected Library Track to Set") {
                    model.libraryActions.addSelectedLibraryTrackToPlaylist()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.library.canAddSelectedLibraryTrackToPlaylist)

                Button("Rescan Library Folders") {
                    model.libraryActions.rescanLibraryFolders()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.library.hasSourceFolders)

                Button("Relink Selected Track...") {
                    model.libraryActions.relinkSelectedTrack()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!model.library.selectedTrackNeedsRelink)
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    model.playingActions.playPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.library.playlist.isEmpty)

                Divider()

                Button(model.mixPlanning.isEnabled ? "Turn Off AI Mix" : "Turn On AI Mix") {
                    model.planningActions.setAIMixEnabled(!model.mixPlanning.isEnabled)
                }
                .keyboardShortcut("m", modifiers: [.command])
                .disabled(!model.mixPlanning.isEnabled && !model.mixPlanning.canEnable(in: model.library))

                Button("Cancel AI Mix") {
                    model.planningActions.cancelMixPlan()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.mixPlanning.canCancel)

                Divider()

                Button("Previous Track") {
                    model.playingActions.playPreviousTrack()
                }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .disabled(!model.library.hasPreviousTrack)

                Button("Next Track") {
                    model.playingActions.playNextTrack()
                }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .disabled(!model.library.hasNextTrack)
            }

            CommandMenu("Workspace") {
                Button("Playing Workspace") {
                    model.navigation.workspaceMode = .playing
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Creative Workspace") {
                    model.navigation.workspaceMode = .creative
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button(
                    model.navigation.workspaceMode == .creative && model.navigation.isLibraryBrowserVisible
                        ? "Hide Library Browser"
                        : "Show Library Browser"
                ) {
                    if model.navigation.workspaceMode == .creative && model.navigation.isLibraryBrowserVisible {
                        model.navigation.isLibraryBrowserVisible = false
                    } else {
                        model.navigation.workspaceMode = .creative
                        model.navigation.isLibraryBrowserVisible = true
                    }
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Button("Save Current Set") {
                    model.libraryActions.saveCurrentSet()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!model.library.canSaveCurrentSet)

                Button("Load Selected Set") {
                    model.libraryActions.loadSelectedSavedSet()
                }
                .disabled(!model.library.canLoadSelectedSet)

                Divider()

                Button(
                    model.navigation.workspaceMode == .playing && model.navigation.isInspectorVisible
                        ? "Hide Inspector"
                        : "Show Inspector"
                ) {
                    if model.navigation.workspaceMode == .playing && model.navigation.isInspectorVisible {
                        model.navigation.isInspectorVisible = false
                    } else {
                        model.navigation.workspaceMode = .playing
                        model.navigation.isInspectorVisible = true
                    }
                }
                .keyboardShortcut("3", modifiers: [.command])
            }
        }

        Settings {
            MixSettingsView()
                .environmentObject(model)
                .environmentObject(model.shell)
        }
    }
}

@MainActor
final class BeatDropperApplicationDelegate: NSObject, NSApplicationDelegate {
    static var model: BeatDropperAppModel?
    private var fallbackWindow: NSWindow?
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        revealMainWindowSoon()
        openPendingFinderItemsIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            revealMainWindowSoon()
        }
        return true
    }

    func application(_ application: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        if let model = Self.model {
            model.libraryActions.openFinderItemsAsSet(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
        revealMainWindowSoon()
    }

    private func openPendingFinderItemsIfNeeded() {
        guard !pendingOpenURLs.isEmpty,
              let model = Self.model
        else {
            return
        }

        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        model.libraryActions.openFinderItemsAsSet(urls)
    }

    private func revealMainWindowSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
            if let visibleWindow = NSApp.windows.first(where: { $0.isVisible }) {
                visibleWindow.makeKeyAndOrderFront(nil)
                return
            }
            self.showFallbackWindow()
        }
    }

    private func showFallbackWindow() {
        guard let model = Self.model else {
            return
        }

        if fallbackWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "BeatDropper"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(
                rootView: ContentView()
                    .environmentObject(model)
                    .environmentObject(model.playing)
                    .environmentObject(model.library)
                    .environmentObject(model.creative)
                    .environmentObject(model.mixPlanning)
                    .environmentObject(model.mixReview)
                    .environmentObject(model.navigation)
                    .environmentObject(model.shell)
            )
            fallbackWindow = window
        }

        fallbackWindow?.makeKeyAndOrderFront(nil)
    }

}
