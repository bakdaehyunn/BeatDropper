import { app } from 'electron';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { TrackAnalysis, sanitizeTrackAnalysis } from '../../shared/analysis';

export class TrackAnalysisStore {
  private readonly rootDir: string;

  constructor(rootDir = path.join(app.getPath('userData'), 'track-analysis-cache')) {
    this.rootDir = rootDir;
  }

  async read(trackId: string): Promise<TrackAnalysis | null> {
    try {
      const raw = await readFile(this.resolvePath(trackId), 'utf8');
      const parsed = JSON.parse(raw) as Partial<TrackAnalysis>;
      return sanitizeTrackAnalysis(trackId, parsed);
    } catch {
      return null;
    }
  }

  async write(analysis: TrackAnalysis): Promise<TrackAnalysis> {
    const next = sanitizeTrackAnalysis(analysis.trackId, analysis);
    const filePath = this.resolvePath(analysis.trackId);
    await mkdir(path.dirname(filePath), { recursive: true });
    await writeFile(filePath, JSON.stringify(next, null, 2), 'utf8');
    return next;
  }

  private resolvePath(trackId: string): string {
    return path.join(this.rootDir, `${encodeURIComponent(trackId)}.json`);
  }
}
