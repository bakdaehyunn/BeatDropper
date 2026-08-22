import BeatDropperApplication
import BeatDropperPlatform
import Foundation

extension NativeLibraryStore: LibraryRepository {}
extension NativeSettingsStore: SettingsRepository {}
extension NativeTrackAnalysisStore: TrackAnalysisRepository {}
extension MixReviewArtifactStore: MixReviewRepository {}
extension NativeMixPlannerBridge: MixPlanning {}
extension NativeAudioEngine: AudioPlayback, AudioPlaybackAutomation {}
