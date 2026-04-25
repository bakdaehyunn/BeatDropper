import { stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { parseFile } from 'music-metadata';
import { AudioFormat, Track } from '../shared/types';

export interface LoadedTrackEntry {
  track: Track;
  filePath: string;
}

export interface InternalTrackLoadResult {
  tracks: LoadedTrackEntry[];
  skipped: string[];
}

const supportedExtensions = new Map<string, AudioFormat>([
  ['.mp3', 'mp3'],
  ['.wav', 'wav']
]);

const resolveFormat = (filePath: string): AudioFormat | null => {
  const ext = path.extname(filePath).toLowerCase();
  return supportedExtensions.get(ext) ?? null;
};

const TRACK_PARSE_CONCURRENCY = 4;

const buildTrackId = async (filePath: string): Promise<string> => {
  const fileStats = await stat(filePath);
  return createHash('sha1')
    .update(filePath)
    .update(String(fileStats.size))
    .update(String(fileStats.mtimeMs))
    .digest('hex');
};

const parseTrackFromPath = async (
  filePath: string
): Promise<{ track?: LoadedTrackEntry; skip?: string }> => {
  const format = resolveFormat(filePath);
  if (!format) {
    return { skip: `${path.basename(filePath)}: unsupported format` };
  }

  try {
    const metadata = await parseFile(filePath, { duration: true });
    const durationSec = metadata.format.duration;
    if (!durationSec || durationSec <= 0) {
      return { skip: `${path.basename(filePath)}: missing duration metadata` };
    }

    const title = metadata.common.title?.trim() || path.basename(filePath);
    const id = await buildTrackId(filePath);

    return {
      track: {
        filePath,
        track: {
          id,
          title,
          durationSec,
          format,
          bpm:
            typeof metadata.common.bpm === 'number' && Number.isFinite(metadata.common.bpm)
              ? metadata.common.bpm
              : null
        }
      }
    };
  } catch {
    return { skip: `${path.basename(filePath)}: unreadable or corrupted` };
  }
};

export const loadTracksFromPaths = async (filePaths: string[]): Promise<InternalTrackLoadResult> => {
  if (filePaths.length === 0) {
    return { tracks: [], skipped: [] };
  }

  const results: Array<{ track?: LoadedTrackEntry; skip?: string }> = new Array(filePaths.length);
  const workerCount = Math.max(1, Math.min(TRACK_PARSE_CONCURRENCY, filePaths.length));
  let cursor = 0;

  const workers = Array.from({ length: workerCount }, async () => {
    while (true) {
      const current = cursor;
      cursor += 1;
      if (current >= filePaths.length) {
        break;
      }
      results[current] = await parseTrackFromPath(filePaths[current]);
    }
  });

  await Promise.all(workers);

  const tracks: LoadedTrackEntry[] = [];
  const skipped: string[] = [];
  for (const result of results) {
    if (!result) {
      continue;
    }
    if (result.track) {
      tracks.push(result.track);
    } else if (result.skip) {
      skipped.push(result.skip);
    }
  }
  return { tracks, skipped };
};
