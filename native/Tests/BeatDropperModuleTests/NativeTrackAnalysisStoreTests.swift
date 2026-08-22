import BeatDropperDomain
import BeatDropperDSP
import BeatDropperLibrary
import BeatDropperPlanning
import BeatDropperPlatform
import BeatDropperReview
import BeatDropperTestSupport
import Foundation
import Testing

struct NativeTrackAnalysisStoreTests {
    @Test func savesAndLoadsAnalysisForTrackIdsThatNeedPathEncoding() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = NativeTrackAnalysisStore(rootURL: rootURL)
        let analysis = minimalAnalysis(trackId: "folder/track #1.wav")

        try store.write(analysis)
        let loaded = try store.read(trackId: analysis.trackId)

        #expect(loaded?.trackId == analysis.trackId)
        #expect(loaded?.schemaVersion == trackAnalysisSchemaVersion)
    }

    @Test func staleSchemaAnalysisReadsAsMissing() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = NativeTrackAnalysisStore(rootURL: rootURL)
        var analysis = minimalAnalysis(trackId: "track-1")
        analysis.schemaVersion = trackAnalysisSchemaVersion - 1

        try store.write(analysis)

        #expect(try store.read(trackId: "track-1") == nil)
    }

    private func minimalAnalysis(trackId: String) -> TrackAnalysis {
        TrackAnalysis(
            trackId: trackId,
            generatedAt: "2026-05-25T00:00:00Z",
            source: .derived,
            bpm: nil,
            bpmConfidence: 0,
            beatGridSec: [],
            downbeatsSec: [],
            barGrid: [],
            phraseMarkers: [],
            introCueSec: 0,
            outroCueSec: nil,
            energyProfile: [],
            waveformPeaks: [],
            waveformDetail: [],
            spectralBands: [],
            transientMarkers: [],
            cueCandidates: [],
            analysisConfidence: 0,
            analysisQuality: AnalysisQuality(
                waveformDetail: 0,
                spectralBands: 0,
                transientMarkers: 0,
                beatGrid: 0
            ),
            analysisWarnings: [.bpmUnavailable]
        )
    }
}
