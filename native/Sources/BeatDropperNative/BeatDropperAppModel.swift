import AppKit
import BeatDropperCore
import Foundation

enum NativeWorkspaceMode: String, CaseIterable, Identifiable {
    case playing = "Playing"
    case creative = "Creative"

    var id: String { rawValue }
}

@MainActor
final class BeatDropperAppModel: ObservableObject {
    @Published private(set) var playlist: [ImportedTrack] = []
    @Published private(set) var libraryRecords: [NativeTrackRecord] = [] {
        didSet { rebuildLibraryBrowserIndex() }
    }
    @Published private(set) var librarySourceFolders: [NativeLibrarySourceFolder] = [] {
        didSet { rebuildLibraryBrowserIndex() }
    }
    @Published private(set) var userPlaylists: [UserPlaylist] = []
    @Published private(set) var trackAnalysesById: [String: TrackAnalysis] = [:]
    @Published private(set) var settings: PlayerSettings = .defaults
    @Published private(set) var analyzingTrackIds: Set<String> = []
    @Published private(set) var queuedAnalysisTrackCount: Int = 0
    @Published private(set) var runningAnalysisTrackCount: Int = 0
    @Published private(set) var libraryBrowserTracks: [NativeLibraryBrowserTrack] = []
    @Published private(set) var filteredLibraryTracks: [NativeLibraryBrowserTrack] = []
    @Published private(set) var currentMixPlan: MixPlan?
    @Published private(set) var currentMixPlanPair: PlannedMixPair?
    @Published private(set) var isPlanningMix: Bool = false
    @Published private(set) var plannerStatus: String = "No AI mix plan"
    @Published private(set) var scheduledMixCountdownSec: Double?
    @Published var selectedTrackID: ImportedTrack.ID?
    @Published var selectedUserPlaylistId: String = ""
    @Published var userPlaylistNameDraft: String = ""
    @Published var notice: String = "Ready"
    @Published var workspaceMode: NativeWorkspaceMode = .playing
    @Published var isInspectorVisible: Bool = false
    @Published var isLibraryBrowserVisible: Bool = true
    @Published var selectedLibraryTrackID: ImportedTrack.ID?
    @Published var librarySearchText: String = "" {
        didSet { rebuildFilteredLibraryTracks() }
    }

    let audioEngine = NativeAudioEngine()

    private let store: NativeLibraryStore
    private let settingsStore: NativeSettingsStore
    private let analysisStore: NativeTrackAnalysisStore
    private let mixPlanner: NativeMixPlannerBridge
    private let maxConcurrentAnalysisTasks = NativeAnalysisQueueState.recommendedConcurrency(
        activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
    )
    private var analysisQueueState = NativeAnalysisQueueState()
    private var queuedAnalysisTracksById: [String: ImportedTrack] = [:]
    private var mixPlanTimer: Timer?
    private var isExecutingScheduledMix = false
    private var activePlannerRequestID: UUID?

    init(
        store: NativeLibraryStore = .applicationSupport(),
        settingsStore: NativeSettingsStore = .applicationSupport(),
        analysisStore: NativeTrackAnalysisStore = .applicationSupport(),
        mixPlanner: NativeMixPlannerBridge = NativeMixPlannerBridge()
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.analysisStore = analysisStore
        self.mixPlanner = mixPlanner
        restoreSettings()
        restoreLibraryState()
    }

    var selectedTrack: ImportedTrack? {
        playlist.first { $0.id == selectedTrackID }
    }

    var selectedLibraryTrack: ImportedTrack? {
        guard let selectedLibraryTrackID else {
            return nil
        }
        guard let row = libraryBrowserTracks.first(where: { $0.id == selectedLibraryTrackID }) else {
            return nil
        }
        return importedTrack(from: row)
    }

    var currentDeckDisplayTrack: Track? {
        audioEngine.currentTrack ?? selectedTrack?.track
    }

    var nextDeckDisplayTrack: Track? {
        audioEngine.queuedTrack ?? nextTrackAfterSelection?.track
    }

    var currentDeckDisplayStatus: String {
        if audioEngine.isPlaybackActive {
            return audioEngine.state.rawValue
        }
        guard let selectedTrack else {
            return "Selected"
        }
        return availabilityStatus(for: selectedTrack)
    }

    var nextDeckDisplayStatus: String {
        if audioEngine.queuedTrack != nil {
            return "Queued"
        }
        guard let nextTrackAfterSelection else {
            return "No available next"
        }
        return availabilityStatus(for: nextTrackAfterSelection)
    }

    var selectedTrackAnalysis: TrackAnalysis? {
        guard let selectedTrackID else {
            return nil
        }
        return trackAnalysesById[selectedTrackID]
    }

    var currentDeckAnalysis: TrackAnalysis? {
        guard let trackId = currentDeckDisplayTrack?.id else {
            return nil
        }
        return trackAnalysesById[trackId]
    }

    var nextDeckAnalysis: TrackAnalysis? {
        guard let trackId = nextDeckDisplayTrack?.id else {
            return nil
        }
        return trackAnalysesById[trackId]
    }

    var selectedTrackIndex: Int? {
        guard let selectedTrackID else {
            return nil
        }
        return playlist.firstIndex { $0.id == selectedTrackID }
    }

    var selectedUserPlaylist: UserPlaylist? {
        userPlaylists.first { $0.id == selectedUserPlaylistId }
    }

    var totalDurationSec: Double {
        playlist.reduce(0) { $0 + $1.track.durationSec }
    }

    var hasLibrarySourceFolders: Bool {
        !librarySourceFolders.isEmpty
    }

    var missingSourceFolders: [NativeLibrarySourceFolder] {
        librarySourceFolders.filter(\.missing)
    }

    var hasMissingSourceFolders: Bool {
        !missingSourceFolders.isEmpty
    }

    var analysisQueueStatus: String? {
        let running = runningAnalysisTrackCount
        let queued = queuedAnalysisTrackCount
        guard running + queued > 0 else {
            return nil
        }
        if running > 0, queued > 0 {
            return "DSP analysis \(running) running · \(queued) queued"
        }
        if running > 0 {
            return "DSP analysis \(running) running"
        }
        return "DSP analysis \(queued) queued"
    }

    var selectedTrackNeedsRelink: Bool {
        selectedTrack.map { !isTrackAvailableForImmediateUse($0) } ?? false
    }

