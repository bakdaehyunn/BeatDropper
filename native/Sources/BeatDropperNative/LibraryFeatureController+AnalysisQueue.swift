import BeatDropperApplication
import Foundation

extension LibraryFeatureController {
    func refreshAnalyses(for imported: [ImportedTrack]) {
        let tracksNeedingAnalysis = imported.filter { track in
            guard library.isAvailable(track) else {
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

    func enqueueAnalyses(for imported: [ImportedTrack]) {
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

    func drainAnalysisQueue() {
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

    func startAnalysis(for imported: ImportedTrack) {
        let analyzer = trackAnalyzer
        let repository = analysisStore
        let analysisTask = Task.detached(priority: .utility) {
            let analysis = try await analyzer.analyze(track: imported.track, url: imported.url)
            try repository.write(analysis)
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
                self.requestAIMixPlanIfReady()
            } catch {
                guard let self else {
                    return
                }
                self.analysisQueueState.finish(imported.id)
                self.syncAnalysisQueuePublishedState()
                self.notice = "Could not analyze \(imported.track.title): \(error.localizedDescription)"
                self.drainAnalysisQueue()
                self.requestAIMixPlanIfReady()
            }
        }
    }

    func syncAnalysisQueuePublishedState() {
        let snapshot = analysisQueueState.snapshot
        queuedAnalysisTrackCount = snapshot.pendingCount
        runningAnalysisTrackCount = snapshot.runningCount
        analyzingTrackIds = analysisQueueState.activeIds
    }

    func applyAnalysis(_ analysis: TrackAnalysis, persist: Bool) {
        trackAnalysesById[analysis.trackId] = analysis
        if currentMixPlanPair?.currentTrackId == analysis.trackId ||
            currentMixPlanPair?.nextTrackId == analysis.trackId {
            clearCurrentMixPlan()
        }
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

    func isCurrentAnalysis(_ analysis: TrackAnalysis, for imported: ImportedTrack) -> Bool {
        guard library.isAvailable(imported) else {
            return false
        }
        guard analysis.schemaVersion == trackAnalysisSchemaVersion else {
            return false
        }
        guard let cachedRevision = analysis.fileRevision else {
            return false
        }
        guard let currentRevision = try? trackAnalyzer.currentFileRevision(for: imported.url) else {
            return true
        }
        return cachedRevision.sizeBytes == currentRevision.sizeBytes &&
            cachedRevision.mtimeMs == currentRevision.mtimeMs
    }
}
