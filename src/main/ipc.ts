import { BrowserWindow, dialog, ipcMain } from 'electron';
import { readFile } from 'node:fs/promises';
import { sanitizeTrackAnalysis } from '../shared/analysis';
import { TrackAnalysisService } from './analysis/trackAnalysisService';
import { TrackAnalysisStore } from './analysis/trackAnalysisStore';
import { AiDjPlannerService } from './aiDj/aiDjPlannerService';
import { AgentConnectionService } from './aiDj/agentConnectionService';
import { RequestMixPlanInput } from '../shared/plannerContract';
import { AiAgentProfile, PlayerSettings, TrackLoadMode, TrackLoadResult } from '../shared/types';
import { CODEX_AGENT_PROFILE_ID } from '../shared/settings';
import { readSettings, writeSettings } from './settingsStore';
import { MusicLibraryStore } from './musicLibraryStore';
import { loadTracksFromDirectory, loadTracksFromPaths } from './trackLibrary';
import { TrackRegistry } from './trackRegistry';
import { UserPlaylistStore, normalizePlaylistName } from './userPlaylistStore';

const trackRegistry = new TrackRegistry();
const musicLibraryStore = new MusicLibraryStore();
const userPlaylistStore = new UserPlaylistStore();
const trackAnalysisStore = new TrackAnalysisStore();
const trackAnalysisService = new TrackAnalysisService({
  store: trackAnalysisStore,
  resolveTrackPath: (trackId: string) => trackRegistry.resolvePath(trackId)
});
const aiDjPlannerService = new AiDjPlannerService({
  analysisService: trackAnalysisService,
  settingsProvider: readSettings
});
const agentConnectionService = new AgentConnectionService();
const SETTINGS_KEYS: ReadonlySet<keyof PlayerSettings> = new Set([
  'fadeDurationSec',
  'masterGain',
  'predecodeLeadSec',
  'repeatAll',
  'decodeTimeoutDurationWeightMs',
  'decodeTimeoutSizeWeightMs',
  'aiDjEnabled',
  'aiDjMode',
  'aiAgentProfiles',
  'activeAiAgentProfileId',
  'plannerCommand',
  'plannerArgs',
  'plannerTimeoutMs'
]);

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
};

const isFiniteNumber = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value);
};

const isStringArray = (value: unknown): value is string[] => {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
};

const parseAiAgentProfile = (item: unknown): AiAgentProfile => {
  if (!isRecord(item)) {
    throw new Error('Invalid aiAgentProfiles item');
  }
  if (typeof item.id !== 'string' || item.id.trim().length === 0) {
    throw new Error('Invalid aiAgentProfiles id');
  }
  if (typeof item.name !== 'string' || item.name.trim().length === 0) {
    throw new Error('Invalid aiAgentProfiles name');
  }
  if (item.kind !== 'cli') {
    throw new Error('Invalid aiAgentProfiles kind');
  }
  if (typeof item.command !== 'string') {
    throw new Error('Invalid aiAgentProfiles command');
  }
  if (!isStringArray(item.args)) {
    throw new Error('Invalid aiAgentProfiles args');
  }
  if (!isFiniteNumber(item.timeoutMs)) {
    throw new Error('Invalid aiAgentProfiles timeoutMs');
  }
  if (typeof item.enabled !== 'boolean') {
    throw new Error('Invalid aiAgentProfiles enabled');
  }

  return {
    id: item.id,
    name: item.name,
    kind: 'cli',
    command: item.command,
    args: item.args,
    timeoutMs: item.timeoutMs,
    enabled: item.enabled
  };
};

const parseCodexAgentProfile = (item: unknown): AiAgentProfile => {
  const profile = parseAiAgentProfile(item);
  if (profile.id !== CODEX_AGENT_PROFILE_ID) {
    throw new Error('Only Codex agent connection checks are supported');
  }

  return profile;
};

