const handlerMap = new Map<string, (...args: unknown[]) => unknown>();

const mockShowOpenDialog = vi.fn();
const mockReadFile = vi.fn();
const mockLoadTracksFromPaths = vi.fn();
const mockLoadTracksFromDirectory = vi.fn();
const mockReadLibraryTracks = vi.fn();
const mockRefreshLibraryAvailability = vi.fn();
const mockUpsertLoadedTracks = vi.fn();
const mockRescanSource = vi.fn();
const mockGetLibraryEntriesByIds = vi.fn();
const mockToRegisterEntries = vi.fn();
const mockReadUserPlaylists = vi.fn();
const mockCreateUserPlaylist = vi.fn();
const mockRenameUserPlaylist = vi.fn();
const mockDeleteUserPlaylist = vi.fn();
const mockSetUserPlaylistTracks = vi.fn();
const mockAddUserPlaylistTrackIds = vi.fn();
const mockGetUserPlaylist = vi.fn();
const mockReadSettings = vi.fn();
const mockWriteSettings = vi.fn();
const mockGetTrackAnalysis = vi.fn();
const mockSaveTrackAnalysis = vi.fn();
const mockRequestMixPlan = vi.fn();
const mockCheckProfile = vi.fn();

vi.mock('electron', () => {
  return {
    app: {
      getPath: () => '/tmp'
    },
    dialog: {
      showOpenDialog: mockShowOpenDialog
    },
    ipcMain: {
      handle: (channel: string, handler: (...args: unknown[]) => unknown) => {
        handlerMap.set(channel, handler);
      }
    }
  };
});

vi.mock('node:fs/promises', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:fs/promises')>();
  return {
    ...actual,
    readFile: mockReadFile,
    default: {
      ...(actual as unknown as { default?: Record<string, unknown> }).default,
      ...actual,
      readFile: mockReadFile
    }
  };
});

vi.mock('../../src/main/trackLibrary', () => {
  return {
    loadTracksFromPaths: mockLoadTracksFromPaths,
    loadTracksFromDirectory: mockLoadTracksFromDirectory
  };
});

vi.mock('../../src/main/musicLibraryStore', () => {
  return {
    MusicLibraryStore: class {
      readTracks = mockReadLibraryTracks;
      refreshAvailability = mockRefreshLibraryAvailability;
      upsertLoadedTracks = mockUpsertLoadedTracks;
      rescanSource = mockRescanSource;
      getEntriesByIds = mockGetLibraryEntriesByIds;
      toRegisterEntries = mockToRegisterEntries;
    }
  };
});

vi.mock('../../src/main/userPlaylistStore', () => {
  return {
    normalizePlaylistName: (name: string) => name.trim().replace(/\s+/g, ' ').slice(0, 80),
    UserPlaylistStore: class {
      readPlaylists = mockReadUserPlaylists;
      createPlaylist = mockCreateUserPlaylist;
      renamePlaylist = mockRenameUserPlaylist;
      deletePlaylist = mockDeleteUserPlaylist;
      setPlaylistTracks = mockSetUserPlaylistTracks;
      addTrackIds = mockAddUserPlaylistTrackIds;
      getPlaylist = mockGetUserPlaylist;
    }
  };
});

vi.mock('../../src/main/settingsStore', () => {
  return {
    readSettings: mockReadSettings,
    writeSettings: mockWriteSettings
  };
});

vi.mock('../../src/main/analysis/trackAnalysisStore', () => {
  return {
    TrackAnalysisStore: class {}
  };
});

vi.mock('../../src/main/analysis/trackAnalysisService', () => {
  return {
    TrackAnalysisService: class {
      getTrackAnalysis = mockGetTrackAnalysis;
      saveTrackAnalysis = mockSaveTrackAnalysis;
    }
  };
});

vi.mock('../../src/main/aiDj/aiDjPlannerService', () => {
  return {
    AiDjPlannerService: class {
      requestMixPlan = mockRequestMixPlan;
    }
  };
});

