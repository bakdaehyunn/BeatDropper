import { ChildProcessWithoutNullStreams, spawn } from 'node:child_process';
import { CODEX_AGENT_PROFILE_ID, HEURISTIC_AGENT_PROFILE_ID } from '../../shared/settings';
import { AiAgentConnectionResult, AiAgentProfile } from '../../shared/types';
import { PLANNER_SCHEMA_VERSION, PlannerRequest } from '../../shared/plannerContract';
import { CliPlannerAdapter } from './cliPlannerAdapter';

type SpawnProcess = (
  command: string,
  args?: readonly string[]
) => ChildProcessWithoutNullStreams;

const CHECK_TIMEOUT_MS = 3000;

const samplePlannerRequest: PlannerRequest = {
  schemaVersion: PLANNER_SCHEMA_VERSION,
  currentTrack: {
    id: 'connection-current',
    title: 'Connection Test Current',
    durationSec: 180,
    bpm: 124
  },
  nextTrack: {
    id: 'connection-next',
    title: 'Connection Test Next',
    durationSec: 190,
    bpm: 126
  },
  currentPlayback: {
    elapsedSec: 120,
    remainingSec: 60
  },
  analysis: {
    current: {
      schemaVersion: 1,
      trackId: 'connection-current',
      generatedAt: '2026-01-01T00:00:00.000Z',
      source: 'derived',
      bpm: 124,
      beatGridSec: [120, 121.94, 123.87, 125.81, 127.74],
      downbeatsSec: [120, 127.74, 135.48, 143.23],
      introCueSec: 0,
      outroCueSec: 168,
      energyProfile: [0.4, 0.5, 0.48, 0.42],
      analysisConfidence: 0.72
    },
    next: {
      schemaVersion: 1,
      trackId: 'connection-next',
      generatedAt: '2026-01-01T00:00:00.000Z',
      source: 'derived',
      bpm: 126,
      beatGridSec: [0, 1.9, 3.81, 5.71, 7.62],
      downbeatsSec: [0, 7.62, 15.24, 22.86],
      introCueSec: 8,
      outroCueSec: 176,
      energyProfile: [0.34, 0.44, 0.58, 0.66],
      analysisConfidence: 0.72
    }
  },
  settings: {
    fadeDurationSec: 8,
    aiDjMode: 'balanced'
  }
};

const nowIso = (): string => new Date().toISOString();

const createResult = (
  profile: AiAgentProfile,
  input: Omit<AiAgentConnectionResult, 'profileId' | 'profileName' | 'checkedAt'>
): AiAgentConnectionResult => {
  return {
    profileId: profile.id,
    profileName: profile.name,
    checkedAt: nowIso(),
    ...input
  };
};

const classifyError = (
  profile: AiAgentProfile,
  error: unknown
): Pick<AiAgentConnectionResult, 'status' | 'message' | 'canRunPlanner' | 'details'> => {
  const raw = error instanceof Error ? error.message : String(error);
  const normalized = raw.toLowerCase();

  if (
    normalized.includes('enoent') ||
    normalized.includes('not found') ||
    normalized.includes('failed to execute codex')
  ) {
    return {
      status: 'cli_not_found',
      message:
        profile.id === CODEX_AGENT_PROFILE_ID
          ? 'Codex CLI is not installed or not available on PATH.'
          : 'The configured CLI command is not available on PATH.',
      canRunPlanner: false,
      details: {
        reason: 'cli_not_found',
        command: profile.command
      }
    };
  }

  if (
    normalized.includes('login') ||
    normalized.includes('auth') ||
    normalized.includes('credential') ||
    normalized.includes('unauthorized') ||
    normalized.includes('api key') ||
    normalized.includes('401')
  ) {
    return {
      status: 'login_required',
      message:
        profile.id === CODEX_AGENT_PROFILE_ID
          ? 'Codex CLI needs login before BeatDropper can request AI mix plans.'
          : 'The configured CLI needs its own authentication before it can run.',
      canRunPlanner: false,
      details: {
        reason: 'login_required',
        command: profile.command
      }
    };
  }

  if (normalized.includes('planner_timeout')) {
    return {
      status: 'test_failed',
      message: 'The agent test timed out before returning a MixPlan response.',
      canRunPlanner: false,
      details: {
        reason: 'timeout',
        timeoutMs: profile.timeoutMs
      }
    };
  }

  return {
    status: 'test_failed',
    message: 'The agent did not return a valid BeatDropper MixPlan response.',
    canRunPlanner: false,
    details: {
      reason: raw.slice(0, 160)
    }
  };
};

export class AgentConnectionService {
  private readonly spawnProcess: SpawnProcess;
  private readonly plannerAdapter: CliPlannerAdapter;

  constructor(spawnProcess: SpawnProcess = spawn) {
    this.spawnProcess = spawnProcess;
    this.plannerAdapter = new CliPlannerAdapter(spawnProcess);
  }

  async checkProfile(profile: AiAgentProfile): Promise<AiAgentConnectionResult> {
    if (!profile.enabled || profile.command.trim().length === 0) {
      return createResult(profile, {
        status: 'test_failed',
        message: 'This agent profile is missing a CLI command.',
        canRunPlanner: false,
        details: {
          reason: 'command_missing'
        }
      });
    }

    try {
      let codexVersion: string | null = null;
      if (profile.id === CODEX_AGENT_PROFILE_ID) {
        codexVersion = await this.checkCodexCliVersion();
      }

      const response = await this.plannerAdapter.execute(
        {
          command: profile.command,
          args: profile.args,
          timeoutMs: profile.timeoutMs,
          profileId: profile.id,
          profileName: profile.name
        },
        samplePlannerRequest
      );

      if (response.error) {
        throw new Error(response.error);
      }

      return createResult(profile, {
        status: profile.id === HEURISTIC_AGENT_PROFILE_ID ? 'local_ready' : 'ready',
        message:
          profile.id === HEURISTIC_AGENT_PROFILE_ID
            ? 'Local heuristic planner is ready.'
            : `${profile.name} is connected and returned a valid MixPlan response.`,
        canRunPlanner: true,
        details: {
          command: profile.command,
          codexVersion
        }
      });
    } catch (error) {
      return createResult(profile, classifyError(profile, error));
    }
  }

  private async checkCodexCliVersion(): Promise<string | null> {
    return new Promise((resolve, reject) => {
      const child = this.spawnProcess('codex', ['--version']);
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
        finish(() => reject(new Error('codex_version_timeout')));
      }, CHECK_TIMEOUT_MS);

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
          if (code !== 0) {
            reject(new Error(stderr.trim() || `codex_version_exit_code:${code ?? 'unknown'}`));
            return;
          }
          resolve(stdout.trim() || null);
        });
      });
    });
  }
}
