import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);

const { buildHeuristicResponse } = require('../../scripts/heuristic-mix-planner.cjs') as {
  buildHeuristicResponse: (request: Record<string, unknown>) => {
    mixPlan: {
      transitionStartSec: number;
      style: string;
      nextTrackStartOffsetSec: number;
      tempoSync: {
        enabled: boolean;
      };
    };
  };
};

const fixtureDir = path.resolve(__dirname, '..', 'fixtures', 'planner-requests');

const loadFixture = (name: string): Record<string, unknown> => {
  return JSON.parse(fs.readFileSync(path.join(fixtureDir, name), 'utf8'));
};

const withMode = (request: Record<string, unknown>, mode: 'safe' | 'balanced' | 'adventurous') => {
  const settings =
    typeof request.settings === 'object' && request.settings !== null
      ? (request.settings as Record<string, unknown>)
      : {};
  return {
    ...request,
    settings: {
      ...settings,
      aiDjMode: mode
    }
  };
};

describe('planner mode regression corpus', () => {
  it('keeps cue-rich close-bpm fixtures conservative until adventurous mode', () => {
    const fixture = loadFixture('cue-rich-close-bpm.json');
    const safe = buildHeuristicResponse(withMode(fixture, 'safe'));
    const balanced = buildHeuristicResponse(withMode(fixture, 'balanced'));
    const adventurous = buildHeuristicResponse(withMode(fixture, 'adventurous'));

    expect(safe.mixPlan.style).toBe('smooth_blend');
    expect(balanced.mixPlan.style).toBe('smooth_blend');
    expect(adventurous.mixPlan.style).toBe('energy_swap');
    expect(safe.mixPlan.transitionStartSec).toBeLessThan(balanced.mixPlan.transitionStartSec);
    expect(balanced.mixPlan.transitionStartSec).toBeLessThan(adventurous.mixPlan.transitionStartSec);
  });

  it('pushes sparse cue / big bpm gap fixtures toward harder adventurous transitions', () => {
    const fixture = loadFixture('sparse-cues-big-gap.json');
    const safe = buildHeuristicResponse(withMode(fixture, 'safe'));
    const balanced = buildHeuristicResponse(withMode(fixture, 'balanced'));
    const adventurous = buildHeuristicResponse(withMode(fixture, 'adventurous'));

    expect(safe.mixPlan.style).toBe('smooth_blend');
    expect(balanced.mixPlan.style).toBe('smooth_blend');
    expect(adventurous.mixPlan.style).toBe('hard_cut');
    expect(safe.mixPlan.tempoSync.enabled).toBe(false);
    expect(adventurous.mixPlan.tempoSync.enabled).toBe(false);
  });

  it('uses partial cue information to keep next-track offsets and moderate balanced behavior', () => {
    const fixture = loadFixture('partial-cues-mid-gap.json');
    const safe = buildHeuristicResponse(withMode(fixture, 'safe'));
    const balanced = buildHeuristicResponse(withMode(fixture, 'balanced'));
    const adventurous = buildHeuristicResponse(withMode(fixture, 'adventurous'));

    expect(safe.mixPlan.nextTrackStartOffsetSec).toBe(0);
    expect(balanced.mixPlan.nextTrackStartOffsetSec).toBe(0);
    expect(adventurous.mixPlan.nextTrackStartOffsetSec).toBe(0);
    expect(safe.mixPlan.style).toBe('smooth_blend');
    expect(['smooth_blend', 'energy_swap']).toContain(balanced.mixPlan.style);
    expect(['energy_swap', 'hard_cut']).toContain(adventurous.mixPlan.style);
  });
});
