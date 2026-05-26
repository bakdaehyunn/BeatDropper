import BeatDropperCore
import Foundation
import Testing

struct ModelParityTests {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    @Test func trackDecodesFromCurrentTypeScriptShape() throws {
        let json = """
        {
          "id": "track-1",
          "title": "DREAMSTATE.wav",
          "durationSec": 204,
          "format": "wav",
          "bpm": 148
        }
        """

        let track = try decoder.decode(Track.self, from: Data(json.utf8))

        #expect(track.id == "track-1")
        #expect(track.title == "DREAMSTATE.wav")
        #expect(track.durationSec == 204)
        #expect(track.format == .wav)
        #expect(track.bpm == 148)
    }

    @Test func trackAnalysisDecodesCurrentSchemaVersion() throws {
        let json = """
        {
          "schemaVersion": 5,
          "trackId": "track-1",
          "generatedAt": "2026-05-25T00:00:00.000Z",
          "source": "derived",
          "fileRevision": { "sizeBytes": 1024, "mtimeMs": 1770000000000 },
          "bpm": 148,
          "bpmConfidence": 0.91,
          "beatGridSec": [0, 0.405],
          "downbeatsSec": [0],
          "barGrid": [{ "index": 0, "startSec": 0, "beatIndex": 0 }],
          "phraseMarkers": [{ "index": 0, "startSec": 0, "bars": 8, "confidence": 0.8 }],
          "introCueSec": 0,
          "outroCueSec": 188,
          "energyProfile": [0.2, 0.5, 0.7],
          "waveformPeaks": [{ "timeSec": 0, "peak": 0.8, "rms": 0.4 }],
          "waveformDetail": [{ "timeSec": 0, "peak": 0.8, "rms": 0.4, "min": -0.7, "max": 0.8 }],
          "spectralBands": [{ "timeSec": 0, "low": 0.7, "mid": 0.4, "high": 0.2 }],
          "transientMarkers": [{ "index": 0, "timeSec": 0.405, "strength": 0.82 }],
          "cueCandidates": [
            {
              "id": "first-downbeat-0",
              "type": "first_downbeat",
              "startSec": 0,
              "endSec": 8,
              "confidence": 0.88,
              "label": "First downbeat"
            }
          ],
          "analysisConfidence": 0.86,
          "analysisQuality": {
            "waveformDetail": 0.9,
            "spectralBands": 0.82,
            "transientMarkers": 0.7,
            "beatGrid": 0.84
          },
          "analysisWarnings": ["beat_grid_estimated"]
        }
        """

        let analysis = try decoder.decode(TrackAnalysis.self, from: Data(json.utf8))

        #expect(analysis.schemaVersion == trackAnalysisSchemaVersion)
        #expect(analysis.trackId == "track-1")
        #expect(analysis.source == .derived)
        #expect(analysis.cueCandidates.first?.type == .firstDownbeat)
        #expect(analysis.analysisWarnings == [.beatGridEstimated])
        #expect(analysis.analysisQuality.spectralBands == 0.82)
    }

    @Test func plannerResponseRoundTripsCurrentMixPlanShape() throws {
        let response = PlannerResponse(
            mixPlan: MixPlan(
                transitionStartSec: 144,
                transitionEndSec: 152,
                nextTrackStartOffsetSec: 25,
                style: .smoothBlend,
                confidence: 0.87,
                reasoningSummary: "bar aligned",
                tempoSync: MixTempoSyncPlan(enabled: true, targetRate: 1.02),
                candidateId: "candidate-1",
                currentBarIndex: 89,
                nextBarIndex: 17,
                phraseAlignment: .aligned,
                energyStrategy: .lift,
                evidence: ["bar 89 -> 17", "phrase aligned"]
            ),
            error: nil
        )

        let encoded = try encoder.encode(response)
        let decoded = try decoder.decode(PlannerResponse.self, from: encoded)

        #expect(decoded.schemaVersion == plannerSchemaVersion)
        #expect(decoded.mixPlan?.style == .smoothBlend)
        #expect(decoded.mixPlan?.tempoSync.targetRate == 1.02)
        #expect(decoded.mixPlan?.phraseAlignment == .aligned)
        #expect(decoded.mixPlan?.energyStrategy == .lift)
        #expect(decoded.mixPlan?.evidence.count == 2)
    }
}
