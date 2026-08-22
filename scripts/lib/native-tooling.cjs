'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const repositoryRoot = path.resolve(__dirname, '..', '..');
const nativeArtifactRoot = path.join(repositoryRoot, 'native', 'dist');

function run(command, args = [], options = {}) {
  const result = spawnSync(command, args, {
    cwd: repositoryRoot,
    encoding: 'utf8',
    stdio: options.capture ? 'pipe' : 'inherit',
    env: options.env || process.env,
    ...options,
  });
  if (result.error) throw result.error;
  return result;
}

function parseArguments(argv, specification = {}) {
  const result = { _: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      result._.push(token);
      continue;
    }
    const equalsIndex = token.indexOf('=');
    const name = token.slice(2, equalsIndex < 0 ? undefined : equalsIndex);
    const kind = specification[name] || 'boolean';
    if (kind === 'boolean') {
      result[name] = true;
      continue;
    }
    const inlineValue = equalsIndex < 0 ? undefined : token.slice(equalsIndex + 1);
    const value = inlineValue === undefined ? argv[index + 1] : inlineValue;
    if (value === undefined || value.startsWith('--')) throw new Error(`--${name} requires a value`);
    result[name] = kind === 'number' ? Number(value) : value;
    if (inlineValue === undefined) index += 1;
  }
  return result;
}

function resolveArtifactPath(filePath) {
  return path.resolve(repositoryRoot, filePath || nativeArtifactRoot);
}

function writeJsonReport(filePath, value) {
  const resolved = resolveArtifactPath(filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  return resolved;
}

function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
}

function swiftRun(product, args = [], options = {}) {
  return run('swift', ['run', '--package-path', 'native', product, ...args], options);
}

function swiftTest(filter, options = {}) {
  return run('swift', ['test', '--package-path', 'native', '--filter', filter], {
    capture: true,
    stdio: 'pipe',
    ...options,
  });
}

module.exports = {
  nativeArtifactRoot,
  parseArguments,
  repositoryRoot,
  resolveArtifactPath,
  run,
  sha256File,
  swiftRun,
  swiftTest,
  writeJsonReport,
};
