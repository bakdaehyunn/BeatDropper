import { app } from 'electron';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { MusicLibraryTrack, Track } from '../shared/types';
import { LoadedTrackEntry } from './trackLibrary';

const MUSIC_LIBRARY_SCHEMA_VERSION = 1;
const MUSIC_LIBRARY_FILE_NAME = 'music-library.json';

export interface StoredMusicLibraryTrack extends MusicLibraryTrack {
  filePath: string;
}

interface MusicLibraryMutationResult {
  tracks: MusicLibraryTrack[];
  added: number;
  updated: number;
  restored: number;
  missing: number;
}

interface MusicLibraryFile {
  schemaVersion: typeof MUSIC_LIBRARY_SCHEMA_VERSION;
  tracks: StoredMusicLibraryTrack[];
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const sanitizeStoredTrack = (candidate: unknown): StoredMusicLibraryTrack | null => {
  if (!isRecord(candidate)) {
    return null;
  }
  if (
    typeof candidate.id !== 'string' ||
    candidate.id.trim().length === 0 ||
    typeof candidate.title !== 'string' ||
    candidate.title.trim().length === 0 ||
    !isFiniteNumber(candidate.durationSec) ||
    (candidate.format !== 'mp3' && candidate.format !== 'wav') ||
    typeof candidate.filePath !== 'string' ||
    candidate.filePath.trim().length === 0 ||
    typeof candidate.sourcePath !== 'string' ||
    candidate.sourcePath.trim().length === 0
  ) {
    return null;
  }

  const addedAt = typeof candidate.addedAt === 'string' ? candidate.addedAt : new Date(0).toISOString();
  const updatedAt = typeof candidate.updatedAt === 'string' ? candidate.updatedAt : addedAt;
  const missing = typeof candidate.missing === 'boolean' ? candidate.missing : false;
  const missingAt =
    typeof candidate.missingAt === 'string' && candidate.missingAt.trim().length > 0
      ? candidate.missingAt
      : null;
  const sourceLabel =
    typeof candidate.sourceLabel === 'string' && candidate.sourceLabel.trim().length > 0
      ? candidate.sourceLabel
      : path.basename(candidate.sourcePath) || candidate.sourcePath;

  return {
    id: candidate.id,
    title: candidate.title,
    durationSec: candidate.durationSec,
    format: candidate.format,
    bpm: isFiniteNumber(candidate.bpm) ? candidate.bpm : null,
    addedAt,
    updatedAt,
    sourcePath: candidate.sourcePath,
    sourceLabel,
    missing,
    missingAt: missing ? missingAt : null,
    filePath: candidate.filePath
  };
};

const toPublicTrack = (track: StoredMusicLibraryTrack): MusicLibraryTrack => ({
  id: track.id,
  title: track.title,
  durationSec: track.durationSec,
  format: track.format,
  bpm: track.bpm,
  addedAt: track.addedAt,
  updatedAt: track.updatedAt,
  sourcePath: track.sourcePath,
  sourceLabel: track.sourceLabel,
  missing: track.missing,
  missingAt: track.missingAt
});

const toPlaylistTrack = (track: StoredMusicLibraryTrack): Track => ({
  id: track.id,
  title: track.title,
  durationSec: track.durationSec,
  format: track.format,
  bpm: track.bpm
});

const sortEntries = (entries: StoredMusicLibraryTrack[]): StoredMusicLibraryTrack[] => {
  return [...entries].sort((left, right) => {
    return left.addedAt.localeCompare(right.addedAt) || left.title.localeCompare(right.title);
  });
};

const fileExists = async (filePath: string): Promise<boolean> => {
  try {
    const fileStats = await stat(filePath);
    return fileStats.isFile();
  } catch {
    return false;
  }
};

const groupEntriesByFilePath = (
  entries: StoredMusicLibraryTrack[]
): Map<string, StoredMusicLibraryTrack[]> => {
  const grouped = new Map<string, StoredMusicLibraryTrack[]>();
  for (const entry of entries) {
    const matching = grouped.get(entry.filePath) ?? [];
    matching.push(entry);
    grouped.set(entry.filePath, matching);
  }
  return grouped;
};

const pickPreferredExistingEntry = (
  entries: StoredMusicLibraryTrack[] | undefined
): StoredMusicLibraryTrack | undefined => {
  if (!entries || entries.length === 0) {
    return undefined;
  }

  return [...entries].sort((left, right) => {
    return left.addedAt.localeCompare(right.addedAt) || left.updatedAt.localeCompare(right.updatedAt);
  })[0];
};

export class MusicLibraryStore {
  private readonly filePath: string;

  constructor(filePath = path.join(app.getPath('userData'), MUSIC_LIBRARY_FILE_NAME)) {
    this.filePath = filePath;
  }

  async readEntries(): Promise<StoredMusicLibraryTrack[]> {
    try {
      const raw = await readFile(this.filePath, 'utf8');
      const parsed = JSON.parse(raw) as Partial<MusicLibraryFile>;
      if (!Array.isArray(parsed.tracks)) {
        return [];
      }
      return parsed.tracks
        .map(sanitizeStoredTrack)
        .filter((track): track is StoredMusicLibraryTrack => track !== null);
    } catch {
      return [];
    }
  }

  async readTracks(): Promise<MusicLibraryTrack[]> {
    const entries = await this.readEntries();
    return entries.map(toPublicTrack);
  }