vi.mock('../../src/main/aiDj/agentConnectionService', () => {
  return {
    AgentConnectionService: class {
      checkProfile = mockCheckProfile;
    }
  };
});

const trackEntry = (id: string, title: string, filePath: string) => ({
  track: {
    id,
    title,
    durationSec: 120,
    format: 'mp3' as const,
    bpm: null
  },
  filePath
});

const bytesFromArrayBuffer = (value: unknown): number[] => {
  return Array.from(new Uint8Array(value as ArrayBuffer));
};

const setupIpcHandlers = async () => {
  vi.resetModules();
  handlerMap.clear();
  const mod = await import('../../src/main/ipc');
  mod.registerIpcHandlers();

  const openHandler = handlerMap.get('library:openTracks');
  const getTracksHandler = handlerMap.get('library:getTracks');
  const getLibraryTracksHandler = handlerMap.get('musicLibrary:getTracks');
  const importLibraryFolderHandler = handlerMap.get('musicLibrary:importFolder');
  const rescanLibraryFolderHandler = handlerMap.get('musicLibrary:rescanFolder');
  const addLibraryTracksToPlaylistHandler = handlerMap.get('musicLibrary:addTracksToPlaylist');
  const getUserPlaylistsHandler = handlerMap.get('userPlaylists:get');
  const createUserPlaylistHandler = handlerMap.get('userPlaylists:create');
  const renameUserPlaylistHandler = handlerMap.get('userPlaylists:rename');
  const deleteUserPlaylistHandler = handlerMap.get('userPlaylists:delete');
  const setUserPlaylistTracksHandler = handlerMap.get('userPlaylists:setTracks');
  const addLibraryTracksToUserPlaylistHandler = handlerMap.get('userPlaylists:addLibraryTracks');
  const loadUserPlaylistHandler = handlerMap.get('userPlaylists:load');
  const readHandler = handlerMap.get('track:readBufferById');
  const analysisHandler = handlerMap.get('analysis:getByTrackId');
  const saveAnalysisHandler = handlerMap.get('analysis:saveForTrackId');
  const plannerHandler = handlerMap.get('planner:requestMixPlan');
  const agentCheckHandler = handlerMap.get('agent:checkConnection');
  const saveSettingsHandler = handlerMap.get('settings:save');
  if (
    !openHandler ||
    !getTracksHandler ||
    !getLibraryTracksHandler ||
    !importLibraryFolderHandler ||
    !rescanLibraryFolderHandler ||
    !addLibraryTracksToPlaylistHandler ||
    !getUserPlaylistsHandler ||
    !createUserPlaylistHandler ||
    !renameUserPlaylistHandler ||
    !deleteUserPlaylistHandler ||
    !setUserPlaylistTracksHandler ||
    !addLibraryTracksToUserPlaylistHandler ||
    !loadUserPlaylistHandler ||
    !readHandler ||
    !analysisHandler ||
    !saveAnalysisHandler ||
    !plannerHandler ||
    !agentCheckHandler ||
    !saveSettingsHandler
  ) {
    throw new Error('ipc handlers are not registered');
  }
  return {
    openHandler,
    getTracksHandler,
    getLibraryTracksHandler,
    importLibraryFolderHandler,
    rescanLibraryFolderHandler,
    addLibraryTracksToPlaylistHandler,
    getUserPlaylistsHandler,
    createUserPlaylistHandler,
    renameUserPlaylistHandler,
    deleteUserPlaylistHandler,
    setUserPlaylistTracksHandler,
    addLibraryTracksToUserPlaylistHandler,
    loadUserPlaylistHandler,
    readHandler,
    analysisHandler,
    saveAnalysisHandler,
    plannerHandler,
    agentCheckHandler,
    saveSettingsHandler
  };
};

