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
      readTrackBufferById: async () => new ArrayBuffer(0),
      getSettings: async () => settings,
      saveSettings: async () => settings
    };
  });

  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('BeatDropper');
  await expect(page.getByRole('button', { name: 'Load as New' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Add to Current' })).toBeDisabled();
  await expect(page.getByRole('heading', { level: 2, name: 'Auto DJ Queue' })).toBeVisible();
});
