import { ChildProcessWithoutNullStreams, spawn } from 'node:child_process';
import {
  PlannerCliConfig,
  PlannerRequest,
  PlannerResponse,
  parsePlannerResponseJson
} from '../../shared/plannerContract';

type SpawnProcess = (
  command: string,
  args?: readonly string[]
) => ChildProcessWithoutNullStreams;

export class CliPlannerAdapter {
  private readonly spawnProcess: SpawnProcess;

  constructor(spawnProcess: SpawnProcess = spawn) {
    this.spawnProcess = spawnProcess;
  }

  async execute(
    config: PlannerCliConfig,
    request: PlannerRequest
  ): Promise<PlannerResponse> {
    return new Promise<PlannerResponse>((resolve, reject) => {
      const child = this.spawnProcess(config.command, config.args);
      let stdout = '';
      let stderr = '';
      let settled = false;

      const finish = (fn: () => void): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeoutHandle);
        fn();
      };

      const timeoutHandle = setTimeout(() => {
        child.kill('SIGKILL');
        finish(() => reject(new Error('planner_timeout')));
      }, config.timeoutMs);

      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      child.stdout.on('data', (chunk: string) => {
        stdout += chunk;
      });
      child.stderr.on('data', (chunk: string) => {
        stderr += chunk;
      });
      child.on('error', (error) => {
        finish(() => reject(error));
      });
      child.on('close', (code) => {
        finish(() => {
          if (stderr.trim().length > 0) {
            reject(new Error(`planner_stderr:${stderr.trim()}`));
            return;
          }

          if (code !== 0) {
            reject(new Error(`planner_exit_code:${code ?? 'unknown'}`));
            return;
          }

          const parsed = parsePlannerResponseJson(stdout.trim());
          if (!parsed.response) {
            reject(new Error(parsed.reason ?? 'planner_response_invalid'));
            return;
          }

          resolve(parsed.response);
        });
      });

      child.stdin.write(JSON.stringify(request));
      child.stdin.end();
    });
  }
}
