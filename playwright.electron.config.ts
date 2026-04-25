import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e-electron',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 45_000,
  webServer: {
    command: 'npm run dev:renderer -- --host 127.0.0.1 --port 4173',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: true
  }
});
