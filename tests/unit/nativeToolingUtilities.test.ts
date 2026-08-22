import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

// CommonJS is intentional: release and packaging scripts run directly in Node.
const tooling = require('../../scripts/lib/native-tooling.cjs');

const temporaryPaths: string[] = [];

afterEach(() => {
  for (const item of temporaryPaths.splice(0)) fs.rmSync(item, { recursive: true, force: true });
});

describe('native tooling utilities', () => {
  it('parses typed flags and positional arguments consistently', () => {
    expect(tooling.parseArguments(['--strict', '--count', '4', '--out', 'report.json', 'fixture'], {
      count: 'number',
      out: 'string',
    })).toEqual({ strict: true, count: 4, out: 'report.json', _: ['fixture'] });
    expect(tooling.parseArguments(['--out=inline.json'], { out: 'string' }).out).toBe('inline.json');
  });

  it('writes stable JSON reports and hashes files', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-tooling-'));
    temporaryPaths.push(root);
    const reportPath = path.join(root, 'nested', 'report.json');
    tooling.writeJsonReport(reportPath, { ok: true });

    expect(fs.readFileSync(reportPath, 'utf8')).toBe('{\n  "ok": true\n}\n');
    expect(tooling.sha256File(reportPath)).toMatch(/^[a-f0-9]{64}$/);
  });
});
