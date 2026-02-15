import { app, BrowserWindow } from 'electron';
import path from 'node:path';
import { registerIpcHandlers } from './ipc';

const isDev = !app.isPackaged;
const appName = 'BeatDropper';
const appIconPath = path.join(__dirname, '../../public/icons/dropper-icon.png');
const devServerUrl = process.env.VITE_DEV_SERVER_URL;
const devServerOrigin = (() => {
  if (!devServerUrl) {
    return null;
  }

  try {
    return new URL(devServerUrl).origin;
  } catch {
    return null;
  }
})();

const isAllowedAppNavigationUrl = (targetUrl: string): boolean => {
  if (targetUrl.startsWith('file://')) {
    return true;
  }

  if (isDev && devServerOrigin) {
    try {
      return new URL(targetUrl).origin === devServerOrigin;
    } catch {
      return false;
    }
  }

  return false;
};

const createMainWindow = (): BrowserWindow => {
  const window = new BrowserWindow({
    title: appName,
    icon: appIconPath,
    width: 1200,
    height: 840,
    minWidth: 960,
    minHeight: 680,
    webPreferences: {
      preload: path.join(__dirname, '../preload/preload.js'),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
      webSecurity: true
    }
  });

  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event, targetUrl) => {
    if (!isAllowedAppNavigationUrl(targetUrl)) {
      event.preventDefault();
    }
  });

  if (isDev && devServerUrl) {
    void window.loadURL(devServerUrl);
    window.webContents.openDevTools({ mode: 'detach' });
  } else {
    void window.loadFile(path.join(__dirname, '../../dist/index.html'));
  }

  return window;
};

app.whenReady().then(() => {
  app.setName(appName);
  if (process.platform === 'darwin' && app.dock) {
    app.dock.setIcon(appIconPath);
  }

  registerIpcHandlers();
  createMainWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
