import BeatDropperApplication
import BeatDropperPlatform
import Combine
import Foundation

@MainActor
final class BeatDropperAppModel: ObservableObject {
    let shell: AppShellFeature
    let playing: PlayingFeature
    let library: LibraryFeature
    let creative: CreativeFeature
    let mixPlanning: MixPlanningFeature
    let mixReview: MixReviewFeature
    let navigation: AppNavigation
    let libraryActions: LibraryFeatureController
    let creativeActions: CreativeFeatureController
    let playingActions: PlayingFeatureController
    let planningActions: MixPlanningFeatureController
    let reviewActions: MixReviewFeatureController
    let settingsActions: SettingsFeatureController

    private var featureCancellables: Set<AnyCancellable> = []

    init(
        audioPlayback: any AudioPlayback = NativeAudioEngine(),
        store: any LibraryRepository = NativeLibraryStore.applicationSupport(),
        settingsStore: any SettingsRepository = NativeSettingsStore.applicationSupport(),
        analysisStore: any TrackAnalysisRepository = NativeTrackAnalysisStore.applicationSupport(),
        mixReviewArtifactStore: any MixReviewRepository = MixReviewArtifactStore.applicationSupport(),
        mixPlanner: any MixPlanning = NativeMixPlannerBridge(),
        trackImporter: any TrackImporting = NativeTrackImporter(),
        trackAnalyzer: any TrackAnalyzing = NativeTrackAnalysisService(),
        clock: any AppClock = SystemAppClock(),
        scheduler: any AppScheduling = RunLoopAppScheduler()
    ) {
        let shell = AppShellFeature()
        let playing = PlayingFeature(audioPlayback: audioPlayback)
        let library = LibraryFeature(trackAvailability: trackImporter)
        let creative = CreativeFeature()
        self.shell = shell
        self.playing = playing
        self.library = library
        self.creative = creative
        let mixPlanning = MixPlanningFeature()
        let mixReview = MixReviewFeature()
        self.mixPlanning = mixPlanning
        self.mixReview = mixReview
        self.navigation = AppNavigation()
        let libraryActions = LibraryFeatureController(
            library: library,
            creative: creative,
            playing: playing,
            shell: shell,
            store: store,
            analysisStore: analysisStore,
            trackImporter: trackImporter,
            trackAnalyzer: trackAnalyzer,
            clock: clock
        )
        self.libraryActions = libraryActions
        let playingActions = PlayingFeatureController(
            playing: playing,
            library: library,
            libraryActions: libraryActions,
            shell: shell
        )
        self.playingActions = playingActions
        let planningActions = MixPlanningFeatureController(
            feature: mixPlanning,
            playing: playing,
            library: library,
            libraryActions: libraryActions,
            shell: shell,
            mixPlanner: mixPlanner,
            clock: clock,
            scheduler: scheduler,
            transitionExecutor: playingActions
        )
        self.planningActions = planningActions
        self.creativeActions = CreativeFeatureController(
            creative: creative,
            library: library,
            playing: playing,
            libraryActions: libraryActions,
            shell: shell,
            clock: clock
        )
        self.settingsActions = SettingsFeatureController(
            shell: shell,
            playing: playing,
            repository: settingsStore
        )
        self.reviewActions = MixReviewFeatureController(
            feature: mixReview,
            library: library,
            planning: mixPlanning,
            shell: shell,
            settingsActions: settingsActions,
            artifactStore: mixReviewArtifactStore,
            fileAvailability: trackImporter,
            clock: clock
        )
        observeFeatureChanges()
        settingsActions.setPlanningInvalidation { [weak planningActions] in
            planningActions?.clearCurrentMixPlan()
            planningActions?.requestAIMixPlanIfReady()
        }
        libraryActions.configureCoordination(
            clearMixPlan: { [weak planningActions] in planningActions?.clearCurrentMixPlan() },
            stopMixPlanScheduler: { [weak planningActions] in planningActions?.stopMixPlanScheduler() },
            synchronizeAIMix: { [weak planningActions] in planningActions?.syncAIMixAfterPlaylistMutation() },
            requestAIMixPlan: { [weak planningActions] in planningActions?.requestAIMixPlanIfReady() },
            currentMixPlanPair: { [weak mixPlanning] in mixPlanning?.currentPair },
            setAIMixEnabled: { [weak mixPlanning] enabled in mixPlanning?.isEnabled = enabled }
        )
        playingActions.configurePlanningCoordination(
            currentMixPlan: { [weak mixPlanning] in mixPlanning?.currentPlan },
            currentMixPlanPair: { [weak mixPlanning] in mixPlanning?.currentPair },
            scheduleManualMixPlan: { [weak planningActions] plan, pair in
                planningActions?.scheduleManualMixPlan(plan, pair: pair)
            },
            clearMixPlan: { [weak planningActions] in planningActions?.clearCurrentMixPlan() },
            requestMixPlan: { [weak planningActions] in planningActions?.requestAIMixPlanIfReady() },
            startMixPlanScheduler: { [weak planningActions] in planningActions?.startMixPlanSchedulerIfNeeded() },
            stopMixPlanScheduler: { [weak planningActions] in planningActions?.stopMixPlanScheduler() }
        )
        planningActions.configureReviewEventRecording { [weak reviewActions] event in
            reviewActions?.record(event)
        }
        settingsActions.restore()
        libraryActions.restoreLibraryState()
        reviewActions.restoreMixReviewArtifacts()
    }

    private func observeFeatureChanges() {
        [
            playing.objectWillChange.eraseToAnyPublisher(),
            library.objectWillChange.eraseToAnyPublisher(),
            creative.objectWillChange.eraseToAnyPublisher(),
            mixPlanning.objectWillChange.eraseToAnyPublisher(),
            mixReview.objectWillChange.eraseToAnyPublisher(),
            navigation.objectWillChange.eraseToAnyPublisher(),
            shell.objectWillChange.eraseToAnyPublisher()
        ]
        .forEach { publisher in
            publisher.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &featureCancellables)
        }
    }

}
