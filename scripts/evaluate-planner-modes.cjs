#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { buildHeuristicResponse } = require('./heuristic-mix-planner.cjs');

const fixtureDir = path.resolve(__dirname, '..', 'tests', 'fixtures', 'planner-requests');
const modes = ['safe', 'balanced', 'adventurous'];

const loadFixtures = () => {
  return fs
    .readdirSync(fixtureDir)
    .filter((name) => name.endsWith('.json'))
    .sort()
    .map((name) => ({
      name,
      request: JSON.parse(fs.readFileSync(path.join(fixtureDir, name), 'utf8'))
    }));
};

const main = () => {
  const fixtures = loadFixtures();

  for (const fixture of fixtures) {
    process.stdout.write(`\n# ${fixture.name}\n`);
    for (const mode of modes) {
      const response = buildHeuristicResponse({
        ...fixture.request,
        settings: {
          ...fixture.request.settings,
          aiDjMode: mode
        }
      });
      const mixPlan = response.mixPlan;
      process.stdout.write(
        [
          `${mode}:`,
          `window ${mixPlan.transitionStartSec.toFixed(2)} -> ${mixPlan.transitionEndSec.toFixed(2)}`,
          `offset ${mixPlan.nextTrackStartOffsetSec.toFixed(2)}`,
          `style ${mixPlan.style}`,
          `tempo ${mixPlan.tempoSync.enabled ? mixPlan.tempoSync.targetRate.toFixed(3) : 'off'}`,
          `confidence ${mixPlan.confidence.toFixed(2)}`
        ].join(' | ') + '\n'
      );
    }
  }
};

main();