describe('IPC library:openTracks', () => {
  beforeEach(() => {
    mockShowOpenDialog.mockReset();
    mockReadFile.mockReset();
    mockLoadTracksFromPaths.mockReset();
    mockLoadTracksFromDirectory.mockReset();
    mockReadLibraryTracks.mockReset();
    mockRefreshLibraryAvailability.mockReset();
    mockUpsertLoadedTracks.mockReset();
    mockRescanSource.mockReset();
    mockGetLibraryEntriesByIds.mockReset();
    mockToRegisterEntries.mockReset();
    mockReadUserPlaylists.mockReset();
    mockCreateUserPlaylist.mockReset();
    mockRenameUserPlaylist.mockReset();
    mockDeleteUserPlaylist.mockReset();
    mockSetUserPlaylistTracks.mockReset();
    mockAddUserPlaylistTrackIds.mockReset();
    mockGetUserPlaylist.mockReset();
    mockReadSettings.mockReset();
    mockWriteSettings.mockReset();
    mockGetTrackAnalysis.mockReset();
    mockSaveTrackAnalysis.mockReset();
    mockRequestMixPlan.mockReset();
    mockCheckProfile.mockReset();
  });

  it('keeps existing registry entries when append mode is used', async () => {
    const { openHandler, getTracksHandler, readHandler } = await setupIpcHandlers();

    mockShowOpenDialog
      .mockResolvedValueOnce({ canceled: false, filePaths: ['/music/one.mp3'] })
      .mockResolvedValueOnce({ canceled: false, filePaths: ['/music/two.mp3'] });
    mockLoadTracksFromPaths
      .mockResolvedValueOnce({
        tracks: [trackEntry('track-1', 'One', '/music/one.mp3')],
        skipped: []
      })
      .mockResolvedValueOnce({
        tracks: [trackEntry('track-2', 'Two', '/music/two.mp3')],
        skipped: []
      });
    mockReadFile.mockResolvedValue(Buffer.from([1, 2, 3]));

    const first = await openHandler({}, 'replace');
    const second = await openHandler({}, 'append');

    expect(first).toMatchObject({ canceled: false, mode: 'replace' });
    expect(second).toMatchObject({ canceled: false, mode: 'append' });
    expect(await getTracksHandler({})).toMatchObject([
      { id: 'track-1', title: 'One' },
      { id: 'track-2', title: 'Two' }
    ]);

    await readHandler({}, 'track-1');
    await readHandler({}, 'track-2');

    expect(mockReadFile).toHaveBeenCalledWith('/music/one.mp3');
    expect(mockReadFile).toHaveBeenCalledWith('/music/two.mp3');
  });

  it('replaces existing registry entries when replace mode is used', async () => {
    const { openHandler, readHandler } = await setupIpcHandlers();

    mockShowOpenDialog
      .mockResolvedValueOnce({ canceled: false, filePaths: ['/music/one.mp3'] })
      .mockResolvedValueOnce({ canceled: false, filePaths: ['/music/two.mp3'] });
    mockLoadTracksFromPaths
      .mockResolvedValueOnce({
        tracks: [trackEntry('track-1', 'One', '/music/one.mp3')],
        skipped: []
      })
      .mockResolvedValueOnce({
        tracks: [trackEntry('track-2', 'Two', '/music/two.mp3')],
        skipped: []
      });
    mockReadFile.mockResolvedValue(Buffer.from([9]));

    await openHandler({}, 'replace');
    await openHandler({}, 'replace');

    await expect(readHandler({}, 'track-1')).rejects.toThrow('Track is not authorized');
    expect(bytesFromArrayBuffer(await readHandler({}, 'track-2'))).toEqual([9]);
  });

  it('returns canceled=true and keeps current registry unchanged when dialog is canceled', async () => {
    const { openHandler, readHandler } = await setupIpcHandlers();

    mockShowOpenDialog
      .mockResolvedValueOnce({ canceled: false, filePaths: ['/music/one.mp3'] })
      .mockResolvedValueOnce({ canceled: true, filePaths: [] });
    mockLoadTracksFromPaths.mockResolvedValueOnce({
      tracks: [trackEntry('track-1', 'One', '/music/one.mp3')],
      skipped: []
    });
    mockReadFile.mockResolvedValue(Buffer.from([4, 5]));

    await openHandler({}, 'replace');
    const canceledResult = await openHandler({}, 'replace');

    expect(canceledResult).toMatchObject({
      tracks: [],
      skipped: [],
      canceled: true,
      mode: 'replace'
    });
    expect(mockLoadTracksFromPaths).toHaveBeenCalledTimes(1);

    expect(bytesFromArrayBuffer(await readHandler({}, 'track-1'))).toEqual([4, 5]);
  });

  it('imports a music folder into the persistent library', async () => {
    const { importLibraryFolderHandler } = await setupIpcHandlers();
    const entry = trackEntry('track-1', 'One', '/music/folder/one.mp3');
    const libraryTrack = {
      ...entry.track,
      addedAt: '2026-05-22T00:00:00.000Z',
      updatedAt: '2026-05-22T00:00:00.000Z',
      sourcePath: '/music/folder',
      sourceLabel: 'folder',
      missing: false,
      missingAt: null
    };

    mockShowOpenDialog.mockResolvedValueOnce({
      canceled: false,
      filePaths: ['/music/folder']
    });
    mockLoadTracksFromDirectory.mockResolvedValueOnce({
      tracks: [entry],
      skipped: ['bad.wav: unreadable or corrupted']
    });
    mockUpsertLoadedTracks.mockResolvedValueOnce({
      tracks: [libraryTrack],
      added: 1,
      updated: 0,
      restored: 0,
      missing: 0
    });

    const result = await importLibraryFolderHandler({});

    expect(mockLoadTracksFromDirectory).toHaveBeenCalledWith('/music/folder');
    expect(mockUpsertLoadedTracks).toHaveBeenCalledWith([entry], '/music/folder');
    expect(result).toMatchObject({
      tracks: [libraryTrack],
      added: 1,
      updated: 0,
      restored: 0,
      missing: 0,
      skipped: ['bad.wav: unreadable or corrupted'],
      canceled: false,
      sourcePath: '/music/folder'
    });
  });

  it('adds selected library tracks to the playable playlist registry', async () => {
    const { addLibraryTracksToPlaylistHandler, getTracksHandler, readHandler } =
      await setupIpcHandlers();
    const entry = trackEntry('track-1', 'One', '/music/one.mp3');

    mockGetLibraryEntriesByIds.mockResolvedValueOnce([{ id: 'track-1' }]);
    mockToRegisterEntries.mockReturnValueOnce([
      { trackId: 'track-1', filePath: '/music/one.mp3', track: entry.track }
    ]);
    mockReadFile.mockResolvedValue(Buffer.from([7, 8]));

    const result = await addLibraryTracksToPlaylistHandler(
      {},
      ['track-1', 'missing-track'],
      'replace'
    );

    expect(mockGetLibraryEntriesByIds).toHaveBeenCalledWith(['track-1', 'missing-track']);
    expect(result).toMatchObject({
      tracks: [entry.track],
      skipped: ['missing-track: not in library'],
      canceled: false,
      mode: 'replace'
    });
    expect(await getTracksHandler({})).toMatchObject([{ id: 'track-1', title: 'One' }]);
    expect(bytesFromArrayBuffer(await readHandler({}, 'track-1'))).toEqual([7, 8]);
  });

  it('rescans an imported music folder and returns missing counts', async () => {
    const { rescanLibraryFolderHandler } = await setupIpcHandlers();
    const entry = trackEntry('track-2', 'Two', '/music/folder/two.mp3');
    const libraryTrack = {
      ...entry.track,
      addedAt: '2026-05-22T00:00:00.000Z',
      updatedAt: '2026-05-23T00:00:00.000Z',
      sourcePath: '/music/folder',
      sourceLabel: 'folder',
      missing: false,
      missingAt: null
    };

    mockLoadTracksFromDirectory.mockResolvedValueOnce({
      tracks: [entry],
      skipped: [],
      scannedFilePaths: ['/music/folder/two.mp3']
    });
    mockRescanSource.mockResolvedValueOnce({
      tracks: [libraryTrack],
      added: 1,
      updated: 1,
      restored: 0,
      missing: 2
    });

    const result = await rescanLibraryFolderHandler({}, '/music/folder');

    expect(mockLoadTracksFromDirectory).toHaveBeenCalledWith('/music/folder');
    expect(mockRescanSource).toHaveBeenCalledWith(
      [entry],
      '/music/folder',
      ['/music/folder/two.mp3']
    );
    expect(result).toMatchObject({
      tracks: [libraryTrack],
      added: 1,
      updated: 1,
      restored: 0,
      missing: 2,
      canceled: false,
      sourcePath: '/music/folder'
    });
  });

  it('creates and updates user taste playlists through IPC', async () => {
    const {
      createUserPlaylistHandler,
      renameUserPlaylistHandler,
      setUserPlaylistTracksHandler,
      addLibraryTracksToUserPlaylistHandler,
      deleteUserPlaylistHandler
    } = await setupIpcHandlers();
    const playlist = {
      id: 'playlist-1',
      name: 'Warmup',
      trackIds: ['track-1'],
      createdAt: '2026-05-22T00:00:00.000Z',
      updatedAt: '2026-05-22T00:00:00.000Z'
    };

    mockCreateUserPlaylist.mockResolvedValueOnce({
      playlists: [playlist],
      playlist
    });
    mockRenameUserPlaylist.mockResolvedValueOnce({
      playlists: [{ ...playlist, name: 'Warmup v2' }],
      playlist: { ...playlist, name: 'Warmup v2' }
    });
    mockSetUserPlaylistTracks.mockResolvedValueOnce({
      playlists: [{ ...playlist, trackIds: ['track-2'] }],
      playlist: { ...playlist, trackIds: ['track-2'] }
    });
    mockAddUserPlaylistTrackIds.mockResolvedValueOnce({
      playlists: [{ ...playlist, trackIds: ['track-1', 'track-3'] }],
      playlist: { ...playlist, trackIds: ['track-1', 'track-3'] }
    });
    mockDeleteUserPlaylist.mockResolvedValueOnce({
      playlists: [],
      playlist: null
    });

    await createUserPlaylistHandler({}, '  Warmup  ', ['track-1']);
    await renameUserPlaylistHandler({}, 'playlist-1', 'Warmup v2');
    await setUserPlaylistTracksHandler({}, 'playlist-1', ['track-2']);
    await addLibraryTracksToUserPlaylistHandler({}, 'playlist-1', ['track-3']);
    await deleteUserPlaylistHandler({}, 'playlist-1');

    expect(mockCreateUserPlaylist).toHaveBeenCalledWith('Warmup', ['track-1']);
    expect(mockRenameUserPlaylist).toHaveBeenCalledWith('playlist-1', 'Warmup v2');
    expect(mockSetUserPlaylistTracks).toHaveBeenCalledWith('playlist-1', ['track-2']);
    expect(mockAddUserPlaylistTrackIds).toHaveBeenCalledWith('playlist-1', ['track-3']);
    expect(mockDeleteUserPlaylist).toHaveBeenCalledWith('playlist-1');
  });

  it('loads a saved user playlist into the playable registry', async () => {
    const { loadUserPlaylistHandler, getTracksHandler, readHandler } = await setupIpcHandlers();
    const first = trackEntry('track-1', 'One', '/music/one.mp3');
    const second = trackEntry('track-2', 'Two', '/music/two.mp3');

    mockGetUserPlaylist.mockResolvedValueOnce({
      id: 'playlist-1',
      name: 'Warmup',
      trackIds: ['track-2', 'missing-track', 'track-1'],
      createdAt: '2026-05-22T00:00:00.000Z',
      updatedAt: '2026-05-22T00:00:00.000Z'
    });
    mockGetLibraryEntriesByIds.mockResolvedValueOnce([
      { id: 'track-2', title: 'Two', missing: false },
      { id: 'track-1', title: 'One', missing: false }
    ]);
    mockToRegisterEntries.mockReturnValueOnce([
      { trackId: 'track-2', filePath: '/music/two.mp3', track: second.track },
      { trackId: 'track-1', filePath: '/music/one.mp3', track: first.track }
    ]);
    mockReadFile.mockResolvedValue(Buffer.from([6]));

    const result = await loadUserPlaylistHandler({}, 'playlist-1');

    expect(mockGetLibraryEntriesByIds).toHaveBeenCalledWith([
      'track-2',
      'missing-track',
      'track-1'
    ]);
    expect(result).toMatchObject({
      tracks: [second.track, first.track],
      skipped: ['missing-track: not in library'],
      canceled: false,
      mode: 'replace'
    });
    expect(await getTracksHandler({})).toMatchObject([
      { id: 'track-2', title: 'Two' },
      { id: 'track-1', title: 'One' }
    ]);
    expect(bytesFromArrayBuffer(await readHandler({}, 'track-2'))).toEqual([6]);
  });
});