    var canSaveCurrentSet: Bool {
        !playlist.isEmpty && !normalizeUserPlaylistName(userPlaylistNameDraft).isEmpty
    }

    var canLoadSelectedSet: Bool {
        selectedUserPlaylist != nil
    }

    var canAddSelectedLibraryTrackToPlaylist: Bool {
        selectedLibraryTrack != nil
    }

    var canMoveSelectedTrackUp: Bool {
        guard let selectedTrackIndex else {
            return false
        }
        return selectedTrackIndex > 0
    }

    var canMoveSelectedTrackDown: Bool {
        guard let selectedTrackIndex else {
            return false
        }
        return selectedTrackIndex < playlist.count - 1
    }

    var canRemoveSelectedTrack: Bool {
        selectedTrackID != nil
    }

    var canClearPlaylist: Bool {
        !playlist.isEmpty
    }

    var hasPreviousTrack: Bool {
        adjacentAvailableTrack(offset: -1) != nil
    }

    var hasNextTrack: Bool {
        nextTrackAfterSelection != nil
    }

    var nextTrackAfterSelection: ImportedTrack? {
        adjacentAvailableTrack(offset: 1)
    }

    var canUseTransportPlayPause: Bool {
        if audioEngine.isPlaybackActive || audioEngine.state == .paused {
            return true
        }
        return selectedTrack.map(isTrackAvailableForImmediateUse) ?? false
    }

    var canRequestMixPlan: Bool {
        guard !isPlanningMix,
              let selectedTrack,
              let nextTrackAfterSelection
        else {
            return false
        }
        return isTrackAvailableForImmediateUse(selectedTrack) &&
            isTrackAvailableForImmediateUse(nextTrackAfterSelection)
    }

    var canCancelMixPlan: Bool {
        currentMixPlan != nil || isPlanningMix
    }

    var isPlaybackActive: Bool {
        audioEngine.isPlaybackActive
    }

    func availabilityStatus(for imported: ImportedTrack) -> String {
        if imported.missing {
            return "Missing"
        }
        if !FileManager.default.fileExists(atPath: imported.url.path) {
            return "Unavailable"
        }
        return "Ready"
    }

    func availabilityStatus(for browserTrack: NativeLibraryBrowserTrack) -> String {
        availabilityStatus(for: importedTrack(from: browserTrack))
    }

    func isTrackAvailable(_ imported: ImportedTrack) -> Bool {
        isTrackAvailableForImmediateUse(imported)
    }

    func isTrackAvailable(_ browserTrack: NativeLibraryBrowserTrack) -> Bool {
        isTrackAvailableForImmediateUse(importedTrack(from: browserTrack))
    }

