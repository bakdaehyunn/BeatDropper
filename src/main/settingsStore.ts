import { app } from 'electron';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { DEFAULT_SETTINGS, sanitizeSettings } from '../shared/settings';
import { PlayerSettings } from '../shared/types';

const SETTINGS_FILE_NAME = 'player-settings.json';

const resolveSettingsPath = (): string => {
  return path.join(app.getPath('userData'), SETTINGS_FILE_NAME);
};

export const readSettings = async (): Promise<PlayerSettings> => {
  try {
    const filePath = resolveSettingsPath();
    const raw = await readFile(filePath, 'utf8');
    const parsed = JSON.parse(raw) as Partial<PlayerSettings>;
    return sanitizeSettings(parsed);
  } catch {
    return DEFAULT_SETTINGS;
  }
};

export const writeSettings = async (
  candidate: Partial<PlayerSettings>
): Promise<PlayerSettings> => {
  const current = await readSettings();
  const next = sanitizeSettings({ ...current, ...candidate });
  const filePath = resolveSettingsPath();
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, JSON.stringify(next, null, 2), 'utf8');
  return next;
};
