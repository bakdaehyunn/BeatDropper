import { DEFAULT_SETTINGS, sanitizeSettings } from '../../src/shared/settings';

describe('sanitizeSettings', () => {
  it('returns defaults when input is empty', () => {
    expect(sanitizeSettings()).toEqual(DEFAULT_SETTINGS);
  });

  it('clamps all numeric ranges', () => {
    const result = sanitizeSettings({
      fadeDurationSec: 100,
      masterGain: -4,
      predecodeLeadSec: 1,
      decodeTimeoutDurationWeightMs: 999,
      decodeTimeoutSizeWeightMs: -20,
      plannerTimeoutMs: 999999
    });

    expect(result.fadeDurationSec).toBe(20);
    expect(result.masterGain).toBe(0);
    expect(result.predecodeLeadSec).toBe(3);
    expect(result.decodeTimeoutDurationWeightMs).toBe(80);
    expect(result.decodeTimeoutSizeWeightMs).toBe(0);
    expect(result.plannerTimeoutMs).toBe(30_000);
  });

  it('keeps valid values as-is', () => {
    const result = sanitizeSettings({
      fadeDurationSec: 6,
      masterGain: 0.75,
      predecodeLeadSec: 18,
      repeatAll: false,
      decodeTimeoutDurationWeightMs: 26,
      decodeTimeoutSizeWeightMs: 320,
      aiDjEnabled: true,
      aiDjMode: 'balanced',
      plannerCommand: 'codex',
      plannerArgs: ['exec', '--json'],
      plannerTimeoutMs: 5500
    });

    expect(result).toEqual({
      fadeDurationSec: 6,
      masterGain: 0.75,
      predecodeLeadSec: 18,
      repeatAll: false,
      decodeTimeoutDurationWeightMs: 26,
      decodeTimeoutSizeWeightMs: 320,
      aiDjEnabled: true,
      aiDjMode: 'balanced',
      plannerCommand: 'codex',
      plannerArgs: ['exec', '--json'],
      plannerTimeoutMs: 5500
    });
  });

  it('falls back to default repeatAll when payload type is invalid', () => {
    const result = sanitizeSettings({
      repeatAll: 'false' as unknown as boolean
    });

    expect(result.repeatAll).toBe(DEFAULT_SETTINGS.repeatAll);
  });

  it('falls back to defaults for invalid ai dj config payloads', () => {
    const result = sanitizeSettings({
      aiDjMode: 'wild' as never,
      plannerArgs: 'codex exec' as never
    });

    expect(result.aiDjMode).toBe(DEFAULT_SETTINGS.aiDjMode);
    expect(result.plannerArgs).toEqual(DEFAULT_SETTINGS.plannerArgs);
  });
});
