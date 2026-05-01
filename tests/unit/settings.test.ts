import {
  CUSTOM_AGENT_PROFILE_ID,
  DEFAULT_SETTINGS,
  sanitizeSettings
} from '../../src/shared/settings';

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

    expect(result).toMatchObject({
      fadeDurationSec: 6,
      masterGain: 0.75,
      predecodeLeadSec: 18,
      repeatAll: false,
      decodeTimeoutDurationWeightMs: 26,
      decodeTimeoutSizeWeightMs: 320,
      aiDjEnabled: true,
      aiDjMode: 'balanced',
      activeAiAgentProfileId: CUSTOM_AGENT_PROFILE_ID,
      plannerCommand: 'codex',
      plannerArgs: ['exec', '--json'],
      plannerTimeoutMs: 5500
    });
    expect(result.aiAgentProfiles).toContainEqual({
      id: CUSTOM_AGENT_PROFILE_ID,
      name: 'Custom CLI',
      kind: 'cli',
      command: 'codex',
      args: ['exec', '--json'],
      timeoutMs: 5500,
      enabled: true
    });
  });

  it('keeps the selected ai agent profile in sync with legacy planner fields', () => {
    const result = sanitizeSettings({
      aiAgentProfiles: [
        ...DEFAULT_SETTINGS.aiAgentProfiles,
        {
          id: 'test-agent',
          name: 'Test Agent',
          kind: 'cli',
          command: 'node',
          args: ['scripts/test-agent.cjs'],
          timeoutMs: 1200,
          enabled: true
        }
      ],
      activeAiAgentProfileId: 'test-agent'
    });

    expect(result.plannerCommand).toBe('node');
    expect(result.plannerArgs).toEqual(['scripts/test-agent.cjs']);
    expect(result.plannerTimeoutMs).toBe(1200);
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
