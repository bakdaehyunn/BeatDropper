import { resolveTempoSyncDecision } from '../../src/renderer/player/tempoSyncPolicy';

describe('resolveTempoSyncDecision', () => {
  it('applies sync when bpm gap is small', () => {
    const decision = resolveTempoSyncDecision(124, 128);

    expect(decision.mode).toBe('apply');
    if (decision.mode === 'apply') {
      expect(decision.targetRate).toBeCloseTo(0.96875, 3);
      expect(decision.residualMismatchPct).toBeLessThanOrEqual(4);
    }
  });

  it('skips sync when residual mismatch is too high', () => {
    const decision = resolveTempoSyncDecision(100, 140);

    expect(decision.mode).toBe('skip');
    if (decision.mode === 'skip') {
      expect(decision.reason).toBe('residual_too_high');
    }
  });

  it('skips sync when bpm data is missing', () => {
    const decision = resolveTempoSyncDecision(120, null);

    expect(decision.mode).toBe('skip');
    if (decision.mode === 'skip') {
      expect(decision.reason).toBe('missing_bpm');
    }
  });
});
