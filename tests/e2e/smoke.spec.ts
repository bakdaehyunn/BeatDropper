import { expect, test } from '@playwright/test';

test('renders BeatDropper shell', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('BeatDropper');
  await expect(page.getByRole('button', { name: 'Load Tracks' })).toBeVisible();
});
