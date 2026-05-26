import { expect, test } from '@playwright/test';
import { _electron as electron } from 'playwright';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { DEFAULT_SETTINGS } from '../../src/shared/settings';

test('exposes preload API and executes IPC settings flow in Electron', async () => {
  const tempHome = await mkdtemp(path.join(os.tmpdir(), 'beatdropper-e2e-'));
  const userDataDir = path.join(tempHome, 'user-data');
  await mkdir(userDataDir, { recursive: true });
  const electronApp = await electron.launch({
    args: ['.'],
    env: {
      ...process.env,
      HOME: tempHome,
      USERPROFILE: tempHome,
      XDG_CONFIG_HOME: path.join(tempHome, '.config'),
      BEATDROPPER_USER_DATA_DIR: userDataDir,
      VITE_DEV_SERVER_URL: 'http://127.0.0.1:4173',
      BEATDROPPER_OPEN_DEVTOOLS: '0'
    }
  });

  try {
    const page = await electronApp.firstWindow();
    await page.waitForURL(/127\.0\.0\.1:4173/, { timeout: 15_000 });
    await page.waitForLoadState('domcontentloaded');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('BeatDropper');

    const apiKeys = await page.evaluate(() => {
      const exposed = (window as Window & { dropperApi?: Record<string, unknown> }).dropperApi;
      return Object.keys(exposed ?? {});
    });

    expect(apiKeys).toEqual(
      expect.arrayContaining([
        'openTracks',
        'getTracks',
        'setTrackOrder',
        'clearTracks',
        'getLibraryTracks',
        'importLibraryFolder',
        'rescanLibraryFolder',
        'addLibraryTracksToPlaylist',
        'getUserPlaylists',
        'createUserPlaylist',
        'renameUserPlaylist',
        'deleteUserPlaylist',
        'setUserPlaylistTracks',
        'addLibraryTracksToUserPlaylist',
        'loadUserPlaylist',
        'readTrackBufferById',
        'getTrackAnalysis',
        'saveTrackAnalysis',
        'requestMixPlan',
        'getSettings',
        'saveSettings',
        'onAppCommand',
        'minimizeWindow',
        'toggleMaximizeWindow',
        'closeWindow'
      ])
    );

    const applicationMenu = await electronApp.evaluate(({ Menu }) => {
      const menu = Menu.getApplicationMenu();
      return {
        topLevel: menu?.items.map((item) => item.label) ?? [],
        fileItems: menu?.items
          .find((item) => item.label === 'File')
          ?.submenu?.items.map((item) => item.label) ?? [],
        playbackItems: menu?.items
          .find((item) => item.label === 'Playback')
          ?.submenu?.items.map((item) => item.label) ?? []
      };
    });
    expect(applicationMenu.topLevel).toEqual(
      expect.arrayContaining(['BeatDropper', 'File', 'View', 'Playback', 'Window', 'Help'])
    );
    expect(applicationMenu.fileItems).toEqual(
      expect.arrayContaining(['New Set...', 'Add Tracks...', 'Import Music Folder...'])
    );
    expect(applicationMenu.playbackItems).toEqual(
      expect.arrayContaining(['Play/Pause', 'Previous Track', 'Next Track'])
    );

    const defaultSettings = await page.evaluate(async () => {
      const exposed = (window as Window & {
        dropperApi: {
          getSettings: () => Promise<Record<string, unknown>>;
        };
      }).dropperApi;
      return exposed.getSettings();
    });
    expect(defaultSettings).toMatchObject({
      fadeDurationSec: 8,
      masterGain: 0.9,
      predecodeLeadSec: 20,
      repeatAll: true
    });

    await page.evaluate(async () => {
      const exposed = (window as Window & {
        dropperApi: {
          saveSettings: (candidate: Record<string, unknown>) => Promise<Record<string, unknown>>;
        };
      }).dropperApi;
      await exposed.saveSettings({
        fadeDurationSec: 11,
        repeatAll: false,
        aiDjEnabled: true,
        aiDjMode: 'balanced',
        plannerCommand: 'node',
        plannerArgs: ['scripts/codex-mix-planner.cjs'],
        plannerTimeoutMs: 9000
      });
    });

    const savedSettings = await page.evaluate(async () => {
      const exposed = (window as Window & {
        dropperApi: {
          getSettings: () => Promise<Record<string, unknown>>;
        };
      }).dropperApi;
      return exposed.getSettings();
    });
    expect(savedSettings).toMatchObject({
      fadeDurationSec: 11,
      repeatAll: false,
      aiDjEnabled: true,
      aiDjMode: 'balanced',
      plannerCommand: 'node',
      plannerArgs: ['scripts/codex-mix-planner.cjs'],
      plannerTimeoutMs: DEFAULT_SETTINGS.plannerTimeoutMs
    });

    const readBufferError = await page.evaluate(async () => {
      const exposed = (window as Window & {
        dropperApi: {
          readTrackBufferById: (trackId: string) => Promise<ArrayBuffer>;
        };
      }).dropperApi;

      try {
        await exposed.readTrackBufferById('unknown-track');
        return null;
      } catch (error) {
        const message =
          error instanceof Error && error.message
            ? error.message
            : String(error ?? 'unknown error');
        return message;
      }
    });
    expect(readBufferError).toContain('Track is not authorized');
  } finally {
    await electronApp.close();
    await rm(tempHome, { recursive: true, force: true });
  }
});