    func sourceDisplayName(for imported: ImportedTrack) -> String {
        guard let sourceFolderPath = imported.sourceFolderPath else {
            return "Files"
        }
        let normalizedPath = URL(fileURLWithPath: sourceFolderPath).standardizedFileURL.path
        if let folder = librarySourceFolders.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalizedPath
        }) {
            return folder.displayName
        }
        return URL(fileURLWithPath: sourceFolderPath).lastPathComponent
    }

    func importedTrack(from browserTrack: NativeLibraryBrowserTrack) -> ImportedTrack {
        ImportedTrack(
            track: browserTrack.track,
            url: URL(fileURLWithPath: browserTrack.filePath),
            sourceFolderPath: browserTrack.sourceFolderPath,
            fileFingerprint: browserTrack.fileFingerprint,
            missing: browserTrack.missing,
            missingAt: browserTrack.missingAt
        )
    }

    private func adjacentAvailableTrack(offset: Int) -> ImportedTrack? {
        guard
            let selectedTrackIndex,
            offset != 0
        else {
            return nil
        }

        var index = selectedTrackIndex + offset
        while playlist.indices.contains(index) {
            let candidate = playlist[index]
            if isTrackAvailableForImmediateUse(candidate) {
                return candidate
            }
            index += offset
        }
        return nil
    }

    func analysisStatus(for imported: ImportedTrack) -> String {
        guard isTrackAvailableForImmediateUse(imported) else {
            return imported.missing ? "Missing" : "Unavailable"
        }
        if analysisQueueState.isRunning(imported.id) {
            return "Analyzing"
        }
        if analysisQueueState.isPending(imported.id) {
            return "Queued"
        }
        guard let analysis = trackAnalysesById[imported.id] else {
            return "Pending"
        }
        return "Quality \(Int((analysis.analysisConfidence * 100).rounded()))%"
    }

    func newSet() {
        let urls = NativeFileImporter.openAudioFiles()
        guard !urls.isEmpty else {
            notice = "Canceled"
            return
        }

        notice = "Loading tracks..."
        Task {
            let imported = await NativeFileImporter.importTracks(from: urls)
            replacePlaylist(with: imported)
        }
    }

    func addTracks() {
        let urls = NativeFileImporter.openAudioFiles()
        guard !urls.isEmpty else {
            notice = "Canceled"
            return
        }

        notice = "Adding tracks..."
        Task {
            let imported = await NativeFileImporter.importTracks(from: urls)
            appendPlaylist(with: imported)
        }
    }

    func importFolder() {
        guard let folderURL = NativeFileImporter.openMusicFolder() else {
            notice = "Canceled"
            return
        }

        notice = "Importing \(folderURL.lastPathComponent)..."
        Task {
            let imported = await NativeFileImporter.importFolder(folderURL)
            guard !imported.isEmpty else {
                notice = "No supported audio files"
                return
            }

            replacePlaylist(with: imported, sourceFolderURL: folderURL)
            notice = "Imported \(imported.count) tracks from \(folderURL.lastPathComponent)"
        }
    }

    func openFinderItemsAsSet(_ urls: [URL]) {
        openExternalItemsAsSet(urls, sourceName: "Finder")
    }

    func openDroppedItemsAsSet(_ urls: [URL]) {
        openExternalItemsAsSet(urls, sourceName: "drop")
    }

    @discardableResult
    func openExternalItemsForAutomation(_ urls: [URL], sourceName: String) async -> Int {
        let selection = NativeFileImporter.classifyOpenURLs(urls)
        guard selection.supportedItemCount > 0 else {
            notice = "No supported audio files"
            return 0
        }

        notice = "Opening \(selection.supportedItemCount) \(sourceName) item\(selection.supportedItemCount == 1 ? "" : "s")..."
        return await replaceSetFromOpenSelection(selection, sourceName: sourceName)
    }

    private func openExternalItemsAsSet(_ urls: [URL], sourceName: String) {
        Task {
            await openExternalItemsForAutomation(urls, sourceName: sourceName)
        }
    }

    @discardableResult
    func importFolderForAutomation(_ folderURL: URL) async -> Int {
        let imported = await NativeFileImporter.importFolder(folderURL)
        guard !imported.isEmpty else {
            notice = "No supported audio files"
            return 0
        }

        replacePlaylist(with: imported, sourceFolderURL: folderURL)
        notice = "Imported \(imported.count) automation tracks"
        return imported.count
    }

    private func replaceSetFromOpenSelection(_ selection: NativeOpenImportSelection, sourceName: String) async -> Int {
        var resolvedTracks: [ImportedTrack] = []
        var analysisTracks: [ImportedTrack] = []
        var seenTrackIds = Set<String>()
        var skippedCount = selection.unsupportedURLs.count

        for folderURL in selection.folderURLs {
            let imported = await NativeFileImporter.importFolder(folderURL)
            guard !imported.isEmpty else {
                skippedCount += 1
                continue
            }
            let resolved = upsertLibraryRecords(for: imported, sourceFolderURL: folderURL)
            appendUnique(resolved, to: &resolvedTracks, seenTrackIds: &seenTrackIds)
            analysisTracks.append(contentsOf: resolved)
        }

        let importedFiles = await NativeFileImporter.importTracks(from: selection.audioFileURLs)
        let resolvedFiles = upsertLibraryRecords(for: importedFiles, sourceFolderURL: nil)
        appendUnique(resolvedFiles, to: &resolvedTracks, seenTrackIds: &seenTrackIds)
        analysisTracks.append(contentsOf: resolvedFiles)

        guard !resolvedTracks.isEmpty else {
            notice = "No supported audio files"
            return 0
        }

        audioEngine.stop()
        stopMixPlanScheduler()
        playlist = resolvedTracks
        selectedTrackID = resolvedTracks.first?.id
        selectFirstAvailableTrackIfNeeded()
        clearCurrentMixPlan()
        persistLibraryState()
        refreshAnalyses(for: analysisTracks)

        let suffix = skippedCount > 0 ? " · \(skippedCount) skipped" : ""
        notice = "Opened \(resolvedTracks.count) tracks from \(sourceName)\(suffix)"
        return resolvedTracks.count
    }

    private func appendUnique(
        _ tracks: [ImportedTrack],
        to destination: inout [ImportedTrack],
        seenTrackIds: inout Set<String>
    ) {
        for track in tracks where !seenTrackIds.contains(track.id) {
            destination.append(track)
            seenTrackIds.insert(track.id)
        }
    }

    func rescanLibraryFolders() {
        let folders = librarySourceFolders
        guard !folders.isEmpty else {
            notice = "Import a folder before rescanning"
            return
        }

        notice = "Rescanning \(folders.count) folder\(folders.count == 1 ? "" : "s")..."
        Task {
            var importedByFolder: [(NativeLibrarySourceFolder, [ImportedTrack])] = []
            var missingFolders: [NativeLibrarySourceFolder] = []

            for folder in folders {
                let folderURL = URL(fileURLWithPath: folder.path, isDirectory: true)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    let imported = await NativeFileImporter.importFolder(folderURL)
                    importedByFolder.append((folder, imported))
                } else {
                    missingFolders.append(folder)
                }
            }

            for folder in missingFolders {
                markSourceFolderMissing(folder.path)
            }

            var tracksForAnalysis: [ImportedTrack] = []
            var totalImported = 0
            for (folder, imported) in importedByFolder {
                let folderURL = URL(fileURLWithPath: folder.path, isDirectory: true)
                let resolved = upsertLibraryRecords(for: imported, sourceFolderURL: folderURL)
                tracksForAnalysis.append(contentsOf: resolved)
                totalImported += resolved.count
            }

            refreshPlaylistFromLibraryRecords()
            selectFirstAvailableTrackIfNeeded()
            persistLibraryState()
            refreshAnalyses(for: tracksForAnalysis)
            notice = missingFolders.isEmpty
                ? "Rescanned \(totalImported) tracks"
                : "Rescanned \(totalImported) tracks · \(missingFolders.count) folder missing"
        }
    }

    func relinkSelectedTrack() {
        guard let selectedTrack else {
            notice = "Select a missing track first"
            return
        }

        guard let replacementURL = NativeFileImporter.openReplacementAudioFile() else {
            notice = "Canceled"
            return
        }

        notice = "Relinking \(selectedTrack.track.title)..."
        Task {
            guard let replacement = await NativeFileImporter.importTrack(from: replacementURL) else {
                notice = "Unsupported audio file"
                return
            }

            let sourceFolderURL = replacementURL.deletingLastPathComponent()
            let replacementItem = NativeLibraryImportItem(
                track: replacement.track,
                filePath: replacement.url.path,
                sourceFolderPath: sourceFolderURL.standardizedFileURL.path,
                fileFingerprint: fileFingerprint(for: replacement)
            )
            if let existingRecord = libraryRecords.first(where: { $0.id == selectedTrack.id }) {
                let assessment = NativeLibraryRelinkAssessment.assess(
                    existing: existingRecord,
                    replacement: replacementItem
                )
                guard confirmRelinkIfNeeded(
                    assessment: assessment,
                    existingTitle: selectedTrack.track.title,
                    replacementTitle: replacement.track.title
                ) else {
                    notice = "Relink canceled"
                    return
                }
            }

            guard let relinked = relinkLibraryRecord(
                trackId: selectedTrack.id,
                replacement: replacement,
                sourceFolderURL: sourceFolderURL
            ) else {
                notice = "Could not relink track"
                return
            }

            refreshPlaylistFromLibraryRecords()
            selectedTrackID = relinked.id
            clearCurrentMixPlan()
            persistLibraryState()
            trackAnalysesById[relinked.id] = nil
            refreshAnalyses(for: [relinked])
            notice = "Relinked \(relinked.track.title)"
        }
    }

    func relinkMissingSourceFolder(_ folder: NativeLibrarySourceFolder) {
        guard let folderURL = NativeFileImporter.openMusicFolder() else {
            notice = "Canceled"
            return
        }

        notice = "Relinking \(folder.displayName)..."
        Task {
            let imported = await NativeFileImporter.importFolder(folderURL)
            guard !imported.isEmpty else {
                notice = "No supported audio files"
                return
            }

            let sourceFolderPath = folderURL.standardizedFileURL.path
            let importItems = imported.map { track in
                NativeLibraryImportItem(
                    track: track.track,
                    filePath: track.url.path,
                    sourceFolderPath: sourceFolderPath,
                    fileFingerprint: fileFingerprint(for: track)
                )
            }
            let assessment = NativeLibraryRelinkAssessment.assessFolder(
                existingRecords: libraryRecords,
                sourceFolderPath: folder.path,
                imported: importItems
            )
            guard confirmFolderRelinkIfNeeded(
                assessment: assessment,
                oldFolderName: folder.displayName,
                newFolderName: folderURL.lastPathComponent
            ) else {
                notice = "Folder relink canceled"
                return
            }

            let resolved = upsertLibraryRecords(for: imported, sourceFolderURL: folderURL)
            pruneUnreferencedMissingSourceFolders()
            refreshPlaylistFromLibraryRecords()
            selectedTrackID = selectedTrackID ?? resolved.first?.id
            selectFirstAvailableTrackIfNeeded()
            clearCurrentMixPlan()
            persistLibraryState()
            refreshAnalyses(for: resolved)
            notice = "Relinked \(folder.displayName) with \(resolved.count) tracks"
        }
    }

    private func confirmRelinkIfNeeded(
        assessment: NativeLibraryRelinkCandidateAssessment,
        existingTitle: String,
        replacementTitle: String
    ) -> Bool {
        guard assessment.requiresUserConfirmation else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = assessment.level == .conflict ? .critical : .warning
        alert.messageText = "Confirm Track Relink"
        let warnings = assessment.warnings.isEmpty
            ? "No specific warnings."
            : assessment.warnings.joined(separator: "\n")
        let reasons = assessment.reasons.isEmpty
            ? "No strong match evidence."
            : assessment.reasons.joined(separator: "\n")
        alert.informativeText = """
        \(assessment.summary)

        Current: \(existingTitle)
        Replacement: \(replacementTitle)

        Match evidence:
        \(reasons)

        Warnings:
        \(warnings)
        """
        alert.addButton(withTitle: "Relink Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmFolderRelinkIfNeeded(
        assessment: NativeLibraryFolderRelinkAssessment,
        oldFolderName: String,
        newFolderName: String
    ) -> Bool {
        guard assessment.requiresUserConfirmation else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = assessment.level == .conflict ? .critical : .warning
        alert.messageText = "Confirm Folder Relink"
        let warnings = assessment.warnings.isEmpty
            ? "No specific warnings."
            : assessment.warnings.joined(separator: "\n")
        let reasons = assessment.reasons.isEmpty
            ? "No strong match evidence."
            : assessment.reasons.joined(separator: "\n")
        alert.informativeText = """
        \(assessment.summary)

        Current folder: \(oldFolderName)
        Replacement folder: \(newFolderName)
        Matched tracks: \(assessment.matchedTrackCount) of \(assessment.existingTrackCount)
        Imported tracks: \(assessment.importedTrackCount)

        Match evidence:
        \(reasons)

        Warnings:
        \(warnings)
        """
        alert.addButton(withTitle: "Relink Folder Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func replacePlaylist(with imported: [ImportedTrack], sourceFolderURL: URL? = nil) {
        guard !imported.isEmpty else {
            notice = "Canceled"
            return
        }

        let resolved = upsertLibraryRecords(for: imported, sourceFolderURL: sourceFolderURL)
        audioEngine.stop()
        stopMixPlanScheduler()
        playlist = resolved
        selectedTrackID = resolved.first?.id
        clearCurrentMixPlan()
        persistLibraryState()
        refreshAnalyses(for: resolved)
        notice = "Loaded \(resolved.count) tracks"
    }

    private func appendPlaylist(with imported: [ImportedTrack]) {
        guard !imported.isEmpty else {
            notice = "Canceled"
            return
        }

        let resolved = upsertLibraryRecords(for: imported, sourceFolderURL: nil)
        playlist.append(contentsOf: resolved)
        selectedTrackID = selectedTrackID ?? resolved.first?.id
        persistLibraryState()
        refreshAnalyses(for: resolved)
        notice = "Added \(resolved.count) tracks"
    }

    func addSelectedLibraryTrackToPlaylist() {
        guard let selectedLibraryTrack else {
            notice = "Select a library track first"
            return
        }
        addLibraryTrackToPlaylist(selectedLibraryTrack)
    }

    func addLibraryTrackToPlaylist(_ imported: ImportedTrack) {
        if playlist.contains(where: { $0.id == imported.id }) {
            selectedTrackID = imported.id
            notice = "Already in current set"
            return
        }

        playlist.append(imported)
        selectedTrackID = imported.id
        clearCurrentMixPlan()
        persistLibraryState()
        refreshAnalyses(for: [imported])
        notice = "Added \(imported.track.title) to set"
    }

    func removeSelectedTrack() {
        guard let selectedTrackID else {
            return
        }

        playlist.removeAll { $0.id == selectedTrackID }
        self.selectedTrackID = playlist.first?.id
        clearCurrentMixPlan()
        persistLibraryState()
        notice = "Removed track"
    }

    func clearPlaylist() {
        audioEngine.stop()
        stopMixPlanScheduler()
        playlist.removeAll()
        selectedTrackID = nil
        clearCurrentMixPlan()
        persistLibraryState()
        notice = "Cleared playlist"
    }

    func moveSelectedTrack(offset: Int) {
        guard
            let selectedTrackID,
            let currentIndex = playlist.firstIndex(where: { $0.id == selectedTrackID })
        else {
            return
        }

        let targetIndex = max(0, min(playlist.count - 1, currentIndex + offset))
        guard currentIndex != targetIndex else {
            return
        }

        let item = playlist.remove(at: currentIndex)
        playlist.insert(item, at: targetIndex)
        clearCurrentMixPlan()
        persistLibraryState()
    }

    func selectUserPlaylist(_ id: String) {
        selectedUserPlaylistId = id
        userPlaylistNameDraft = selectedUserPlaylist?.name ?? ""
        persistLibraryState()
    }

    func saveCurrentSet() {
        let name = normalizeUserPlaylistName(userPlaylistNameDraft)
        guard !name.isEmpty else {
            notice = "Name the saved set first"
            return
        }
        guard !playlist.isEmpty else {
            notice = "Add tracks before saving a set"
            return
        }

        let now = timestamp()
        let trackIds = playlist.map(\.id)

        if let index = userPlaylists.firstIndex(where: { $0.id == selectedUserPlaylistId }) {
            let current = userPlaylists[index]
            userPlaylists[index] = UserPlaylist(
                id: current.id,
                name: name,
                trackIds: trackIds,
                createdAt: current.createdAt,
                updatedAt: now
            )
            notice = "Saved \(name)"
        } else {
            let playlist = UserPlaylist(
                id: UUID().uuidString,
                name: name,
                trackIds: trackIds,
                createdAt: now,
                updatedAt: now
            )
            userPlaylists.append(playlist)
            selectedUserPlaylistId = playlist.id
            notice = "Saved \(name)"
        }

        persistLibraryState()
    }

    func loadSelectedSavedSet() {
        guard let selectedUserPlaylist else {
            notice = "Choose a saved set first"
            return
        }

        let recordsById = Dictionary(uniqueKeysWithValues: libraryRecords.map { ($0.id, $0) })
        let restored = selectedUserPlaylist.trackIds.compactMap { id in
            recordsById[id].map(ImportedTrack.init(record:))
        }

        guard !restored.isEmpty else {
            notice = "Saved set has no available tracks"
            return
        }

        audioEngine.stop()
        playlist = restored
        selectedTrackID = restored.first?.id
        selectFirstAvailableTrackIfNeeded()
        userPlaylistNameDraft = selectedUserPlaylist.name
        clearCurrentMixPlan()
        persistLibraryState()
        refreshAnalyses(for: restored)
        notice = "Loaded \(selectedUserPlaylist.name)"
    }

    func renameSelectedSavedSet() {
        let name = normalizeUserPlaylistName(userPlaylistNameDraft)
        guard !name.isEmpty else {
            notice = "Name the saved set first"
            return
        }
        guard let index = userPlaylists.firstIndex(where: { $0.id == selectedUserPlaylistId }) else {
            notice = "Choose a saved set first"
            return
        }

        let current = userPlaylists[index]
        userPlaylists[index] = UserPlaylist(
            id: current.id,
            name: name,
            trackIds: current.trackIds,
            createdAt: current.createdAt,
            updatedAt: timestamp()
        )
        persistLibraryState()
        notice = "Renamed saved set"
    }

    func deleteSelectedSavedSet() {
        guard let selectedUserPlaylist else {
            notice = "Choose a saved set first"
            return
        }

        userPlaylists.removeAll { $0.id == selectedUserPlaylist.id }
        selectedUserPlaylistId = ""
        userPlaylistNameDraft = ""
        persistLibraryState()
        notice = "Deleted \(selectedUserPlaylist.name)"
    }

    func updateFadeDuration(_ value: Double) {
        updateSettings(invalidatesMixPlan: true) { settings in
            settings.fadeDurationSec = value
        }
    }

    func updateMasterGain(_ value: Double) {
        updateSettings(invalidatesMixPlan: false) { settings in
            settings.masterGain = value
        }
    }

    func updateAIDJMode(_ mode: AIDJMode) {
        updateSettings(invalidatesMixPlan: true) { settings in
            settings.aiDjMode = mode
        }
    }

    func playPause() {
        do {
            if audioEngine.isPlaybackActive {
                audioEngine.pause()
                stopMixPlanScheduler()
                return
            }

            if audioEngine.state == .paused {
                try audioEngine.resume()
                startMixPlanSchedulerIfNeeded()
                return
            }

            guard let selectedTrack else {
                notice = "Load tracks first"
                return
            }
            guard markTrackMissingIfUnavailable(selectedTrack) else {
                notice = "Track file is missing. Rescan or relink the source folder."
                return
            }

            try audioEngine.play(url: selectedTrack.url, track: selectedTrack.track)
            startMixPlanSchedulerIfNeeded()
            notice = "Playing \(selectedTrack.track.title)"
        } catch {
            notice = error.localizedDescription
        }
    }

    func playPreviousTrack() {
        playAdjacentTrack(offset: -1)
    }

    func playNextTrack() {
        playAdjacentTrack(offset: 1)
    }

    func requestMixPlanForNextTrack() {
        guard let current = selectedTrack, let next = nextTrackAfterSelection else {
            plannerStatus = "Select a track with a next track first"
            notice = plannerStatus
            return
        }
        guard markTrackMissingIfUnavailable(current),
              markTrackMissingIfUnavailable(next)
        else {
            plannerStatus = "Cannot plan mix with missing files"
            notice = plannerStatus
            return
        }

        isPlanningMix = true
        let requestID = UUID()
        activePlannerRequestID = requestID
        plannerStatus = "Requesting AI mix plan..."
        notice = plannerStatus
        let currentElapsed = audioEngine.currentTrack?.id == current.id
            ? audioEngine.elapsedSec
            : 0
        let currentAnalysis = trackAnalysesById[current.id]
        let nextAnalysis = trackAnalysesById[next.id]
        let plannerSettings = PlannerSettingsSnapshot(
            fadeDurationSec: settings.fadeDurationSec,
            aiDjMode: settings.aiDjMode
        )
        let request = PlannerRequestBuilder.build(
            currentTrack: current.track,
            nextTrack: next.track,
            elapsedSec: currentElapsed,
            currentAnalysis: currentAnalysis,
            nextAnalysis: nextAnalysis,
            settings: plannerSettings
        )
        let validationContext = MixPlanValidationContext(
            currentPlaybackElapsedSec: request.currentPlayback.elapsedSec,
            currentTrackDurationSec: current.track.durationSec,
            nextTrackDurationSec: next.track.durationSec,
            maxFadeDurationSec: self.settings.fadeDurationSec
        )
        var mixPlanner = self.mixPlanner
        mixPlanner.timeoutSec = max(1, self.settings.plannerTimeoutMs / 1_000)

        Task { [weak self] in
            let result = await mixPlanner.requestMixPlan(
                request: request,
                validationContext: validationContext
            )
            guard let self else {
                return
            }
            guard self.activePlannerRequestID == requestID else {
                return
            }

            self.isPlanningMix = false
            self.activePlannerRequestID = nil
            if let plan = result.plan {
                self.currentMixPlan = plan
                self.currentMixPlanPair = PlannedMixPair(currentTrackId: current.id, nextTrackId: next.id)
                self.updateScheduledMixStatus()
                self.startMixPlanSchedulerIfNeeded()
                self.notice = result.source == "local-fallback"
                    ? "Local fallback mix plan ready"
                    : "AI mix plan ready"
            } else {
                self.currentMixPlan = nil
                self.currentMixPlanPair = nil
                self.plannerStatus = result.reason ?? "AI planner returned no plan"
                self.notice = self.plannerStatus
            }
        }
    }

    func cancelMixPlan() {
        stopMixPlanScheduler()
        clearCurrentMixPlan()
        isPlanningMix = false
        activePlannerRequestID = nil
        notice = "Canceled AI mix plan"
    }

    private func playAdjacentTrack(offset: Int) {
        do {
            guard
                let selectedTrackIndex,
                let target = adjacentAvailableTrack(offset: offset)
            else {
                notice = offset > 0 ? "No available next track" : "No available previous track"
                return
            }

            let current = playlist[selectedTrackIndex]
            let matchingPlan = offset == 1 &&
                currentMixPlanPair?.currentTrackId == current.id &&
                currentMixPlanPair?.nextTrackId == target.id
                ? currentMixPlan
                : nil
            selectedTrackID = target.id

            if audioEngine.isPlaybackActive {
                try executeTransition(
                    from: current,
                    to: target,
                    plan: matchingPlan,
                    clearPlanAfterStart: true
                )
                notice = matchingPlan == nil
                    ? "Crossfading to \(target.track.title)"
                    : "Executing AI mix plan"
            } else {
                try audioEngine.play(url: target.url, track: target.track)
                notice = "Playing \(target.track.title)"
            }
            clearCurrentMixPlan()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func executeTransition(
        from current: ImportedTrack,
        to target: ImportedTrack,
        plan: MixPlan?,
        clearPlanAfterStart: Bool
    ) throws {
        guard markTrackMissingIfUnavailable(target) else {
            throw NativePlaybackError.trackUnavailable(target.track.title)
        }

        let duration = plan.map {
            max(0.25, $0.transitionEndSec - $0.transitionStartSec)
        } ?? settings.fadeDurationSec
        let startOffset = plan?.nextTrackStartOffsetSec ?? 0
        selectedTrackID = target.id
        try audioEngine.crossfadeTo(
            url: target.url,
            track: target.track,
            durationSec: duration,
            startOffsetSec: startOffset
        ) { [weak self] in
            self?.notice = "Playing \(target.track.title)"
        }
        if clearPlanAfterStart {
            clearCurrentMixPlan()
        }
    }

    private func restoreLibraryState() {
        do {
            let state = try store.loadMigratingElectronStateIfNeeded()
            libraryRecords = state.trackRecords
            librarySourceFolders = state.sourceFolders
            userPlaylists = state.userPlaylists
            selectedUserPlaylistId = state.selectedUserPlaylistId
            userPlaylistNameDraft = selectedUserPlaylist?.name ?? ""

            let recordsById = Dictionary(uniqueKeysWithValues: state.trackRecords.map { ($0.id, $0) })
            playlist = state.currentPlaylistTrackIds.compactMap { id in
                recordsById[id].map(ImportedTrack.init(record:))
            }
            selectedTrackID = playlist.first?.id
            selectFirstAvailableTrackIfNeeded()
            refreshAnalyses(for: playlist)
            notice = playlist.isEmpty ? "Ready" : "Restored \(playlist.count) tracks"
        } catch {
            notice = "Could not restore library: \(error.localizedDescription)"
        }
    }

    private func restoreSettings() {
        do {
            settings = try settingsStore.loadMigratingElectronSettingsIfNeeded()
            audioEngine.setMasterGain(settings.masterGain)
        } catch {
            settings = .defaults
            audioEngine.setMasterGain(settings.masterGain)
            notice = "Could not restore settings: \(error.localizedDescription)"
        }
    }

    private func persistSettings() {
        do {
            try settingsStore.save(settings)
        } catch {
            notice = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func updateSettings(
        invalidatesMixPlan: Bool,
        mutate: (inout PlayerSettings) -> Void
    ) {
        var next = settings
        mutate(&next)
        settings = NativeSettingsStore.sanitize(next)
        audioEngine.setMasterGain(settings.masterGain)
        if invalidatesMixPlan {
            clearCurrentMixPlan()
        }
        persistSettings()
    }

    private func persistLibraryState() {
        do {
            let state = NativeLibraryState(
                trackRecords: libraryRecords,
                sourceFolders: librarySourceFolders,
                currentPlaylistTrackIds: playlist.map(\.id),
                userPlaylists: userPlaylists,
                selectedUserPlaylistId: selectedUserPlaylistId
            )
            try store.save(state)
        } catch {
            notice = "Could not save library: \(error.localizedDescription)"
        }
    }

    private func rebuildLibraryBrowserIndex() {
        libraryBrowserTracks = NativeLibraryBrowserIndex.build(
            records: libraryRecords,
            sourceFolders: librarySourceFolders
        )
        rebuildFilteredLibraryTracks()
    }

    private func rebuildFilteredLibraryTracks() {
        filteredLibraryTracks = NativeLibraryBrowserIndex.filter(
            libraryBrowserTracks,
            query: librarySearchText
        )
        if let selectedLibraryTrackID,
           !libraryBrowserTracks.contains(where: { $0.id == selectedLibraryTrackID }) {
            self.selectedLibraryTrackID = nil
        }
    }

    @discardableResult
    private func upsertLibraryRecords(for imported: [ImportedTrack], sourceFolderURL: URL?) -> [ImportedTrack] {
        let now = timestamp()
        let sourceFolderPath = sourceFolderURL?.standardizedFileURL.path
        let sourceFolder = sourceFolderURL.map {
            NativeLibrarySourceFolderInput(path: $0.standardizedFileURL.path, displayName: $0.lastPathComponent)
        }
        let importItems = imported.map { track in
            NativeLibraryImportItem(
                track: track.track,
                filePath: track.url.path,
                sourceFolderPath: sourceFolderPath,
                fileFingerprint: fileFingerprint(for: track)
            )
        }
        let result = NativeLibraryReconciler.upsert(
            existingRecords: libraryRecords,
            existingSourceFolders: librarySourceFolders,
            imported: importItems,
            sourceFolder: sourceFolder,
            now: now
        )
        libraryRecords = result.trackRecords
        librarySourceFolders = result.sourceFolders

        let recordsById = Dictionary(uniqueKeysWithValues: libraryRecords.map { ($0.id, $0) })
        var seenResolvedIds = Set<String>()
        return imported.compactMap { importedTrack in
            let resolvedId = result.resolvedTrackIdByImportId[importedTrack.id] ?? importedTrack.id
            guard !seenResolvedIds.contains(resolvedId) else {
                return nil
            }
            seenResolvedIds.insert(resolvedId)
            if let record = recordsById[resolvedId] {
                return ImportedTrack(record: record)
            }
            return importedTrack
        }
    }

    @discardableResult
    private func relinkLibraryRecord(
        trackId: String,
        replacement: ImportedTrack,
        sourceFolderURL: URL?
    ) -> ImportedTrack? {
        let now = timestamp()
        let sourceFolderPath = sourceFolderURL?.standardizedFileURL.path
        let sourceFolder = sourceFolderURL.map {
            NativeLibrarySourceFolderInput(path: $0.standardizedFileURL.path, displayName: $0.lastPathComponent)
        }
        let item = NativeLibraryImportItem(
            track: replacement.track,
            filePath: replacement.url.path,
            sourceFolderPath: sourceFolderPath,
            fileFingerprint: fileFingerprint(for: replacement)
        )
        let result = NativeLibraryReconciler.relinkTrack(
            existingRecords: libraryRecords,
            existingSourceFolders: librarySourceFolders,
            trackId: trackId,
            replacement: item,
            sourceFolder: sourceFolder,
            now: now
        )
        libraryRecords = result.trackRecords
        librarySourceFolders = result.sourceFolders
        pruneUnreferencedMissingSourceFolders()
        return libraryRecords.first { $0.id == trackId }.map(ImportedTrack.init(record:))
    }

    private func markSourceFolderMissing(_ sourceFolderPath: String) {
        let result = NativeLibraryReconciler.markSourceFolderMissing(
            existingRecords: libraryRecords,
            existingSourceFolders: librarySourceFolders,
            sourceFolderPath: sourceFolderPath,
            now: timestamp()
        )
        libraryRecords = result.trackRecords
        librarySourceFolders = result.sourceFolders
    }

    private func pruneUnreferencedMissingSourceFolders() {
        let referencedSourcePaths = Set(libraryRecords.compactMap { record -> String? in
            guard let sourceFolderPath = record.sourceFolderPath else {
                return nil
            }
            return URL(fileURLWithPath: sourceFolderPath).standardizedFileURL.path
        })
        librarySourceFolders.removeAll { folder in
            folder.missing && !referencedSourcePaths.contains(URL(fileURLWithPath: folder.path).standardizedFileURL.path)
        }
    }

    private func refreshPlaylistFromLibraryRecords() {
        let recordsById = Dictionary(uniqueKeysWithValues: libraryRecords.map { ($0.id, $0) })
        playlist = playlist.map { imported in
            guard let record = recordsById[imported.id] else {
                return imported
            }
            return ImportedTrack(record: record)
        }
    }

    private func refreshAnalyses(for imported: [ImportedTrack]) {
        let tracksNeedingAnalysis = imported.filter { track in
            guard isTrackAvailableForImmediateUse(track) else {
                return false
            }
            if analyzingTrackIds.contains(track.id) {
                return false
            }
            if let cached = try? analysisStore.read(trackId: track.id),
               isCurrentAnalysis(cached, for: track) {
                applyAnalysis(cached, persist: false)
                return false
            }
            return true
        }

        enqueueAnalyses(for: tracksNeedingAnalysis)
    }

    private func enqueueAnalyses(for imported: [ImportedTrack]) {
        guard !imported.isEmpty else {
            syncAnalysisQueuePublishedState()
            return
        }

        var idsToEnqueue: [String] = []
        for track in imported where !analysisQueueState.contains(track.id) {
            queuedAnalysisTracksById[track.id] = track
            idsToEnqueue.append(track.id)
        }

        analysisQueueState.enqueue(idsToEnqueue)
        syncAnalysisQueuePublishedState()
        drainAnalysisQueue()
    }

    private func drainAnalysisQueue() {
        let trackIds = analysisQueueState.startAvailable(maxConcurrent: maxConcurrentAnalysisTasks)
        for trackId in trackIds {
            guard let imported = queuedAnalysisTracksById.removeValue(forKey: trackId) else {
                analysisQueueState.finish(trackId)
                continue
            }
            startAnalysis(for: imported)
        }
        syncAnalysisQueuePublishedState()
    }

    private func startAnalysis(for imported: ImportedTrack) {
        let analysisStore = analysisStore
        let analysisTask = Task.detached(priority: .utility) {
            let analysis = try NativeTrackAnalyzer.analyze(importedTrack: imported)
            try analysisStore.write(analysis)
            return analysis
        }

        Task { [weak self] in
            do {
                let analysis = try await analysisTask.value
                guard let self else {
                    return
                }
                self.analysisQueueState.finish(imported.id)
                self.syncAnalysisQueuePublishedState()
                self.applyAnalysis(analysis, persist: true)
                self.notice = "Analyzed \(imported.track.title)"
                self.drainAnalysisQueue()
            } catch {
                guard let self else {
                    return
                }
                self.analysisQueueState.finish(imported.id)
                self.syncAnalysisQueuePublishedState()
                self.notice = "Could not analyze \(imported.track.title): \(error.localizedDescription)"
                self.drainAnalysisQueue()
            }
        }
    }

    private func syncAnalysisQueuePublishedState() {
        let snapshot = analysisQueueState.snapshot
        queuedAnalysisTrackCount = snapshot.pendingCount
        runningAnalysisTrackCount = snapshot.runningCount
        analyzingTrackIds = analysisQueueState.activeIds
    }

    private func applyAnalysis(_ analysis: TrackAnalysis, persist: Bool) {
        trackAnalysesById[analysis.trackId] = analysis
        clearCurrentMixPlan()
        guard let bpm = analysis.bpm else {
            return
        }

        for index in playlist.indices where playlist[index].id == analysis.trackId {
            playlist[index].track.bpm = bpm
        }
        for index in libraryRecords.indices where libraryRecords[index].id == analysis.trackId {
            libraryRecords[index].track.bpm = bpm
            libraryRecords[index].updatedAt = timestamp()
        }
        if persist {
            persistLibraryState()
        }
    }

    private func isCurrentAnalysis(_ analysis: TrackAnalysis, for imported: ImportedTrack) -> Bool {
        guard isTrackAvailableForImmediateUse(imported) else {
            return false
        }
        guard analysis.schemaVersion == trackAnalysisSchemaVersion else {
            return false
        }
        guard let cachedRevision = analysis.fileRevision else {
            return false
        }
        guard let currentRevision = try? NativeTrackAnalyzer.currentFileRevision(for: imported.url) else {
            return true
        }
        return cachedRevision.sizeBytes == currentRevision.sizeBytes &&
            cachedRevision.mtimeMs == currentRevision.mtimeMs
    }

    private func startMixPlanSchedulerIfNeeded() {
        stopMixPlanScheduler()
        guard
            currentMixPlan != nil,
            let pair = currentMixPlanPair,
            audioEngine.isPlaybackActive,
            audioEngine.currentTrack?.id == pair.currentTrackId
        else {
            updateScheduledMixStatus()
            return
        }

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickMixPlanScheduler()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mixPlanTimer = timer
        tickMixPlanScheduler()
    }

    private func stopMixPlanScheduler() {
        mixPlanTimer?.invalidate()
        mixPlanTimer = nil
        scheduledMixCountdownSec = nil
    }

    private func tickMixPlanScheduler() {
        guard
            !isExecutingScheduledMix,
            let plan = currentMixPlan,
            let pair = currentMixPlanPair,
            audioEngine.isPlaybackActive,
            audioEngine.currentTrack?.id == pair.currentTrackId,
            let current = playlist.first(where: { $0.id == pair.currentTrackId }),
            let target = playlist.first(where: { $0.id == pair.nextTrackId })
        else {
            updateScheduledMixStatus()
            return
        }

        guard isTrackAvailableForImmediateUse(target) else {
            stopMixPlanScheduler()
            clearCurrentMixPlan()
            notice = "Scheduled mix canceled because a file is missing"
            return
        }

        let secondsUntilTransition = MixPlanScheduler.secondsUntilTransition(
            plan: plan,
            elapsedSec: audioEngine.elapsedSec
        )
        if !MixPlanScheduler.shouldStartTransition(plan: plan, elapsedSec: audioEngine.elapsedSec) {
            scheduledMixCountdownSec = secondsUntilTransition
            updateScheduledMixStatus()
            return
        }

        do {
            isExecutingScheduledMix = true
            stopMixPlanScheduler()
            try executeTransition(
                from: current,
                to: target,
                plan: plan,
                clearPlanAfterStart: true
            )
            notice = "Executing scheduled AI mix"
            isExecutingScheduledMix = false
        } catch {
            isExecutingScheduledMix = false
            stopMixPlanScheduler()
            notice = error.localizedDescription
        }
    }

    private func updateScheduledMixStatus() {
        guard let plan = currentMixPlan else {
            scheduledMixCountdownSec = nil
            if !isPlanningMix {
                plannerStatus = "No AI mix plan"
            }
            return
        }

        if audioEngine.isPlaybackActive, audioEngine.currentTrack?.id == currentMixPlanPair?.currentTrackId {
            let countdown = MixPlanScheduler.secondsUntilTransition(plan: plan, elapsedSec: audioEngine.elapsedSec)
            scheduledMixCountdownSec = countdown
            plannerStatus = "Scheduled in \(formatMixTime(countdown)) · next in \(formatMixTime(plan.nextTrackStartOffsetSec))"
        } else {
            scheduledMixCountdownSec = nil
            plannerStatus = "AI plan \(formatMixTime(plan.transitionStartSec)) -> \(formatMixTime(plan.nextTrackStartOffsetSec))"
        }
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func fileFingerprint(for imported: ImportedTrack) -> String {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: imported.url.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        let titleKey = imported.track.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let durationMs = Int((imported.track.durationSec * 1_000).rounded())
        return "\(titleKey)|\(imported.track.format.rawValue)|\(durationMs)|\(fileSize)"
    }

    private func isTrackAvailableForImmediateUse(_ imported: ImportedTrack) -> Bool {
        !imported.missing && FileManager.default.fileExists(atPath: imported.url.path)
    }

    @discardableResult
    private func markTrackMissingIfUnavailable(_ imported: ImportedTrack) -> Bool {
        if isTrackAvailableForImmediateUse(imported) {
            return true
        }

        let now = timestamp()
        for index in playlist.indices where playlist[index].id == imported.id {
            playlist[index].missing = true
            playlist[index].missingAt = playlist[index].missingAt ?? now
        }
        for index in libraryRecords.indices where libraryRecords[index].id == imported.id {
            libraryRecords[index].missing = true
            libraryRecords[index].missingAt = libraryRecords[index].missingAt ?? now
            libraryRecords[index].updatedAt = now
        }
        clearCurrentMixPlan()
        persistLibraryState()
        return false
    }

    private func selectFirstAvailableTrackIfNeeded() {
        if let selectedTrack, isTrackAvailableForImmediateUse(selectedTrack) {
            return
        }
        selectedTrackID = playlist.first(where: isTrackAvailableForImmediateUse)?.id ?? playlist.first?.id
    }

    private func clearCurrentMixPlan() {
        stopMixPlanScheduler()
        currentMixPlan = nil
        currentMixPlanPair = nil
        scheduledMixCountdownSec = nil
        if !isPlanningMix {
            plannerStatus = "No AI mix plan"
        }
    }
}

struct PlannedMixPair: Equatable, Sendable {
    var currentTrackId: String
    var nextTrackId: String
}

private func formatMixTime(_ seconds: Double) -> String {
    guard seconds.isFinite else {
        return "--"
    }
    let safeSeconds = max(0, Int(seconds.rounded(.down)))
    return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
}

private enum NativePlaybackError: LocalizedError {
    case trackUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .trackUnavailable(let title):
            return "\(title) is missing. Rescan or relink the source folder."
        }
    }
}
