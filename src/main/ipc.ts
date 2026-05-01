import { BrowserWindow, dialog, ipcMain } from 'electron';
import { readFile } from 'node:fs/promises';
import { TrackAnalysisService } from './analysis/trackAnalysisService';
import { TrackAnalysisStore } from './analysis/trackAnalysisStore';
import { AiDjPlannerService } from './aiDj/aiDjPlannerService';
import { RequestMixPlanInput } from '../shared/plannerContract';
import { PlayerSettings, TrackLoadMode } from '../shared/types';
import { readSettings, writeSettings } from './settingsStore';
import { loadTracksFromPaths } from './trackLibrary';
import { TrackRegistry } from './trackRegistry';

const trackRegistry = new TrackRegistry();
const trackAnalysisStore = new TrackAnalysisStore();
const trackAnalysisService = new TrackAnalysisService({
  store: trackAnalysisStore,
  resolveTrackPath: (trackId: string) => trackRegistry.resolvePath(trackId)
});
const aiDjPlannerService = new AiDjPlannerService({
  analysisService: trackAnalysisService,
  settingsProvider: readSettings
});
const SETTINGS_KEYS: ReadonlySet<keyof PlayerSettings> = new Set([
  'fadeDurationSec',
  'masterGain',
  'predecodeLeadSec',
  'repeatAll',
  'decodeTimeoutDurationWeightMs',
  'decodeTimeoutSizeWeightMs',
  'aiDjEnabled',
  'aiDjMode',
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

const parseTrackIdList = (input: unknown): string[] => {
  if (!Array.isArray(input) || !input.every((item) => typeof item === 'string')) {
    throw new Error('Invalid track id list');
  }

  return input.filter((item) => item.trim().length > 0);
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

  ipcMain.handle('planner:requestMixPlan', async (_event, candidateInput: unknown) => {
    const candidate = parseMixPlanRequestCandidate(candidateInput);
    return aiDjPlannerService.requestMixPlan(candidate);
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