  async refreshAvailability(
    nowIso = new Date().toISOString()
  ): Promise<{ tracks: MusicLibraryTrack[]; missing: number; restored: number }> {
    const entries = await this.readEntries();
    const next: StoredMusicLibraryTrack[] = [];
    let changed = false;
    let missing = 0;
    let restored = 0;

    for (const entry of entries) {
      const exists = await fileExists(entry.filePath);
      if (!exists) {
        missing += 1;
        if (entry.missing) {
          next.push(entry);
          continue;
        }
        changed = true;
        next.push({
          ...entry,
          missing: true,
          missingAt: nowIso
        });
        continue;
      }

      if (entry.missing) {
        changed = true;
        restored += 1;
      }
      next.push({
        ...entry,
        missing: false,
        missingAt: null
      });
    }

    if (changed) {
      await this.writeEntries(sortEntries(next));
    }

    return {
      tracks: next.map(toPublicTrack),
      missing,
      restored
    };
  }

  async upsertLoadedTracks(
    loadedTracks: LoadedTrackEntry[],
    sourcePath: string,
    nowIso = new Date().toISOString()
  ): Promise<MusicLibraryMutationResult> {
    const current = await this.readEntries();
    const byId = new Map(current.map((track) => [track.id, track]));
    const byFilePath = groupEntriesByFilePath(current);
    let added = 0;
    let updated = 0;
    let restored = 0;
    const sourceLabel = path.basename(sourcePath) || sourcePath;

    for (const entry of loadedTracks) {
      const pathEntries = byFilePath.get(entry.filePath);
      const existing = pickPreferredExistingEntry(pathEntries) ?? byId.get(entry.track.id);
      const persistedId = existing?.id ?? entry.track.id;
      if (existing) {
        updated += 1;
        if (existing.missing) {
          restored += 1;
        }
      } else {
        added += 1;
      }

      for (const duplicate of pathEntries ?? []) {
        if (duplicate.id !== persistedId) {
          byId.delete(duplicate.id);
        }
      }

      if (persistedId !== entry.track.id) {
        byId.delete(entry.track.id);
      }

      byId.set(persistedId, {
        ...entry.track,
        id: persistedId,
        bpm: entry.track.bpm ?? null,
        addedAt: existing?.addedAt ?? nowIso,
        updatedAt: nowIso,
        sourcePath,
        sourceLabel,
        missing: false,
        missingAt: null,
        filePath: entry.filePath
      });
    }

    const next = sortEntries(Array.from(byId.values()));
    await this.writeEntries(next);
    return {
      tracks: next.map(toPublicTrack),
      added,
      updated,
      restored,
      missing: next.filter((track) => track.missing).length
    };
  }

  async rescanSource(
    loadedTracks: LoadedTrackEntry[],
    sourcePath: string,
    scannedFilePaths: string[],
    nowIso = new Date().toISOString()
  ): Promise<MusicLibraryMutationResult> {
    const current = await this.readEntries();
    const byId = new Map(current.map((track) => [track.id, track]));
    const byFilePath = groupEntriesByFilePath(current);
    const scannedPathSet = new Set(scannedFilePaths);
    const sourceLabel = path.basename(sourcePath) || sourcePath;
    let added = 0;
    let updated = 0;
    let restored = 0;

    for (const entry of current) {
      if (entry.sourcePath !== sourcePath || scannedPathSet.has(entry.filePath)) {
        continue;
      }
      byId.set(entry.id, {
        ...entry,
        missing: true,
        missingAt: entry.missingAt ?? nowIso
      });
    }

    for (const entry of loadedTracks) {
      const pathEntries = byFilePath.get(entry.filePath);
      const existing = pickPreferredExistingEntry(pathEntries) ?? byId.get(entry.track.id);
      const persistedId = existing?.id ?? entry.track.id;
      if (existing) {
        updated += 1;
        if (existing.missing) {
          restored += 1;
        }
      } else {
        added += 1;
      }

      for (const duplicate of pathEntries ?? []) {
        if (duplicate.id !== persistedId) {
          byId.delete(duplicate.id);
        }
      }

      if (persistedId !== entry.track.id) {
        byId.delete(entry.track.id);
      }

      byId.set(persistedId, {
        ...entry.track,
        id: persistedId,
        bpm: entry.track.bpm ?? null,
        addedAt: existing?.addedAt ?? nowIso,
        updatedAt: nowIso,
        sourcePath,
        sourceLabel,
        missing: false,
        missingAt: null,
        filePath: entry.filePath
      });
    }

    const next = sortEntries(Array.from(byId.values()));
    await this.writeEntries(next);
    return {
      tracks: next.map(toPublicTrack),
      added,
      updated,
      restored,
      missing: next.filter((track) => track.sourcePath === sourcePath && track.missing).length
    };
  }

  async getEntriesByIds(trackIds: string[]): Promise<StoredMusicLibraryTrack[]> {
    const byId = new Map((await this.readEntries()).map((track) => [track.id, track]));
    return trackIds
      .map((trackId) => byId.get(trackId))
      .filter((track): track is StoredMusicLibraryTrack => track !== undefined);
  }

  toRegisterEntries(entries: StoredMusicLibraryTrack[]) {
    return entries.map((entry) => ({
      trackId: entry.id,
      filePath: entry.filePath,
      track: toPlaylistTrack(entry)
    }));
  }

  private async writeEntries(tracks: StoredMusicLibraryTrack[]): Promise<void> {
    const payload: MusicLibraryFile = {
      schemaVersion: MUSIC_LIBRARY_SCHEMA_VERSION,
      tracks
    };
    await mkdir(path.dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(payload, null, 2), 'utf8');
  }
}
