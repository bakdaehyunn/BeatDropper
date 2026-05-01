import { expect, test } from '@playwright/test';

test('renders BeatDropper shell', async ({ page }) => {
  await page.addInitScript(() => {
    const settings = {
      fadeDurationSec: 8,
      masterGain: 0.9,
      predecodeLeadSec: 20,
      repeatAll: true
    };
    (window as Window & { dropperApi?: unknown }).dropperApi = {
      openTracks: async (mode: 'replace' | 'append') => ({
        tracks: [],
        skipped: [],
        canceled: true,
        mode
      }),
      getTracks: async () => [],
      setTrackOrder: async () => [],
      clearTracks: async () => undefined,
      readTrackBufferById: async () => new ArrayBuffer(0),
      getTrackAnalysis: async () => null,
      saveTrackAnalysis: async (_trackId: string, analysis: unknown) => analysis,
      requestMixPlan: async () => {
        throw new Error('No planner request expected in smoke test');
      },
      checkAiAgentConnection: async () => ({
        profileId: 'local-heuristic',
        profileName: 'Local Heuristic',
        status: 'local_ready',
        message: 'Local heuristic planner is ready.',
        checkedAt: new Date().toISOString(),
        canRunPlanner: true
      }),
      getSettings: async () => settings,
      saveSettings: async () => settings,
      minimizeWindow: async () => undefined,
      toggleMaximizeWindow: async () => undefined,
      closeWindow: async () => undefined
    };
  });

  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('BeatDropper');
  await expect(page.getByRole('button', { name: 'New Set' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Add Tracks' })).toBeDisabled();
  await expect(page.getByRole('heading', { level: 2, name: 'Live Mix Monitor' })).toBeVisible();
  await page.getByRole('button', { name: 'Open settings' }).click();
  await expect(page.getByRole('heading', { level: 3, name: 'AI Agent Mixer' })).toBeVisible();
  await expect(page.getByLabel('Active agent')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Check connection' })).toBeVisible();
});

test('keeps playlist and mix inspector visible without internal scrollbars', async ({ page }) => {
  await page.setViewportSize({ width: 1217, height: 841 });
  await page.addInitScript(() => {
    const settings = {
      fadeDurationSec: 8,
      masterGain: 0.9,
      predecodeLeadSec: 20,
      repeatAll: true
    };
    const tracks = [
      {
        id: 'track-1',
        title: 'rezonate - underground finished.wav',
        durationSec: 253,
        format: 'wav',
        bpm: 167
      },
      {
        id: 'track-2',
        title: '_Mix and Master_ DREAMSTATE rezonated211.wav',
        durationSec: 204,
        format: 'wav',
        bpm: 168
      },
      {
        id: 'track-3',
        title: 'CANT HOLD ME BACK (FINAL VERSION)1 pppp.wav',
        durationSec: 229,
        format: 'wav',
        bpm: 132
      }
    ];
    const makeAnalysis = (trackId: string, bpm: number, durationSec: number) => ({
      schemaVersion: 2,
      trackId,
      generatedAt: new Date().toISOString(),
      source: 'derived',
      bpm,
      bpmConfidence: 0.9,
      beatGridSec: Array.from({ length: 64 }, (_, index) => index * (60 / bpm)),
      downbeatsSec: Array.from({ length: 16 }, (_, index) => index * 4 * (60 / bpm)),
      barGrid: Array.from({ length: 16 }, (_, index) => ({
        index,
        startSec: index * 4 * (60 / bpm),
        beatIndex: index * 4
      })),
      phraseMarkers: [
        { index: 0, startSec: 0, bars: 8, confidence: 0.8 },
        { index: 1, startSec: 8 * 4 * (60 / bpm), bars: 8, confidence: 0.8 }
      ],
      introCueSec: 0,
      outroCueSec: Math.max(0, durationSec - 16),
      energyProfile: [0.2, 0.45, 0.68, 0.72, 0.55, 0.5, 0.34, 0.2],
      waveformPeaks: Array.from({ length: 48 }, (_, index) => ({
        timeSec: index * (durationSec / 48),
        peak: 0.25 + (index % 8) * 0.08,
        rms: 0.18 + (index % 6) * 0.06
      })),
      cueCandidates: [
        { id: 'intro-0', type: 'intro', startSec: 0, endSec: 8, confidence: 0.7, label: 'Intro' },
        {
          id: 'outro-0',
          type: 'outro',
          startSec: Math.max(0, durationSec - 16),
          endSec: durationSec,
          confidence: 0.75,
          label: 'Outro'
        }
      ],
      analysisConfidence: 0.86,
      analysisWarnings: []
    });
    const analyses = Object.fromEntries(
      tracks.map((track) => [track.id, makeAnalysis(track.id, track.bpm, track.durationSec)])
    );
    (window as Window & { dropperApi?: unknown }).dropperApi = {
      openTracks: async (mode: 'replace' | 'append') => ({
        tracks,
        skipped: [],
        canceled: false,
        mode
      }),
      getTracks: async () => tracks,
      setTrackOrder: async () => [],
      clearTracks: async () => undefined,
      readTrackBufferById: async () => new ArrayBuffer(0),
      getTrackAnalysis: async (trackId: string) => analyses[trackId],
      saveTrackAnalysis: async (_trackId: string, analysis: unknown) => analysis,
      requestMixPlan: async () => {
        throw new Error('No planner request expected in layout test');
      },
      checkAiAgentConnection: async () => ({
        profileId: 'local-heuristic',
        profileName: 'Local Heuristic',
        status: 'local_ready',
        message: 'Local heuristic planner is ready.',
        checkedAt: new Date().toISOString(),
        canRunPlanner: true
      }),
      getSettings: async () => settings,
      saveSettings: async () => settings,
      minimizeWindow: async () => undefined,
      toggleMaximizeWindow: async () => undefined,
      closeWindow: async () => undefined
    };
  });

  await page.goto('/');
  await expect(page.getByRole('heading', { level: 2, name: 'Live Mix Monitor' })).toBeVisible();
  await expect(page.getByRole('heading', { level: 2, name: 'Playlist' })).toBeVisible();
  await expect(page.getByRole('heading', { level: 2, name: 'Mix Pair Inspector' })).toBeVisible();
  await expect(page.locator('.supervisor-waveform.current')).toBeVisible();
  await expect(page.locator('.supervisor-waveform.next')).toBeVisible();
  await expect(page.locator('.supervisor-cursor.mix-out')).toBeVisible();
  await expect(page.locator('.supervisor-cursor.mix-in')).toBeVisible();

  const overflow = await page.evaluate(() => {
    const selectors = [
      '.app-shell',
      '.live-mix-panel',
      '.supervisor-wave-stack',
      '.supervisor-waveform.current',
      '.supervisor-waveform.next',
      '.playlist-table-wrap',
      '.playlist-table-body',
      '.analysis-panel',
      '.analysis-grid',
      '.candidate-list'
    ];
    return selectors.map((selector) => {
      const element = document.querySelector(selector);
      return {
        selector,
        horizontal: element ? element.scrollWidth - element.clientWidth : 0,
        vertical: element ? element.scrollHeight - element.clientHeight : 0
      };
    });
  });

  for (const item of overflow) {
    expect(item.horizontal, `${item.selector} horizontal overflow`).toBeLessThanOrEqual(1);
    expect(item.vertical, `${item.selector} vertical overflow`).toBeLessThanOrEqual(1);
  }
});
