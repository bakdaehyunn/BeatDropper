import { DEFAULT_SETTINGS, sanitizeSettings } from '../../src/shared/settings';

describe('sanitizeSettings', () => {
  it('returns defaults when input is empty', () => {
    expect(sanitizeSettings()).toEqual(DEFAULT_SETTINGS);
  });

  it('clamps all numeric ranges', () => {
    const result = sanitizeSettings({
      fadeDurationSec: 100,
      masterGain: -4,
      predecodeLeadSec: 1
    });

    expect(result.fadeDurationSec).toBe(20);
    expect(result.masterGain).toBe(0);
    expect(result.predecodeLeadSec).toBe(3);
  });

  it('keeps valid values as-is', () => {
    const result = sanitizeSettings({
      fadeDurationSec: 6,
      masterGain: 0.75,
      predecodeLeadSec: 18,
      repeatAll: false
    });

    expect(result).toEqual({
      fadeDurationSec: 6,
      masterGain: 0.75,
      predecodeLeadSec: 18,
      repeatAll: false
    });
  });
});
