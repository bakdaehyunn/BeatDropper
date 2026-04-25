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

    const analysis = sanitizeTrackAnalysis(trackId, {
      generatedAt: new Date().toISOString(),
      source: metadataBpm !== null ? 'metadata' : 'derived',
      bpm: metadataBpm,
      introCueSec: 0,
      outroCueSec:
        durationSec !== null ? Math.max(0, durationSec - Math.min(16, durationSec * 0.12)) : null,
      analysisConfidence: metadataBpm !== null ? 0.7 : 0.2,
      beatGridSec: [],
      downbeatsSec: [],
      energyProfile: []
    });

    return this.store.write(analysis);
  }
}