const parseAiAgentProfiles = (input: unknown): AiAgentProfile[] => {
  if (!Array.isArray(input)) {
    throw new Error('Invalid aiAgentProfiles');
  }

  return input.map(parseAiAgentProfile);
};

const parseTrackIdList = (input: unknown): string[] => {
  if (!Array.isArray(input) || !input.every((item) => typeof item === 'string')) {
    throw new Error('Invalid track id list');
  }

  return input.filter((item) => item.trim().length > 0);
};

const parsePlaylistId = (input: unknown): string => {
  if (typeof input !== 'string' || input.trim().length === 0) {
    throw new Error('Invalid playlist id');
  }

  return input;
};

const parsePlaylistName = (input: unknown): string => {
  if (typeof input !== 'string') {
    throw new Error('Invalid playlist name');
  }

  const name = normalizePlaylistName(input);
  if (name.length === 0) {
    throw new Error('Invalid playlist name');
  }

  return name;
};

const loadLibraryTrackIdsToRegistry = async (
  trackIds: string[],
  mode: TrackLoadMode
): Promise<TrackLoadResult> => {
  await musicLibraryStore.refreshAvailability();
  const entries = await musicLibraryStore.getEntriesByIds(trackIds);
  const foundIds = new Set(entries.map((entry) => entry.id));
  const missingEntries = entries.filter((entry) => entry.missing);
  const availableEntries = entries.filter((entry) => !entry.missing);
  const skipped = [
    ...trackIds
      .filter((trackId) => !foundIds.has(trackId))
      .map((trackId) => `${trackId}: not in library`),
    ...missingEntries.map((entry) => `${entry.title}: missing file`)
  ];
  const registerEntries = musicLibraryStore.toRegisterEntries(availableEntries);

  if (mode === 'replace') {
    trackRegistry.replace(registerEntries);
  } else {
    trackRegistry.append(registerEntries);
  }

  return {
    tracks: registerEntries
      .map((entry) => entry.track)
      .filter((track): track is NonNullable<typeof track> => track !== undefined),
    skipped,
    canceled: false,
    mode
  };
};

const parseTrackCandidate = (input: unknown) => {
  if (!isRecord(input)) {
    throw new Error('Invalid track payload');
  }

  if (typeof input.id !== 'string' || input.id.trim().length === 0) {
    throw new Error('Invalid track id');
  }
  if (typeof input.title !== 'string' || input.title.trim().length === 0) {
    throw new Error('Invalid track title');
  }
  if (!isFiniteNumber(input.durationSec)) {
    throw new Error('Invalid track durationSec');
  }
  if (input.format !== 'mp3' && input.format !== 'wav') {
    throw new Error('Invalid track format');
  }
  if (
    input.bpm !== undefined &&
    input.bpm !== null &&
    !isFiniteNumber(input.bpm)
  ) {
    throw new Error('Invalid track bpm');
  }

  return {
    id: input.id,
    title: input.title,
    durationSec: input.durationSec,
    format: input.format,
    bpm: input.bpm ?? null
  } as const;
};

const parseMixPlanRequestCandidate = (input: unknown): RequestMixPlanInput => {
  if (!isRecord(input)) {
    throw new Error('Invalid planner request payload');
  }

  if (!isRecord(input.currentPlayback) || !isFiniteNumber(input.currentPlayback.elapsedSec)) {
    throw new Error('Invalid currentPlayback.elapsedSec');
  }

  const candidate: RequestMixPlanInput = {
    currentTrack: parseTrackCandidate(input.currentTrack),
    nextTrack: parseTrackCandidate(input.nextTrack),
    currentPlayback: {
      elapsedSec: input.currentPlayback.elapsedSec
    }
  };

  if (input.settingsOverride !== undefined) {
    candidate.settingsOverride = parseSettingsCandidate(input.settingsOverride);
  }

  return candidate;
};

