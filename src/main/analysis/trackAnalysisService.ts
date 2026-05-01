import { parseFile } from 'music-metadata';
import { TrackAnalysis, sanitizeTrackAnalysis } from '../../shared/analysis';

interface TrackAnalysisServiceDeps {
  store: {
    read(trackId: string): Promise<TrackAnalysis | null>;
    write(analysis: TrackAnalysis): Promise<TrackAnalysis>;
  };
  resolveTrackPath(trackId: string): string;
}

export class TrackAnalysisService {
  private readonly store: TrackAnalysisServiceDeps['store'];
  private readonly resolveTrackPath: TrackAnalysisServiceDeps['resolveTrackPath'];

  constructor(deps: TrackAnalysisServiceDeps) {
    this.store = deps.store;
    this.resolveTrackPath = deps.resolveTrackPath;
  }

  async getTrackAnalysis(trackId: string): Promise<TrackAnalysis | null> {
    const cached = await this.store.read(trackId);
    if (cached) {
      return cached;
    }

    const filePath = this.resolveTrackPath(trackId);
    const metadata = await parseFile(filePath, { duration: true });
    const durationSec =
      typeof metadata.format.duration === 'number' && Number.isFinite(metadata.format.duration)
        ? metadata.format.duration
        : null;
    const metadataBpm =
      typeof metadata.common.bpm === 'number' && Number.isFinite(metadata.common.bpm)
        ? metadata.common.bpm
        : null;
    const beatIntervalSec = metadataBpm && metadataBpm > 0 ? 60 / metadataBpm : null;
    const beatGridSec =
      beatIntervalSec && durationSec
        ? Array.from(
            { length: Math.min(2200, Math.floor(durationSec / beatIntervalSec) + 1) },
            (_, index) => index * beatIntervalSec
          )
        : [];
    const downbeatsSec = beatGridSec.filter((_beat, index) => index % 4 === 0);
    const barGrid = downbeatsSec.map((startSec, index) => ({
      index,
      startSec,
      beatIndex: index * 4
    }));
    const phraseMarkers = barGrid
      .filter((_bar, index) => index % 8 === 0)
      .map((bar, index) => ({
        index,
        startSec: bar.startSec,
        bars: 8,
        confidence: metadataBpm !== null ? 0.55 : 0.1
      }));
    const outroCueSec =
      durationSec !== null ? Math.max(0, durationSec - Math.min(16, durationSec * 0.12)) : null;

    const analysis = sanitizeTrackAnalysis(trackId, {
      generatedAt: new Date().toISOString(),
      source: metadataBpm !== null ? 'metadata' : 'derived',
      bpm: metadataBpm,
      bpmConfidence: metadataBpm !== null ? 0.7 : 0,
      introCueSec: 0,
      outroCueSec,
      analysisConfidence: metadataBpm !== null ? 0.7 : 0.2,
      beatGridSec,
      downbeatsSec,
      barGrid,
      phraseMarkers,
      energyProfile: [],
      waveformPeaks: [],
      cueCandidates: [
        {
          id: 'intro',
          type: 'intro',
          startSec: 0,
          endSec: Math.min(durationSec ?? 0, 8),
          confidence: 0.4,
          label: 'Intro'
        },
        ...(outroCueSec !== null && durationSec !== null
          ? [
              {
                id: 'outro',
                type: 'outro' as const,
                startSec: outroCueSec,
                endSec: durationSec,
                confidence: 0.42,
                label: 'Outro mix-out'
              }
            ]
          : [])
      ],
      analysisWarnings: [
        ...(metadataBpm === null ? ['bpm_unavailable' as const] : []),
        ...(metadataBpm !== null ? ['beat_grid_estimated' as const] : []),
        ...(durationSec !== null && durationSec < 30 ? ['short_track' as const] : [])
      ]
    });

    return this.store.write(analysis);
  }

  async saveTrackAnalysis(trackId: string, candidate: Partial<TrackAnalysis>): Promise<TrackAnalysis> {
    return this.store.write(sanitizeTrackAnalysis(trackId, candidate));
  }
}
