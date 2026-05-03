import { TrackAnalysis } from '../../shared/analysis';
import { Track } from '../../shared/types';

export const shouldBuildDetailedTrackAnalysis = (
  analysis: TrackAnalysis | null | undefined
): boolean => {
  if (!analysis) {
    return true;
  }

  return (
    analysis.waveformPeaks.length === 0 ||
    analysis.waveformDetail.length === 0 ||
    analysis.analysisWarnings.includes('analysis_upgrade_available')
  );
};

export const pickNextTrackForDetailedAnalysis = (
  tracks: Track[],
  analysisByTrackId: Record<string, TrackAnalysis>,
  analyzingTrackIds: string[],
  failedTrackIds: ReadonlySet<string>
): Track | null => {
  const analyzingIds = new Set(analyzingTrackIds);
  return (
    tracks.find((track) => {
      if (analyzingIds.has(track.id) || failedTrackIds.has(track.id)) {
        return false;
      }
      return shouldBuildDetailedTrackAnalysis(analysisByTrackId[track.id]);
    }) ?? null
  );
};

export const preferDetailedTrackAnalysis = (
  current: TrackAnalysis | null | undefined,
  incoming: TrackAnalysis
): TrackAnalysis => {
  if (
    current &&
    current.waveformDetail.length > 0 &&
    incoming.waveformDetail.length === 0
  ) {
    return current;
  }
  return incoming;
};
