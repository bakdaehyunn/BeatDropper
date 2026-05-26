import { app, BrowserWindow, Menu, MenuItemConstructorOptions } from 'electron';
import { AppCommand } from '../shared/appCommand';

interface AppMenuOptions {
  getMainWindow(): BrowserWindow | null;
  isDev: boolean;
}

const separator = (): MenuItemConstructorOptions => ({ type: 'separator' });

const sendAppCommand = (
  getMainWindow: AppMenuOptions['getMainWindow'],
  command: AppCommand
): void => {
  const targetWindow = getMainWindow() ?? BrowserWindow.getFocusedWindow();
  if (!targetWindow || targetWindow.isDestroyed()) {
    return;
  }

  targetWindow.webContents.send('app:command', command);
};

export const installAppMenu = ({ getMainWindow, isDev }: AppMenuOptions): void => {
  const isMac = process.platform === 'darwin';
  const command = (appCommand: AppCommand) => (): void => {
    sendAppCommand(getMainWindow, appCommand);
  };

  const template: MenuItemConstructorOptions[] = [
    ...(isMac
      ? [
          {
            label: app.getName(),
            submenu: [
              { role: 'about' },
              separator(),
              {
                label: 'Settings...',
                accelerator: 'CmdOrCtrl+,',
                click: command('open-settings')
              },
              separator(),
              { role: 'services' },
              separator(),
              { role: 'hide' },
              { role: 'hideOthers' },
              { role: 'unhide' },
              separator(),
              { role: 'quit' }
            ]
          } satisfies MenuItemConstructorOptions
        ]
      : []),
    {
      label: 'File',
      submenu: [
        {
          label: 'New Set...',
          accelerator: 'CmdOrCtrl+O',
          click: command('new-set')
        },
        {
          label: 'Add Tracks...',
          accelerator: 'CmdOrCtrl+Shift+O',
          click: command('add-tracks')
        },
        {
          label: 'Import Music Folder...',
          accelerator: 'CmdOrCtrl+Shift+I',
          click: command('import-folder')
        },
        separator(),
        isMac ? { role: 'close' } : { role: 'quit' }
      ]
    },
    {
      label: 'View',
      submenu: [
        {
          label: 'Show Set',
          accelerator: 'CmdOrCtrl+1',
          click: command('show-set')
        },
        {
          label: 'Show Music Library',
          accelerator: 'CmdOrCtrl+2',
          click: command('show-library')
        },
        {
          label: 'Toggle Inspector',
          accelerator: 'CmdOrCtrl+3',
          click: command('toggle-inspector')
        },
        {
          label: 'Toggle Saved Sets',
          accelerator: 'CmdOrCtrl+Shift+S',
          click: command('toggle-saved-sets')
        },
        separator(),
        { role: 'reload' },
        { role: 'forceReload' },
        ...(isDev
          ? [
              {
                label: 'Toggle Developer Tools',
                accelerator: isMac ? 'Alt+Command+I' : 'Ctrl+Shift+I',
                click: () => {
                  BrowserWindow.getFocusedWindow()?.webContents.toggleDevTools();
                }
              } satisfies MenuItemConstructorOptions
            ]
          : [])
      ]
    },
    {
      label: 'Playback',
      submenu: [
        {
          label: 'Play/Pause',
          accelerator: 'Space',
          click: command('play-pause')
        },
        {
          label: 'Previous Track',
          accelerator: 'CmdOrCtrl+Left',
          click: command('previous-track')
        },
        {
          label: 'Next Track',
          accelerator: 'CmdOrCtrl+Right',
          click: command('next-track')
        }
      ]
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        ...(isMac
          ? ([
              separator(),
              { role: 'front' },
              separator(),
              { role: 'window' }
            ] satisfies MenuItemConstructorOptions[])
          : ([{ role: 'close' }] satisfies MenuItemConstructorOptions[]))
      ]
    },
    {
      role: 'help',
      submenu: [
        {
          label: 'BeatDropper Help',
          click: command('open-settings')
        }
      ]
    }
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
};