describe('IPC settings:save', () => {
  beforeEach(() => {
    mockWriteSettings.mockReset();
    mockWriteSettings.mockResolvedValue({
      fadeDurationSec: 8,
      masterGain: 0.9,
      predecodeLeadSec: 20,
      repeatAll: true,
      decodeTimeoutDurationWeightMs: 20,
      decodeTimeoutSizeWeightMs: 200,
      aiDjEnabled: false,
      aiDjMode: 'safe',
      plannerCommand: '',
      plannerArgs: [],
      plannerTimeoutMs: 4000
    });
  });

  it('rejects non-object payload', async () => {
    const { saveSettingsHandler } = await setupIpcHandlers();
    await expect(saveSettingsHandler({}, 'invalid')).rejects.toThrow(
      'Invalid settings payload'
    );
  });

  it('rejects unknown keys and invalid value types', async () => {
    const { saveSettingsHandler } = await setupIpcHandlers();

    await expect(
      saveSettingsHandler({}, { repeatAll: false, unexpected: 'x' })
    ).rejects.toThrow('Unknown setting key: unexpected');
    await expect(saveSettingsHandler({}, { repeatAll: 'false' })).rejects.toThrow(
      'Invalid repeatAll'
    );
    await expect(
      saveSettingsHandler({}, { decodeTimeoutSizeWeightMs: '450' })
    ).rejects.toThrow('Invalid decodeTimeoutSizeWeightMs');
    await expect(saveSettingsHandler({}, { plannerArgs: 'codex' })).rejects.toThrow(
      'Invalid plannerArgs'
    );
  });

  it('accepts valid partial payload and forwards it to settings store', async () => {
    const { saveSettingsHandler } = await setupIpcHandlers();

    await saveSettingsHandler({}, {
      repeatAll: false,
      fadeDurationSec: 12,
      decodeTimeoutDurationWeightMs: 33,
      decodeTimeoutSizeWeightMs: 450
    });

    expect(mockWriteSettings).toHaveBeenCalledWith({
      repeatAll: false,
      fadeDurationSec: 12,
      decodeTimeoutDurationWeightMs: 33,
      decodeTimeoutSizeWeightMs: 450
    });
  });
});

