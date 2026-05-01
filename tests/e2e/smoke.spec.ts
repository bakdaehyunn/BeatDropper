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
  await expect(page.getByRole('heading', { level: 2, name: 'Auto DJ Queue' })).toBeVisible();
  await page.getByRole('button', { name: 'Open settings' }).click();
  await expect(page.getByRole('heading', { level: 3, name: 'AI Agent Mixer' })).toBeVisible();
  await expect(page.getByLabel('Active agent')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Check connection' })).toBeVisible();
});
