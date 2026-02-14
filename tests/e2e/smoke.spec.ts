import { expect, test } from '@playwright/test';

test('renders Dropper AI shell', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Dropper AI');
  await expect(page.getByRole('button', { name: 'Load Tracks' })).toBeVisible();
});
