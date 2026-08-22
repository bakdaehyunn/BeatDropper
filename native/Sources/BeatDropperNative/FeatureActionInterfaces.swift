import BeatDropperApplication
import Foundation

@MainActor
protocol LibraryFeatureActionHandling: AnyObject {
    func newSet()
    func addTracks()
    func importFolder()
    func openDroppedItemsAsSet(_ urls: [URL])
    func selectPlaylistTrack(_ trackID: ImportedTrack.ID?)
    func selectLibraryTrack(_ trackID: ImportedTrack.ID?)
    func selectUserPlaylist(_ id: String)
    func addSelectedLibraryTrackToPlaylist()
    func moveSelectedTrack(offset: Int)
    func removeSelectedTrack()
    func clearPlaylist()
    func saveCurrentSet()
    func loadSelectedSavedSet()
    func renameSelectedSavedSet()
    func deleteSelectedSavedSet()
    func rescanLibraryFolders()
    func relinkSelectedTrack()
    func relinkMissingSourceFolder(_ folder: NativeLibrarySourceFolder)
}

@MainActor
protocol CreativeFeatureActionHandling: AnyObject {
    func previewCreativeTrack(at timeSec: Double)
    func toggleCreativePreviewPlayback()
    func seekCreativePreview(by deltaSec: Double)
    func stopCreativePreview()
    func tapBPMForCreativeTrack()
    func applyTappedBPMToCreativeTrack()
    func setCreativeBPMOverride(_ bpm: Double)
    func clearCreativeBPMOverride()
    func addCreativeHotCue(kind: TrackPreparationCueKind)
    func removeCreativeHotCue(_ cue: TrackPreparationCue)
}

@MainActor
protocol PlayingFeatureActionHandling: AnyObject {
    func playPause()
    func playPreviousTrack()
    func playNextTrack()
}

@MainActor
protocol MixPlanningFeatureActionHandling: AnyObject {
    func setAIMixEnabled(_ enabled: Bool)
    func cancelMixPlan()
}

@MainActor
protocol SettingsFeatureActionHandling: AnyObject {
    func updateFadeDuration(_ value: Double)
    func updateMasterGain(_ value: Double)
    func updateAIDJMode(_ mode: AIDJMode)
}

@MainActor
protocol MixReviewFeatureActionHandling: AnyObject {
    var canExportMixReviewNotes: Bool { get }
    var canPreviewSelectedPairMixReviewNotes: Bool { get }
    var canFilterImportedMixReviewArtifactsBySelectedPair: Bool { get }
    var visibleImportedMixReviewArtifacts: [ImportedMixReviewArtifact] { get }
    var importedMixReviewArtifactFilterSummary: String { get }
    var canCompareImportedMixReviewArtifacts: Bool { get }

    func canSelectImportedMixReviewArtifactForComparison(_ artifact: ImportedMixReviewArtifact) -> Bool
    func isImportedMixReviewArtifactSelectedForComparison(_ artifactID: ImportedMixReviewArtifact.ID) -> Bool
    func toggleImportedMixReviewArtifactComparisonSelection(_ artifactID: ImportedMixReviewArtifact.ID)
    func clearImportedMixReviewArtifactComparisonSelection()
    func buildImportedMixReviewArtifactComparison() -> ImportedMixReviewArtifactComparison?
    func copyImportedMixReviewArtifactComparisonSummary(_ comparison: ImportedMixReviewArtifactComparison)
    func exportImportedMixReviewArtifactComparisonSummary(_ comparison: ImportedMixReviewArtifactComparison)
    func buildMixReviewExportPreview(
        format: MixReviewExportFileFormat,
        scope: MixReviewExportPreviewScope
    ) -> MixReviewExportPreview?
    func copyMixReviewExportPreviewToClipboard(_ preview: MixReviewExportPreview)
    func exportMixReviewPreview(_ preview: MixReviewExportPreview)
    func importMixReviewArtifact()
    func importedMixReviewArtifactAnnotation(for artifactID: ImportedMixReviewArtifact.ID) -> String
    func updateImportedMixReviewArtifactAnnotation(for artifactID: ImportedMixReviewArtifact.ID, annotation: String)
}

extension MixReviewFeatureActionHandling {
    func buildMixReviewExportPreview(format: MixReviewExportFileFormat) -> MixReviewExportPreview? {
        buildMixReviewExportPreview(format: format, scope: .allRecent)
    }
}
