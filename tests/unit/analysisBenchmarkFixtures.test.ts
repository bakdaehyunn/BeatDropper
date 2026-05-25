import fs from 'node:fs';
import path from 'node:path';
import {
  AnalysisBenchmarkFixture,
  evaluateAnalysisBenchmarkFixture,
  evaluateAnalysisBenchmarkSuite
} from '../../src/shared/analysisBenchmark';

const fixtureDir = path.resolve(__dirname, '..', 'fixtures', 'analysis-benchmarks');

const loadFixtures = (): AnalysisBenchmarkFixture[] =>
  fs
    .readdirSync(fixtureDir)
    .filter((name) => name.endsWith('.json'))
    .sort()
    .map((name) => JSON.parse(fs.readFileSync(path.join(fixtureDir, name), 'utf8')));

describe('analysis benchmark fixtures', () => {
  it('loads synthetic fixtures and evaluates their expected grades', () => {
    const fixtures = loadFixtures();
    const results = fixtures.map(evaluateAnalysisBenchmarkFixture);

    expect(fixtures.map((fixture) => fixture.id).sort()).toEqual([
      'clean-124-phrase',
      'shifted-downbeat-warn',
      'weak-ambiguous-fail'
    ]);
    expect(fixtures.every((fixture) => fixture.kind === 'synthetic')).toBe(true);
    for (const fixture of fixtures) {
      const result = results.find((item) => item.fixtureId === fixture.id);
      expect(result?.grade).toBe(fixture.expectedGrade);
      expect(result?.kind).toBe('synthetic');
    }
  });

  it('summarizes the benchmark suite for regression reporting', () => {
    const suite = evaluateAnalysisBenchmarkSuite(loadFixtures());

    expect(suite.grade).toBe('fail');
    expect(suite.passed).toBe(1);
    expect(suite.warned).toBe(1);
    expect(suite.failed).toBe(1);
    expect(suite.results).toHaveLength(3);
    expect(suite.byKind).toEqual([
      expect.objectContaining({
        kind: 'synthetic',
        total: 3,
        passed: 1,
        warned: 1,
        failed: 1
      })
    ]);
    expect(suite.score).toBeGreaterThan(0);
    expect(suite.score).toBeLessThan(1);
  });
});
