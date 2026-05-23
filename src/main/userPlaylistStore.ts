import { randomUUID } from 'node:crypto';
import { app } from 'electron';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { UserPlaylist, UserPlaylistMutationResult } from '../shared/types';

const USER_PLAYLIST_SCHEMA_VERSION = 1;
const USER_PLAYLIST_FILE_NAME = 'user-playlists.json';
const MAX_PLAYLIST_NAME_LENGTH = 80;

interface UserPlaylistFile {
  schemaVersion: typeof USER_PLAYLIST_SCHEMA_VERSION;
  playlists: UserPlaylist[];
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

export const normalizePlaylistName = (name: string): string => {
  return name.trim().replace(/\s+/g, ' ').slice(0, MAX_PLAYLIST_NAME_LENGTH);
};

const normalizeTrackIds = (trackIds: string[]): string[] => {
  const seen = new Set<string>();
  const normalized: string[] = [];

  for (const trackId of trackIds) {
    const next = trackId.trim();
    if (next.length === 0 || seen.has(next)) {
      continue;
    }
    seen.add(next);
    normalized.push(next);
  }

  return normalized;
};

const sanitizePlaylist = (candidate: unknown): UserPlaylist | null => {
  if (!isRecord(candidate)) {
    return null;
  }
  if (
    typeof candidate.id !== 'string' ||
    candidate.id.trim().length === 0 ||
    typeof candidate.name !== 'string' ||
    candidate.name.trim().length === 0 ||
    !Array.isArray(candidate.trackIds)
  ) {
    return null;
  }

  const name = normalizePlaylistName(candidate.name);
  if (name.length === 0) {
    return null;
  }

  const createdAt =
    typeof candidate.createdAt === 'string' ? candidate.createdAt : new Date(0).toISOString();
  const updatedAt = typeof candidate.updatedAt === 'string' ? candidate.updatedAt : createdAt;

  return {
    id: candidate.id,
    name,
    trackIds: normalizeTrackIds(
      candidate.trackIds.filter((trackId): trackId is string => typeof trackId === 'string')
    ),
    createdAt,
    updatedAt
  };
};

const sortPlaylists = (playlists: UserPlaylist[]): UserPlaylist[] => {
  return [...playlists].sort((left, right) => {
    return right.updatedAt.localeCompare(left.updatedAt) || left.name.localeCompare(right.name);
  });
};

export class UserPlaylistStore {
  private readonly filePath: string;

  constructor(filePath = path.join(app.getPath('userData'), USER_PLAYLIST_FILE_NAME)) {
    this.filePath = filePath;
  }

  async readPlaylists(): Promise<UserPlaylist[]> {
    try {
      const raw = await readFile(this.filePath, 'utf8');
      const parsed = JSON.parse(raw) as Partial<UserPlaylistFile>;
      if (!Array.isArray(parsed.playlists)) {
        return [];
      }

      return sortPlaylists(
        parsed.playlists
          .map(sanitizePlaylist)
          .filter((playlist): playlist is UserPlaylist => playlist !== null)
      );
    } catch {
      return [];
    }
  }

  async createPlaylist(
    nameInput: string,
    trackIds: string[],
    nowIso = new Date().toISOString()
  ): Promise<UserPlaylistMutationResult> {
    const name = normalizePlaylistName(nameInput);
    if (name.length === 0) {
      throw new Error('Invalid playlist name');
    }

    const playlist: UserPlaylist = {
      id: randomUUID(),
      name,
      trackIds: normalizeTrackIds(trackIds),
      createdAt: nowIso,
      updatedAt: nowIso
    };
    const playlists = sortPlaylists([playlist, ...(await this.readPlaylists())]);
    await this.writePlaylists(playlists);

    return {
      playlists,
      playlist
    };
  }

  async renamePlaylist(
    playlistId: string,
    nameInput: string,
    nowIso = new Date().toISOString()
  ): Promise<UserPlaylistMutationResult> {
    const name = normalizePlaylistName(nameInput);
    if (name.length === 0) {
      throw new Error('Invalid playlist name');
    }

    return this.updatePlaylist(playlistId, nowIso, (playlist) => ({
      ...playlist,
      name
    }));
  }

  async deletePlaylist(playlistId: string): Promise<UserPlaylistMutationResult> {
    const playlists = await this.readPlaylists();
    const next = playlists.filter((playlist) => playlist.id !== playlistId);
    await this.writePlaylists(next);
    return {
      playlists: next,
      playlist: null
    };
  }

  async setPlaylistTracks(
    playlistId: string,
    trackIds: string[],
    nowIso = new Date().toISOString()
  ): Promise<UserPlaylistMutationResult> {
    return this.updatePlaylist(playlistId, nowIso, (playlist) => ({
      ...playlist,
      trackIds: normalizeTrackIds(trackIds)
    }));
  }

  async addTrackIds(
    playlistId: string,
    trackIds: string[],
    nowIso = new Date().toISOString()
  ): Promise<UserPlaylistMutationResult> {
    return this.updatePlaylist(playlistId, nowIso, (playlist) => ({
      ...playlist,
      trackIds: normalizeTrackIds([...playlist.trackIds, ...trackIds])
    }));
  }

  async getPlaylist(playlistId: string): Promise<UserPlaylist | null> {
    return (await this.readPlaylists()).find((playlist) => playlist.id === playlistId) ?? null;
  }

  private async updatePlaylist(
    playlistId: string,
    nowIso: string,
    update: (playlist: UserPlaylist) => UserPlaylist
  ): Promise<UserPlaylistMutationResult> {
    const playlists = await this.readPlaylists();
    let updatedPlaylist: UserPlaylist | null = null;
    const next = sortPlaylists(
      playlists.map((playlist) => {
        if (playlist.id !== playlistId) {
          return playlist;
        }
        updatedPlaylist = {
          ...update(playlist),
          updatedAt: nowIso
        };
        return updatedPlaylist;
      })
    );

    if (!updatedPlaylist) {
      throw new Error('Playlist not found');
    }

    await this.writePlaylists(next);
    return {
      playlists: next,
      playlist: updatedPlaylist
    };
  }

  private async writePlaylists(playlists: UserPlaylist[]): Promise<void> {
    const payload: UserPlaylistFile = {
      schemaVersion: USER_PLAYLIST_SCHEMA_VERSION,
      playlists
    };
    await mkdir(path.dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(payload, null, 2), 'utf8');
  }
}
