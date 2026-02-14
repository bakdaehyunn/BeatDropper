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

const buildTrackId = async (filePath: string): Promise<string> => {
  const fileStats = await stat(filePath);
  return createHash('sha1')
    .update(filePath)
    .update(String(fileStats.size))
    .update(String(fileStats.mtimeMs))
    .digest('hex');
};

export const loadTracksFromPaths = async (
  filePaths: string[]
): Promise<InternalTrackLoadResult> => {
  const tracks: LoadedTrackEntry[] = [];
  const skipped: string[] = [];

  for (const filePath of filePaths) {
    const format = resolveFormat(filePath);
    if (!format) {
      skipped.push(`${path.basename(filePath)}: unsupported format`);
      continue;
    }

    try {
      const metadata = await parseFile(filePath, { duration: true });
      const durationSec = metadata.format.duration;
      if (!durationSec || durationSec <= 0) {
        skipped.push(`${path.basename(filePath)}: missing duration metadata`);
        continue;
      }

      const title = metadata.common.title?.trim() || path.basename(filePath);
      const id = await buildTrackId(filePath);

      tracks.push({
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
      });
    } catch {
      skipped.push(`${path.basename(filePath)}: unreadable or corrupted`);
    }
  }

  return { tracks, skipped };
};
