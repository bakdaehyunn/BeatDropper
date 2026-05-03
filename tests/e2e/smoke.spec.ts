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
    const makeAnalysis = (trackId: string, bpm: number, durationSec: number) => {
      const waveformDetail = Array.from({ length: 180 }, (_, index) => ({
        timeSec: index * (durationSec / 180),
        peak: 0.25 + (index % 8) * 0.08,
        rms: 0.18 + (index % 6) * 0.06,
        min: -0.2 - (index % 5) * 0.05,
        max: 0.2 + (index % 7) * 0.06
      }));
      return {
      schemaVersion: 3,
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
      waveformDetail,
      spectralBands: waveformDetail.map((point, index) => ({
        timeSec: point.timeSec,
        low: 0.3 + (index % 6) * 0.08,
        mid: 0.25 + (index % 5) * 0.1,
        high: 0.2 + (index % 4) * 0.12
      })),
      transientMarkers: Array.from({ length: 12 }, (_, index) => ({
        index,
        timeSec: index * 8,
        strength: 0.55 + (index % 3) * 0.12
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
      analysisQuality: {
        waveformDetail: 0.85,
        spectralBands: 0.85,
        transientMarkers: 0.64,
        beatGrid: 0.8
      },
      analysisWarnings: []
    };
    };
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
  const plannerStatus = page.getByLabel('AI mix planner status');
  await expect(plannerStatus).toBeVisible();
  await expect(plannerStatus.getByText('Agent')).toBeVisible();
  await expect(plannerStatus.getByText('Plan')).toBeVisible();
  await expect(plannerStatus.getByText('Tempo')).toBeVisible();
  await expect(page.getByRole('heading', { level: 2, name: 'Playlist' })).toBeVisible();
  await expect(page.getByRole('heading', { level: 2, name: 'Mix Pair Inspector' })).toBeVisible();
  await expect(page.locator('.supervisor-waveform.current')).toBeVisible();
  await expect(page.locator('.supervisor-waveform.next')).toBeVisible();
  await expect(page.locator('.supervisor-cursor.mix-out')).toBeVisible();
  await expect(page.locator('.supervisor-cursor.mix-in')).toBeVisible();
  await expect(page.locator('.supervisor-phrase-marker').first()).toBeVisible();
  await expect(page.locator('.supervisor-transient').first()).toBeVisible();
  const waveformMetrics = await page.evaluate(() => {
    const current = document.querySelector('.supervisor-waveform.current');
    const next = document.querySelector('.supervisor-waveform.next');
    const currentRect = current?.getBoundingClientRect();
    const nextRect = next?.getBoundingClientRect();
    return {
      currentHeight: currentRect?.height ?? 0,
      nextHeight: nextRect?.height ?? 0,
      currentPeaks: current?.querySelectorAll('.supervisor-peak').length ?? 0,
      nextPeaks: next?.querySelectorAll('.supervisor-peak').length ?? 0
    };
  });

  expect(waveformMetrics.currentHeight).toBeGreaterThanOrEqual(68);
  expect(waveformMetrics.nextHeight).toBeGreaterThanOrEqual(68);
  expect(waveformMetrics.currentPeaks).toBeGreaterThanOrEqual(90);
  expect(waveformMetrics.nextPeaks).toBeGreaterThanOrEqual(90);

  const overflow = await page.evaluate(() => {
    const selectors = [
      '.app-shell',
      '.live-mix-panel',
      '.live-ai-statusbar',
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

test('contains long playlist scrolling inside the playlist table', async ({ page }) => {
  await page.setViewportSize({ width: 1217, height: 841 });
  await page.addInitScript(() => {
    const settings = {
      fadeDurationSec: 8,
      masterGain: 0.9,
      predecodeLeadSec: 20,
      repeatAll: true
    };
    const tracks = Array.from({ length: 24 }, (_, index) => ({
      id: `track-${index + 1}`,
      title: `Set track ${String(index + 1).padStart(2, '0')}.wav`,
      durationSec: 180 + index,
      format: 'wav',
      bpm: 120 + (index % 8)
    }));
    const makeAnalysis = (trackId: string, bpm: number, durationSec: number) => ({
      schemaVersion: 3,
      trackId,
      generatedAt: new Date().toISOString(),
      source: 'derived',
      bpm,
      bpmConfidence: 0.85,
      beatGridSec: Array.from({ length: 48 }, (_, index) => index * (60 / bpm)),
      downbeatsSec: Array.from({ length: 12 }, (_, index) => index * 4 * (60 / bpm)),
      barGrid: Array.from({ length: 12 }, (_, index) => ({
        index,
        startSec: index * 4 * (60 / bpm),
        beatIndex: index * 4
      })),
      phraseMarkers: [{ index: 0, startSec: 0, bars: 8, confidence: 0.8 }],
      introCueSec: 0,
      outroCueSec: Math.max(0, durationSec - 16),
      energyProfile: [0.25, 0.44, 0.62, 0.5],
      waveformPeaks: Array.from({ length: 48 }, (_, index) => ({
        timeSec: index * (durationSec / 48),
        peak: 0.25 + (index % 8) * 0.08,
        rms: 0.18 + (index % 6) * 0.06
      })),
      waveformDetail: Array.from({ length: 120 }, (_, index) => ({
        timeSec: index * (durationSec / 120),
        peak: 0.25 + (index % 8) * 0.08,
        rms: 0.18 + (index % 6) * 0.06,
        min: -0.24,
        max: 0.24
      })),
      spectralBands: [],
      transientMarkers: [],
      cueCandidates: [],
      analysisConfidence: 0.8,
      analysisQuality: {
        waveformDetail: 0.8,
        spectralBands: 0,
        transientMarkers: 0,
        beatGrid: 0.8
      },
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
        throw new Error('No planner request expected in long playlist layout test');
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
  const playlist = page.getByLabel('Playlist tracks');
  await expect(playlist).toBeVisible();

  const metrics = await page.evaluate(() => {
    const list = document.querySelector('.playlist-table-body');
    const app = document.querySelector('.app-shell');
    if (!(list instanceof HTMLElement) || !(app instanceof HTMLElement)) {
      return null;
    }
    const before = list.scrollTop;
    list.scrollTop = 180;
    const listStyle = window.getComputedStyle(list);
    return {
      appOverflow: app.scrollHeight - app.clientHeight,
      listOverflow: list.scrollHeight - list.clientHeight,
      scrolled: list.scrollTop > before,
      overflowY: listStyle.overflowY,
      scrollbarGutter: listStyle.scrollbarGutter
    };
  });

  expect(metrics).not.toBeNull();
  expect(metrics?.appOverflow).toBeLessThanOrEqual(1);
  expect(metrics?.listOverflow).toBeGreaterThan(80);
  expect(metrics?.scrolled).toBe(true);
  expect(metrics?.overflowY).toBe('auto');
  expect(metrics?.scrollbarGutter).toContain('stable');
});
