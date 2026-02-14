#!/usr/bin/env node

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = process.cwd();

const ignoredPrefixes = [
  '.git/',
  'node_modules/',
  'dist/',
  'dist-electron/',
  'playwright-report/',
  'test-results/'
];

const binaryExtensions = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.pdf',
  '.zip',
  '.gz',
  '.tar',
  '.mp3',
  '.wav',
  '.lock'
]);

const forbiddenTrackedFilePatterns = [
  /^\.env$/,
  /^\.env\..+/,
  /\.pem$/i,
  /\.key$/i,
  /\.p12$/i
];

const secretPatterns = [
  { name: 'AWS key', regex: /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/g },
  { name: 'GitHub PAT', regex: /\b(?:ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,})\b/g },
  { name: 'OpenAI key', regex: /\bsk-[A-Za-z0-9]{20,}\b/g },
  { name: 'Google API key', regex: /\bAIza[0-9A-Za-z_-]{35}\b/g },
  { name: 'Slack token', regex: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/g },
  {
    name: 'Private key block',
    regex: /-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----/g
  },
  {
    name: 'Bearer token literal',
    regex: /authorization\s*:\s*bearer\s+[A-Za-z0-9._~+/-]{12,}/gi
  }
];

const isIgnored = (filePath) => {
  return ignoredPrefixes.some((prefix) => filePath.startsWith(prefix));
};

const isBinaryByExtension = (filePath) => {
  return binaryExtensions.has(path.extname(filePath).toLowerCase());
};

const getTrackedFiles = () => {
  try {
    const output = execFileSync('git', ['ls-files', '-z'], {
      cwd: repoRoot,
      encoding: 'utf8'
    });
    return output
      .split('\u0000')
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);
  } catch {
    return [];
  }
};

const walkFiles = (directory) => {
  const files = [];
  const entries = fs.readdirSync(directory, { withFileTypes: true });

  for (const entry of entries) {
    const absolutePath = path.join(directory, entry.name);
    const relativePath = path
      .relative(repoRoot, absolutePath)
      .split(path.sep)
      .join('/');

    if (isIgnored(relativePath)) {
      continue;
    }

    if (entry.isDirectory()) {
      files.push(...walkFiles(absolutePath));
      continue;
    }

    files.push(relativePath);
  }

  return files;
};

const trackedFiles = getTrackedFiles().filter((filePath) => !isIgnored(filePath));
const files = trackedFiles.length > 0 ? trackedFiles : walkFiles(repoRoot);

const findings = [];

for (const filePath of files) {
  if (
    filePath !== '.env.example' &&
    forbiddenTrackedFilePatterns.some((pattern) => pattern.test(filePath))
  ) {
    findings.push({
      filePath,
      type: 'forbidden_tracked_file',
      match: filePath
    });
    continue;
  }

  if (isBinaryByExtension(filePath)) {
    continue;
  }

  const absolutePath = path.join(repoRoot, filePath);
  let content;
  try {
    content = fs.readFileSync(absolutePath, 'utf8');
  } catch {
    continue;
  }

  for (const pattern of secretPatterns) {
    pattern.regex.lastIndex = 0;
    const match = pattern.regex.exec(content);
    if (!match) {
      continue;
    }

    findings.push({
      filePath,
      type: pattern.name,
      match: match[0]
    });
  }
}

if (findings.length > 0) {
  console.error('Potential secret exposure detected:');
  for (const finding of findings) {
    console.error(
      `- ${finding.filePath} [${finding.type}] ${String(finding.match).slice(0, 90)}`
    );
  }
  process.exit(1);
}

console.log('security:scan passed (no high-signal secrets detected).');