const parseSettingsCandidate = (input: unknown): Partial<PlayerSettings> => {
  if (!isRecord(input)) {
    throw new Error('Invalid settings payload');
  }

  const candidate: Partial<PlayerSettings> = {};
  for (const key of Object.keys(input)) {
    if (!SETTINGS_KEYS.has(key as keyof PlayerSettings)) {
      throw new Error(`Unknown setting key: ${key}`);
    }
  }

  if ('fadeDurationSec' in input) {
    if (!isFiniteNumber(input.fadeDurationSec)) {
      throw new Error('Invalid fadeDurationSec');
    }
    candidate.fadeDurationSec = input.fadeDurationSec;
  }

  if ('masterGain' in input) {
    if (!isFiniteNumber(input.masterGain)) {
      throw new Error('Invalid masterGain');
    }
    candidate.masterGain = input.masterGain;
  }

  if ('predecodeLeadSec' in input) {
    if (!isFiniteNumber(input.predecodeLeadSec)) {
      throw new Error('Invalid predecodeLeadSec');
    }
    candidate.predecodeLeadSec = input.predecodeLeadSec;
  }

  if ('repeatAll' in input) {
    if (typeof input.repeatAll !== 'boolean') {
      throw new Error('Invalid repeatAll');
    }
    candidate.repeatAll = input.repeatAll;
  }

  if ('decodeTimeoutDurationWeightMs' in input) {
    if (!isFiniteNumber(input.decodeTimeoutDurationWeightMs)) {
      throw new Error('Invalid decodeTimeoutDurationWeightMs');
    }
    candidate.decodeTimeoutDurationWeightMs = input.decodeTimeoutDurationWeightMs;
  }

  if ('decodeTimeoutSizeWeightMs' in input) {
    if (!isFiniteNumber(input.decodeTimeoutSizeWeightMs)) {
      throw new Error('Invalid decodeTimeoutSizeWeightMs');
    }
    candidate.decodeTimeoutSizeWeightMs = input.decodeTimeoutSizeWeightMs;
  }

  if ('aiDjEnabled' in input) {
    if (typeof input.aiDjEnabled !== 'boolean') {
      throw new Error('Invalid aiDjEnabled');
    }
    candidate.aiDjEnabled = input.aiDjEnabled;
  }

  if ('aiDjMode' in input) {
    if (
      input.aiDjMode !== 'safe' &&
      input.aiDjMode !== 'balanced' &&
      input.aiDjMode !== 'adventurous'
    ) {
      throw new Error('Invalid aiDjMode');
    }
    candidate.aiDjMode = input.aiDjMode;
  }

  if ('aiAgentProfiles' in input) {
    candidate.aiAgentProfiles = parseAiAgentProfiles(input.aiAgentProfiles);
  }

  if ('activeAiAgentProfileId' in input) {
    if (typeof input.activeAiAgentProfileId !== 'string') {
      throw new Error('Invalid activeAiAgentProfileId');
    }
    candidate.activeAiAgentProfileId = input.activeAiAgentProfileId;
  }

  if ('plannerCommand' in input) {
    if (typeof input.plannerCommand !== 'string') {
      throw new Error('Invalid plannerCommand');
    }
    candidate.plannerCommand = input.plannerCommand;
  }

  if ('plannerArgs' in input) {
    if (!isStringArray(input.plannerArgs)) {
      throw new Error('Invalid plannerArgs');
    }
    candidate.plannerArgs = input.plannerArgs;
  }

  if ('plannerTimeoutMs' in input) {
    if (!isFiniteNumber(input.plannerTimeoutMs)) {
      throw new Error('Invalid plannerTimeoutMs');
    }
    candidate.plannerTimeoutMs = input.plannerTimeoutMs;
  }

  return candidate;
};

