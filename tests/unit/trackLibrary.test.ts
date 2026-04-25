import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const mockParseFile = vi.fn();

vi.mock('music-metadata', () => {
  return {
    parseFile: mockParseFile
  };
});

const waitTicks = async (ticks: number): Promise<void> => {
  for (let index = 0; index < ticks; index += 1) {
    await Promise.resolve();
  }
};

describe('loadTracksFromPaths', () => {
  beforeEach(() => {
    mockParseFile.mockReset();
  });

  it('keeps input order while parsing with bounded concurrency', async () => {
    const { loadTracksFromPaths } = await import('../../src/main/trackLibrary');
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-tracklib-'));
    const filePaths = [
      path.join(tempRoot, 'alpha.mp3'),
      path.join(tempRoot, 'bravo.wav'),
      path.join(tempRoot, 'charlie.mp3'),
      path.join(tempRoot, 'delta.wav'),
      path.join(tempRoot, 'echo.mp3')
    ];

    for (const filePath of filePaths) {
      await writeFile(filePath, 'x');
    }

    const delayByFile = new Map<string, number>([
      [filePaths[0], 9],
      [filePaths[1], 2],
      [filePaths[2], 7],
      [filePaths[3], 1],
      [filePaths[4], 5]
    ]);
    let active = 0;
    let maxActive = 0;

    try {
      mockParseFile.mockImplementation(async (filePath: string) => {
        active += 1;
        maxActive = Math.max(maxActive, active);
        await waitTicks(delayByFile.get(filePath) ?? 0);
        active -= 1;
        return {
          format: { duration: 120 },
          common: { title: path.basename(filePath).replace(/\.(mp3|wav)$/i, '') }
        };
      });

      const result = await loadTracksFromPaths(filePaths);
      const loadedNames = result.tracks.map((entry) => entry.track.title);

      expect(mockParseFile).toHaveBeenCalledTimes(5);
      expect(result.skipped).toEqual([]);
      expect(loadedNames).toEqual(['alpha', 'bravo', 'charlie', 'delta', 'echo']);
      expect(maxActive).toBeGreaterThan(1);
      expect(maxActive).toBeLessThanOrEqual(4);
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('returns skipped reasons for unsupported and invalid files', async () => {
    const { loadTracksFromPaths } = await import('../../src/main/trackLibrary');
    const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-tracklib-'));
    const filePaths = [
      path.join(tempRoot, 'unsupported.flac'),
      path.join(tempRoot, 'missing-meta.wav'),
      path.join(tempRoot, 'bad.mp3')
    ];

    for (const filePath of filePaths) {
      await writeFile(filePath, 'x');
    }

    try {
      mockParseFile.mockImplementation(async (filePath: string) => {
        if (filePath.endsWith('bad.mp3')) {
          throw new Error('broken');
        }
        return {
          format: { duration: 0 },
          common: {}
        };
      });

      const result = await loadTracksFromPaths(filePaths);
      expect(result.tracks).toEqual([]);
      expect(result.skipped).toEqual([
        'unsupported.flac: unsupported format',
        'missing-meta.wav: missing duration metadata',
        'bad.mp3: unreadable or corrupted'
      ]);
    } finally {
      await rm(tempRoot, { recursive: true, force: true });
    }
  });
});
