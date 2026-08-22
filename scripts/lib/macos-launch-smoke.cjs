'use strict';

const { spawnSync } = require('node:child_process');

function runPersistentAppLaunch(executablePath, options = {}) {
  const settleMs = options.settleMs || 1_200;
  const result = spawnSync(executablePath, [], {
    encoding: 'utf8',
    env: options.env || process.env,
    timeout: settleMs,
    killSignal: 'SIGTERM',
  });
  const output = `${result.stdout || ''}${result.stderr || ''}`.trim();
  const timedOut = result.error?.code === 'ETIMEDOUT';
  const remainedActive = timedOut && (result.signal === 'SIGTERM' || result.status === null);
  return {
    ok: remainedActive,
    status: result.status,
    signal: result.signal,
    remainedActive,
    settleMs,
    output,
    error: result.error || null,
  };
}

module.exports = { runPersistentAppLaunch };
