import BeatDropperCore

extension BeatDropperAppModel {
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
}
