import { EventEmitter } from 'node:events';
import { CliPlannerAdapter } from '../../src/main/aiDj/cliPlannerAdapter';
import { PLANNER_SCHEMA_VERSION } from '../../src/shared/plannerContract';

class FakeStream extends EventEmitter {
  private body = '';

  setEncoding(): void {
    return;
  }

  write(chunk: string): void {
    this.body += chunk;
  }

  end(): void {
    return;
  }

  getBody(): string {
    return this.body;
  }
}

class FakeChildProcess extends EventEmitter {
  stdout = new FakeStream();
  stderr = new FakeStream();
  stdin = new FakeStream();
  kill = vi.fn();
}

describe('CliPlannerAdapter', () => {
  it('writes request JSON to stdin and parses stdout JSON', async () => {
    const child = new FakeChildProcess();
    const adapter = new CliPlannerAdapter(() => child as never);

    const promise = adapter.execute(
      {
        command: 'codex',
        args: ['exec'],
        timeoutMs: 1000
      },
      {
        schemaVersion: PLANNER_SCHEMA_VERSION,
        currentTrack: {
          id: 'track-1',
          title: 'Track 1',
          durationSec: 120,
          bpm: 124
        },
        nextTrack: {
          id: 'track-2',
          title: 'Track 2',
          durationSec: 140,
          bpm: 128
        },
        currentPlayback: {
          elapsedSec: 60,
          remainingSec: 60
        },
        analysis: {
          current: null,
          next: null
        },
        settings: {
          fadeDurationSec: 8,
          aiDjMode: 'balanced'
        }
      }
    );

    child.stdout.emit(
      'data',
      JSON.stringify({
        schemaVersion: PLANNER_SCHEMA_VERSION,
        mixPlan: {
          transitionStartSec: 70,
          transitionEndSec: 78,
          nextTrackStartOffsetSec: 12,
          style: 'smooth_blend',
          confidence: 0.8,
          reasoningSummary: 'intro over outro',
          tempoSync: {
            enabled: true,
            targetRate: 0.98
          }
        },
        error: null
      })
    );
    child.emit('close', 0);

    await expect(promise).resolves.toMatchObject({
      mixPlan: {
        transitionStartSec: 70,
        transitionEndSec: 78
      }
    });
    expect(child.stdin.getBody()).toContain('"schemaVersion":1');
  });

  it('fails when stderr is written', async () => {
    const child = new FakeChildProcess();
    const adapter = new CliPlannerAdapter(() => child as never);

    const promise = adapter.execute(
      {
        command: 'codex',
        args: [],
        timeoutMs: 1000
      },
      {
        schemaVersion: PLANNER_SCHEMA_VERSION,
        currentTrack: {
          id: 'track-1',
          title: 'Track 1',
          durationSec: 120,
          bpm: 124
        },
        nextTrack: {
          id: 'track-2',
          title: 'Track 2',
          durationSec: 140,
          bpm: 128
        },
        currentPlayback: {
          elapsedSec: 60,
          remainingSec: 60
        },
        analysis: {
          current: null,
          next: null
        },
        settings: {
          fadeDurationSec: 8,
          aiDjMode: 'safe'
        }
      }
    );

    child.stderr.emit('data', 'warning');
    child.emit('close', 0);

    await expect(promise).rejects.toThrow('planner_stderr:warning');
  });
});
