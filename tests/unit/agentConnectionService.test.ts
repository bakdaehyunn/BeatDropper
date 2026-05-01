import { EventEmitter } from 'node:events';
import { AgentConnectionService } from '../../src/main/aiDj/agentConnectionService';
import {
  CODEX_AGENT_PROFILE_ID,
  HEURISTIC_AGENT_PROFILE_ID
} from '../../src/shared/settings';
import { PLANNER_SCHEMA_VERSION } from '../../src/shared/plannerContract';

class FakeStream extends EventEmitter {
  setEncoding(): void {
    return;
  }

  write(): void {
    return;
  }

  end(): void {
    return;
  }
}

class FakeChildProcess extends EventEmitter {
  stdout = new FakeStream();
  stderr = new FakeStream();
  stdin = new FakeStream();
  kill = vi.fn();
}

const validPlannerResponse = JSON.stringify({
  schemaVersion: PLANNER_SCHEMA_VERSION,
  mixPlan: {
    transitionStartSec: 140,
    transitionEndSec: 148,
    nextTrackStartOffsetSec: 8,
    style: 'smooth_blend',
    confidence: 0.84,
    reasoningSummary: 'connection test',
    tempoSync: {
      enabled: false,
      targetRate: null
    }
  },
  error: null
});

describe('AgentConnectionService', () => {
  it('marks the local heuristic profile ready when it returns a valid MixPlan response', async () => {
    const child = new FakeChildProcess();
    const service = new AgentConnectionService(() => child as never);

    const promise = service.checkProfile({
      id: HEURISTIC_AGENT_PROFILE_ID,
      name: 'Local Heuristic',
      kind: 'cli',
      command: 'node',
      args: ['scripts/heuristic-mix-planner.cjs'],
      timeoutMs: 4000,
      enabled: true
    });

    child.stdout.emit('data', validPlannerResponse);
    child.emit('close', 0);

    await expect(promise).resolves.toMatchObject({
      status: 'local_ready',
      canRunPlanner: true,
      message: 'Local heuristic planner is ready.'
    });
  });

  it('checks Codex CLI availability before running the Codex planner wrapper', async () => {
    const versionChild = new FakeChildProcess();
    const plannerChild = new FakeChildProcess();
    const spawnProcess = vi
      .fn()
      .mockReturnValueOnce(versionChild)
      .mockReturnValueOnce(plannerChild);
    const service = new AgentConnectionService(spawnProcess);

    const promise = service.checkProfile({
      id: CODEX_AGENT_PROFILE_ID,
      name: 'Codex CLI',
      kind: 'cli',
      command: 'node',
      args: ['scripts/codex-mix-planner.cjs'],
      timeoutMs: 20000,
      enabled: true
    });

    versionChild.stdout.emit('data', 'codex 0.1.0');
    versionChild.emit('close', 0);
    await new Promise((resolve) => setTimeout(resolve, 0));
    plannerChild.stdout.emit('data', validPlannerResponse);
    plannerChild.emit('close', 0);

    await expect(promise).resolves.toMatchObject({
      status: 'ready',
      canRunPlanner: true,
      details: {
        codexVersion: 'codex 0.1.0'
      }
    });
    expect(spawnProcess).toHaveBeenNthCalledWith(1, 'codex', ['--version']);
    expect(spawnProcess).toHaveBeenNthCalledWith(2, 'node', [
      'scripts/codex-mix-planner.cjs'
    ]);
  });

  it('reports missing Codex CLI without exposing raw stderr as the primary message', async () => {
    const child = new FakeChildProcess();
    const service = new AgentConnectionService(() => child as never);

    const promise = service.checkProfile({
      id: CODEX_AGENT_PROFILE_ID,
      name: 'Codex CLI',
      kind: 'cli',
      command: 'node',
      args: ['scripts/codex-mix-planner.cjs'],
      timeoutMs: 20000,
      enabled: true
    });

    child.emit('error', new Error('spawn codex ENOENT'));

    await expect(promise).resolves.toMatchObject({
      status: 'cli_not_found',
      canRunPlanner: false,
      message: 'Codex CLI is not installed or not available on PATH.'
    });
  });

  it('maps authentication failures to login_required', async () => {
    const child = new FakeChildProcess();
    const service = new AgentConnectionService(() => child as never);

    const promise = service.checkProfile({
      id: 'custom-cli',
      name: 'Custom CLI',
      kind: 'cli',
      command: 'custom-agent',
      args: [],
      timeoutMs: 4000,
      enabled: true
    });

    child.stderr.emit('data', 'Authentication failed: login required');
    child.emit('close', 1);

    await expect(promise).resolves.toMatchObject({
      status: 'login_required',
      canRunPlanner: false
    });
  });
});
