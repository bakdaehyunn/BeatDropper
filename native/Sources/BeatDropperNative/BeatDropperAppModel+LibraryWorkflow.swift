import AppKit
import BeatDropperCore
import Foundation

extension BeatDropperAppModel {
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
        syncAIMixAfterPlaylistMutation()

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
            syncAIMixAfterPlaylistMutation()
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
            syncAIMixAfterPlaylistMutation()
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
            syncAIMixAfterPlaylistMutation()
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
}