export const registerIpcHandlers = (): void => {
  ipcMain.handle('window:minimize', async (event) => {
    BrowserWindow.fromWebContents(event.sender)?.minimize();
  });

  ipcMain.handle('window:toggleMaximize', async (event) => {
    const window = BrowserWindow.fromWebContents(event.sender);
    if (!window) {
      return;
    }

    if (window.isMaximized()) {
      window.unmaximize();
    } else {
      window.maximize();
    }
  });

  ipcMain.handle('window:close', async (event) => {
    BrowserWindow.fromWebContents(event.sender)?.close();
  });

  ipcMain.handle('library:openTracks', async (_event, modeInput: unknown) => {
    const mode: TrackLoadMode = modeInput === 'append' ? 'append' : 'replace';
    const result = await dialog.showOpenDialog({
      title: 'Select audio tracks',
      properties: ['openFile', 'multiSelections'],
      filters: [
        {
          name: 'Audio',
          extensions: ['mp3', 'wav']
        }
      ]
    });

    if (result.canceled) {
      return { tracks: [], skipped: [], canceled: true, mode };
    }

    const loaded = await loadTracksFromPaths(result.filePaths);
    const registerEntries = loaded.tracks.map((entry) => ({
      trackId: entry.track.id,
      filePath: entry.filePath,
      track: entry.track
    }));

    if (mode === 'append') {
      trackRegistry.append(registerEntries);
    } else {
      trackRegistry.replace(registerEntries);
    }

    return {
      tracks: loaded.tracks.map((entry) => entry.track),
      skipped: loaded.skipped,
      canceled: false,
      mode
    };
  });

  ipcMain.handle('library:getTracks', async () => {
    return trackRegistry.getTracks();
  });

  ipcMain.handle('library:setTrackOrder', async (_event, trackIdsInput: unknown) => {
    trackRegistry.reorder(parseTrackIdList(trackIdsInput));
    return trackRegistry.getTracks();
  });

  ipcMain.handle('library:clearTracks', async () => {
    trackRegistry.clear();
  });

  ipcMain.handle('musicLibrary:getTracks', async () => {
    const refreshed = await musicLibraryStore.refreshAvailability();
    return refreshed.tracks;
  });

  ipcMain.handle('musicLibrary:importFolder', async () => {
    const result = await dialog.showOpenDialog({
      title: 'Select music folder',
      properties: ['openDirectory']
    });

    if (result.canceled || result.filePaths.length === 0) {
      const refreshed = await musicLibraryStore.refreshAvailability();
      return {
        tracks: refreshed.tracks,
        added: 0,
        updated: 0,
        restored: refreshed.restored,
        missing: refreshed.missing,
        skipped: [],
        canceled: true,
        sourcePath: null
      };
    }

    const sourcePath = result.filePaths[0];
    const loaded = await loadTracksFromDirectory(sourcePath);
    const saved = await musicLibraryStore.upsertLoadedTracks(loaded.tracks, sourcePath);

    return {
      tracks: saved.tracks,
      added: saved.added,
      updated: saved.updated,
      restored: saved.restored,
      missing: saved.missing,
      skipped: loaded.skipped,
      canceled: false,
      sourcePath
    };
  });

  ipcMain.handle('musicLibrary:rescanFolder', async (_event, sourcePathInput: unknown) => {
    if (typeof sourcePathInput !== 'string' || sourcePathInput.trim().length === 0) {
      throw new Error('Invalid library source path');
    }

    const sourcePath = sourcePathInput;
    const loaded = await loadTracksFromDirectory(sourcePath);
    const saved = await musicLibraryStore.rescanSource(
      loaded.tracks,
      sourcePath,
      loaded.scannedFilePaths
    );

    return {
      tracks: saved.tracks,
      added: saved.added,
      updated: saved.updated,
      restored: saved.restored,
      missing: saved.missing,
      skipped: loaded.skipped,
      canceled: false,
      sourcePath
    };
  });

  ipcMain.handle(
    'musicLibrary:addTracksToPlaylist',
    async (_event, trackIdsInput: unknown, modeInput: unknown) => {
      const mode: TrackLoadMode = modeInput === 'replace' ? 'replace' : 'append';
      const trackIds = parseTrackIdList(trackIdsInput);
      return loadLibraryTrackIdsToRegistry(trackIds, mode);
    }
  );

  ipcMain.handle('userPlaylists:get', async () => {
    return userPlaylistStore.readPlaylists();
  });

  ipcMain.handle(
    'userPlaylists:create',
    async (_event, nameInput: unknown, trackIdsInput: unknown) => {
      return userPlaylistStore.createPlaylist(
        parsePlaylistName(nameInput),
        parseTrackIdList(trackIdsInput)
      );
    }
  );

  ipcMain.handle(
    'userPlaylists:rename',
    async (_event, playlistIdInput: unknown, nameInput: unknown) => {
      return userPlaylistStore.renamePlaylist(
        parsePlaylistId(playlistIdInput),
        parsePlaylistName(nameInput)
      );
    }
  );

  ipcMain.handle('userPlaylists:delete', async (_event, playlistIdInput: unknown) => {
    return userPlaylistStore.deletePlaylist(parsePlaylistId(playlistIdInput));
  });

  ipcMain.handle(
    'userPlaylists:setTracks',
    async (_event, playlistIdInput: unknown, trackIdsInput: unknown) => {
      return userPlaylistStore.setPlaylistTracks(
        parsePlaylistId(playlistIdInput),
        parseTrackIdList(trackIdsInput)
      );
    }
  );

  ipcMain.handle(
    'userPlaylists:addLibraryTracks',
    async (_event, playlistIdInput: unknown, trackIdsInput: unknown) => {
      return userPlaylistStore.addTrackIds(
        parsePlaylistId(playlistIdInput),
        parseTrackIdList(trackIdsInput)
      );
    }
  );

  ipcMain.handle('userPlaylists:load', async (_event, playlistIdInput: unknown) => {
    const playlist = await userPlaylistStore.getPlaylist(parsePlaylistId(playlistIdInput));
    if (!playlist) {
      throw new Error('Playlist not found');
    }

    return loadLibraryTrackIdsToRegistry(playlist.trackIds, 'replace');
  });

  ipcMain.handle('track:readBufferById', async (_event, trackId: unknown) => {
    const filePath = trackRegistry.resolvePath(trackId);
    const buffer = await readFile(filePath);
    return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  });

  ipcMain.handle('analysis:getByTrackId', async (_event, trackId: unknown) => {
    if (typeof trackId !== 'string' || trackId.trim().length === 0) {
      throw new Error('Invalid track id');
    }

    return trackAnalysisService.getTrackAnalysis(trackId);
  });

  ipcMain.handle(
    'analysis:saveForTrackId',
    async (_event, trackId: unknown, analysisInput: unknown) => {
      if (typeof trackId !== 'string' || trackId.trim().length === 0) {
        throw new Error('Invalid track id');
      }
      if (!isRecord(analysisInput)) {
        throw new Error('Invalid track analysis payload');
      }

      return trackAnalysisService.saveTrackAnalysis(
        trackId,
        sanitizeTrackAnalysis(trackId, analysisInput)
      );
    }
  );

  ipcMain.handle('planner:requestMixPlan', async (_event, candidateInput: unknown) => {
    const candidate = parseMixPlanRequestCandidate(candidateInput);
    return aiDjPlannerService.requestMixPlan(candidate);
  });

  ipcMain.handle('agent:checkConnection', async (_event, profileInput: unknown) => {
    const profile = parseCodexAgentProfile(profileInput);
    return agentConnectionService.checkProfile(profile);
  });

  ipcMain.handle('settings:get', async () => {
    return readSettings();
  });

  ipcMain.handle(
    'settings:save',
    async (_event, candidateInput: unknown) => {
      const candidate = parseSettingsCandidate(candidateInput);
      return writeSettings(candidate);
    }
  );
};
