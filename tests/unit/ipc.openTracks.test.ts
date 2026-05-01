const handlerMap = new Map<string, (...args: unknown[]) => unknown>();

const mockShowOpenDialog = vi.fn();
const mockReadFile = vi.fn();
const mockLoadTracksFromPaths = vi.fn();
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
    loadTracksFromPaths: mockLoadTracksFromPaths
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
  const readHandler = handlerMap.get('track:readBufferById');
  const analysisHandler = handlerMap.get('analysis:getByTrackId');
  const saveAnalysisHandler = handlerMap.get('analysis:saveForTrackId');
  const plannerHandler = handlerMap.get('planner:requestMixPlan');
  const agentCheckHandler = handlerMap.get('agent:checkConnection');
  const saveSettingsHandler = handlerMap.get('settings:save');
  if (
    !openHandler ||
    !getTracksHandler ||
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
      profileId: 'custom-cli',
      profileName: 'Custom CLI',
      status: 'ready',
      message: 'Ready',
      checkedAt: '2026-01-01T00:00:00.000Z',
      canRunPlanner: true
    });

    await expect(agentCheckHandler({}, { id: '' })).rejects.toThrow(
      'Invalid aiAgentProfiles id'
    );

    await agentCheckHandler({}, {
      id: 'custom-cli',
      name: 'Custom CLI',
      kind: 'cli',
      command: 'node',
      args: ['scripts/custom.cjs'],
      timeoutMs: 2000,
      enabled: true
    });

    expect(mockCheckProfile).toHaveBeenCalledWith({
      id: 'custom-cli',
      name: 'Custom CLI',
      kind: 'cli',
      command: 'node',
      args: ['scripts/custom.cjs'],
      timeoutMs: 2000,
      enabled: true
    });
  });
});
