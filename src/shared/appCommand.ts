export const APP_COMMANDS = [
  'new-set',
  'add-tracks',
  'import-folder',
  'show-set',
  'show-library',
  'toggle-saved-sets',
  'toggle-inspector',
  'open-settings',
  'play-pause',
  'previous-track',
  'next-track'
] as const;

export type AppCommand = (typeof APP_COMMANDS)[number];

const APP_COMMAND_SET = new Set<string>(APP_COMMANDS);

export const isAppCommand = (value: unknown): value is AppCommand => {
  return typeof value === 'string' && APP_COMMAND_SET.has(value);
};
