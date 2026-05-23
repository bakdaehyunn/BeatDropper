import { mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { TrackAnalysisService } from '../../src/main/analysis/trackAnalysisService';
import { TrackFileRevision, sanitizeTrackAnalysis } from '../../src/shared/analysis';

const mockParseFile = vi.hoisted(() => vi.fn());

vi.mock('music-metadata', () => {
  return {
    parseFile: mockParseFile
  };
});

const readRevision = async (filePath: string): Promise<TrackFileRevision> => {
  const fileStats = await stat(filePath);
  return {
    sizeBytes: fileStats.size,
    mtimeMs: fileStats.mtimeMs
  };
};

describe('TrackAnalysisService', () => {
  beforeEach(() => {
    mockParseFile.mockReset();
  });

  it('returns cached analysis when the stored file revision still matches', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-analysis-service-'));
    const filePath = path.join(tempRoot, 'track.mp3');

    try {
      await writeFile(filePath, 'audio');
      const fileRevision = await readRevision(filePath);
      const cached = sanitizeTrackAnalysis('track-1', {
        fileRevision,
        source: 'derived',
        bpm: 124,
        bpmConfidence: 0.8,
        analysisConfidence: 0.8,
        beatGridSec: [0, 0.5],
        downbeatsSec: [0],
        barGrid: [{ index: 0, startSec: 0, beatIndex: 0 }]
      });
      const store = {
        read: vi.fn().mockResolvedValue(cached),
        write: vi.fn()
      };
      const service = new TrackAnalysisService({
        store,
        resolveTrackPath: () => filePath
      });

      const result = await service.getTrackAnalysis('track-1');

      expect(result).toBe(cached);
      expect(mockParseFile).not.toHaveBeenCalled();
      expect(store.write).not.toHaveBeenCalled();
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('regenerates metadata analysis when the file revision has changed', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-analysis-service-'));
    const filePath = path.join(tempRoot, 'track.mp3');

    try {
      await writeFile(filePath, 'current audio bytes');
      const cached = sanitizeTrackAnalysis('track-1', {
        fileRevision: {
          sizeBytes: 1,
          mtimeMs: 1
        },
        source: 'derived',
        bpm: 118,
        bpmConfidence: 0.8,
        analysisConfidence: 0.8
      });
      const store = {
        read: vi.fn().mockResolvedValue(cached),
        write: vi.fn(async (analysis) => analysis)
      };
      const service = new TrackAnalysisService({
        store,
        resolveTrackPath: () => filePath
      });

      mockParseFile.mockResolvedValue({
        format: { duration: 180 },
        common: { bpm: 128 }
      });

      const result = await service.getTrackAnalysis('track-1');
      const currentRevision = await readRevision(filePath);

      expect(mockParseFile).toHaveBeenCalledWith(filePath, { duration: true });
      expect(store.write).toHaveBeenCalledWith(
        expect.objectContaining({
          trackId: 'track-1',
          bpm: 128,
          fileRevision: currentRevision
        })
      );
      expect(result).toMatchObject({
        trackId: 'track-1',
        bpm: 128,
        fileRevision: currentRevision
      });
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('keeps legacy cached analysis that has no file revision yet', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-analysis-service-'));
    const filePath = path.join(tempRoot, 'track.mp3');

    try {
      await writeFile(filePath, 'audio');
      const legacyCached = sanitizeTrackAnalysis('track-1', {
        source: 'derived',
        bpm: 122,
        bpmConfidence: 0.8,
        analysisConfidence: 0.8
      });
      const store = {
        read: vi.fn().mockResolvedValue(legacyCached),
        write: vi.fn()
      };
      const service = new TrackAnalysisService({
        store,
        resolveTrackPath: () => filePath
      });

      const result = await service.getTrackAnalysis('track-1');

      expect(result).toBe(legacyCached);
      expect(result?.fileRevision).toBeNull();
      expect(mockParseFile).not.toHaveBeenCalled();
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('attaches the current file revision when saving renderer analysis', async () => {
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-analysis-service-'));
    const filePath = path.join(tempRoot, 'track.mp3');

    try {
      await writeFile(filePath, 'audio');
      const store = {
        read: vi.fn(),
        write: vi.fn(async (analysis) => analysis)
      };
      const service = new TrackAnalysisService({
        store,
        resolveTrackPath: () => filePath
      });

      const result = await service.saveTrackAnalysis('track-1', {
        source: 'derived',
        bpm: 126,
        bpmConfidence: 0.9,
        analysisConfidence: 0.9
      });
      const currentRevision = await readRevision(filePath);

      expect(store.write).toHaveBeenCalledWith(
        expect.objectContaining({
          trackId: 'track-1',
          bpm: 126,
          fileRevision: currentRevision
        })
      );
      expect(result.fileRevision).toEqual(currentRevision);
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });
});