describe('IPC analysis and planner handlers', () => {
  beforeEach(() => {
    mockGetTrackAnalysis.mockReset();
    mockSaveTrackAnalysis.mockReset();
    mockRequestMixPlan.mockReset();
    mockCheckProfile.mockReset();
  });

  it('validates track id before requesting analysis', async () => {
    const { analysisHandler } = await setupIpcHandlers();
    await expect(analysisHandler({}, '')).rejects.toThrow('Invalid track id');
  });

  it('validates and saves renderer-generated track analysis', async () => {
    const { saveAnalysisHandler } = await setupIpcHandlers();
    mockSaveTrackAnalysis.mockResolvedValue({
      trackId: 'a',
      schemaVersion: 2
    });

    await expect(saveAnalysisHandler({}, '', {})).rejects.toThrow('Invalid track id');
    await expect(saveAnalysisHandler({}, 'a', null)).rejects.toThrow(
      'Invalid track analysis payload'
    );

    await saveAnalysisHandler({}, 'a', {
      trackId: 'a',
      bpm: 124,
      beatGridSec: [0, 0.48],
      downbeatsSec: [0],
      analysisConfidence: 0.8
    });

    expect(mockSaveTrackAnalysis).toHaveBeenCalledWith(
      'a',
      expect.objectContaining({
        trackId: 'a',
        bpm: 124,
        analysisConfidence: 0.8
      })
    );
  });

  it('validates planner payload before calling service', async () => {
    const { plannerHandler } = await setupIpcHandlers();
    await expect(plannerHandler({}, { currentTrack: {} })).rejects.toThrow(
      'Invalid currentPlayback.elapsedSec'
    );

    await expect(
      plannerHandler({}, {
        currentTrack: {
          id: 'a',
          title: 'A',
          durationSec: 120,
          format: 'mp3'
        },
        nextTrack: {
          id: 'b',
          title: 'B',
          durationSec: 120,
          format: 'wav'
        },
        currentPlayback: {
          elapsedSec: 15
        },
        settingsOverride: {
          plannerArgs: 'codex'
        }
      })
    ).rejects.toThrow('Invalid plannerArgs');
  });

  it('forwards valid planner payload to the planner service', async () => {
    const { plannerHandler } = await setupIpcHandlers();
    mockRequestMixPlan.mockResolvedValue({
      source: 'fallback',
      plan: null,
      reason: 'ai_dj_disabled'
    });

    await plannerHandler({}, {
      currentTrack: {
        id: 'a',
        title: 'A',
        durationSec: 120,
        format: 'mp3',
        bpm: 124
      },
      nextTrack: {
        id: 'b',
        title: 'B',
        durationSec: 130,
        format: 'wav',
        bpm: 128
      },
      currentPlayback: {
        elapsedSec: 15
      },
      settingsOverride: {
        aiDjEnabled: true,
        aiDjMode: 'balanced',
        plannerCommand: 'codex',
        plannerArgs: ['exec'],
        plannerTimeoutMs: 2000
      }
    });

    expect(mockRequestMixPlan).toHaveBeenCalledWith({
      currentTrack: {
        id: 'a',
        title: 'A',
        durationSec: 120,
        format: 'mp3',
        bpm: 124
      },
      nextTrack: {
        id: 'b',
        title: 'B',
        durationSec: 130,
        format: 'wav',
        bpm: 128
      },
      currentPlayback: {
        elapsedSec: 15
      },
      settingsOverride: {
        aiDjEnabled: true,
        aiDjMode: 'balanced',
        plannerCommand: 'codex',
        plannerArgs: ['exec'],
        plannerTimeoutMs: 2000
      }
    });
  });

  it('validates and forwards ai agent connection checks', async () => {
    const { agentCheckHandler } = await setupIpcHandlers();
    mockCheckProfile.mockResolvedValue({
      profileId: 'codex',
      profileName: 'Codex',
      status: 'ready',
      message: 'Ready',
      checkedAt: '2026-01-01T00:00:00.000Z',
      canRunPlanner: true
    });

    await expect(agentCheckHandler({}, { id: '' })).rejects.toThrow(
      'Invalid aiAgentProfiles id'
    );
    await expect(agentCheckHandler({}, {
      id: 'other-agent',
      name: 'Other Agent',
      kind: 'cli',
      command: 'node',
      args: ['scripts/other-agent.cjs'],
      timeoutMs: 2000,
      enabled: true
    })).rejects.toThrow('Only Codex agent connection checks are supported');

    await agentCheckHandler({}, {
      id: 'codex',
      name: 'Codex',
      kind: 'cli',
      command: 'node',
      args: ['scripts/codex-mix-planner.cjs'],
      timeoutMs: 20000,
      enabled: true
    });

    expect(mockCheckProfile).toHaveBeenCalledWith({
      id: 'codex',
      name: 'Codex',
      kind: 'cli',
      command: 'node',
      args: ['scripts/codex-mix-planner.cjs'],
      timeoutMs: 20000,
      enabled: true
    });
  });
});
