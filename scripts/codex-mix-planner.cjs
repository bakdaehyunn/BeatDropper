#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const readStdin = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)));
  }
  return Buffer.concat(chunks).toString('utf8');
};

const plannerSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['schemaVersion', 'mixPlan', 'error'],
  properties: {
    schemaVersion: {
      type: 'integer',
      const: 1
    },
    error: {
      anyOf: [{ type: 'string' }, { type: 'null' }]
    },
    mixPlan: {
      anyOf: [
        { type: 'null' },
        {
          type: 'object',
          additionalProperties: false,
          required: [
            'transitionStartSec',
            'transitionEndSec',
            'nextTrackStartOffsetSec',
            'style',
            'confidence',
            'reasoningSummary',
            'tempoSync',
            'candidateId',
            'currentBarIndex',
            'nextBarIndex',
            'phraseAlignment',
            'energyStrategy',
            'evidence'
          ],
          properties: {
            transitionStartSec: { type: 'number' },
            transitionEndSec: { type: 'number' },
            nextTrackStartOffsetSec: { type: 'number' },
            style: {
              type: 'string',
              enum: ['smooth_blend', 'energy_swap', 'hard_cut']
            },
            confidence: { type: 'number' },
            reasoningSummary: {
              anyOf: [{ type: 'string' }, { type: 'null' }]
            },
            tempoSync: {
              type: 'object',
              additionalProperties: false,
              required: ['enabled', 'targetRate'],
              properties: {
                enabled: { type: 'boolean' },
                targetRate: {
                  anyOf: [{ type: 'number', minimum: 0.85, maximum: 1.15 }, { type: 'null' }]
                }
              }
            },
            candidateId: {
              anyOf: [{ type: 'string' }, { type: 'null' }]
            },
            currentBarIndex: {
              anyOf: [{ type: 'number' }, { type: 'null' }]
            },
            nextBarIndex: {
              anyOf: [{ type: 'number' }, { type: 'null' }]
            },
            phraseAlignment: {
              anyOf: [{ type: 'string', enum: ['aligned', 'near', 'free'] }, { type: 'null' }]
            },
            energyStrategy: {
              anyOf: [{ type: 'string', enum: ['lift', 'maintain', 'drop'] }, { type: 'null' }]
            },
            evidence: {
              type: 'array',
              items: { type: 'string' }
            }
          }
        }
      ]
    }
  }
};

const buildModeGuidance = (mode) => {
  if (mode === 'safe') {
    return [
      'Mode policy: safe.',
      '- Prefer smooth_blend.',
      '- Favor stable outro / intro cues and longer overlaps.',
      '- Use tempoSync only for very small BPM differences.',
      '- Avoid hard_cut unless no safe overlap exists.'
    ].join('\n');
  }

  if (mode === 'adventurous') {
    return [
      'Mode policy: adventurous.',
      '- You may use energy_swap or hard_cut when cues are weak or the energy jump is intentional.',
      '- Shorter transitions are acceptable if operationally safe.',
      '- TempoSync can be used for moderate BPM differences when still plausible.'
    ].join('\n');
  }

  return [
    'Mode policy: balanced.',
    '- Prefer smooth_blend, but allow energy_swap when cues and BPM relation support it.',
    '- Use cue/downbeat alignment when available.',
    '- TempoSync is acceptable for modest BPM differences.'
  ].join('\n');
};

const buildAnalysisHints = (request) => {
  const current = request?.analysis?.current;
  const next = request?.analysis?.next;
  const currentHints = [];
  const nextHints = [];

  if (typeof current?.outroCueSec === 'number') {
    currentHints.push(`current outro cue ${current.outroCueSec.toFixed(2)}s`);
  }
  if (Array.isArray(current?.downbeatsSec) && current.downbeatsSec.length > 0) {
    currentHints.push(`current downbeats ${current.downbeatsSec.length}`);
  }
  if (Array.isArray(current?.beatGridSec) && current.beatGridSec.length > 0) {
    currentHints.push(`current beat-grid points ${current.beatGridSec.length}`);
  }

  if (typeof next?.introCueSec === 'number') {
    nextHints.push(`next intro cue ${next.introCueSec.toFixed(2)}s`);
  }
  if (Array.isArray(next?.downbeatsSec) && next.downbeatsSec.length > 0) {
    nextHints.push(`next downbeats ${next.downbeatsSec.length}`);
  }
  if (Array.isArray(next?.beatGridSec) && next.beatGridSec.length > 0) {
    nextHints.push(`next beat-grid points ${next.beatGridSec.length}`);
  }

  return [
    'Analysis hints:',
    `- ${currentHints.length > 0 ? currentHints.join(', ') : 'current track has limited cue/downbeat data'}`,
    `- ${nextHints.length > 0 ? nextHints.join(', ') : 'next track has limited cue/downbeat data'}`
  ].join('\n');
};

const buildPairContextHints = (request) => {
  const candidates = Array.isArray(request?.pairContext?.candidates)
    ? request.pairContext.candidates
    : [];
  if (candidates.length === 0) {
    return 'Mix candidates: none available; use cue and beat-grid evidence directly.';
  }

  return [
    'Mix candidates:',
    `Readiness: ${request?.pairContext?.readiness ?? 'unknown'}`,
    ...candidates.slice(0, 5).map((candidate, index) =>
      [
        `- ${index + 1}. id ${candidate.id}`,
        `source ${candidate.source ?? 'unknown'}`,
        `evidence ${candidate.evidenceLevel ?? 'unknown'}`,
        candidate.requiresAnalysisUpgrade ? 'requires analysis upgrade' : null,
        `score ${typeof candidate.score === 'number' ? candidate.score.toFixed(2) : '--'}`,
        `current out ${candidate.currentMixOutSec}s`,
        `next in ${candidate.nextMixInSec}s`,
        `bars ${candidate.currentBarIndex ?? '--'} -> ${candidate.nextBarIndex ?? '--'}`,
        `phrase ${candidate.phraseAlignment ?? '--'}`,
        `style ${candidate.style ?? '--'}`,
        candidate.reason ? `reason ${candidate.reason}` : null
      ]
        .filter(Boolean)
        .join('; ')
    )
  ].join('\n');
};

const buildPrompt = (request) => {
  const requestJson = JSON.stringify(request, null, 2);
  return [
    'You are an AI DJ planner for BeatDropper.',
    'Return only a JSON object that matches the provided schema.',
    'Plan a musically plausible but operationally safe transition.',
    '',
    'Hard safety rules:',
    '- transitionStartSec must be >= currentPlayback.elapsedSec',
    '- transitionEndSec must be > transitionStartSec',
    '- transitionEndSec must be <= currentTrack.durationSec',
    '- transition duration should usually be <= settings.fadeDurationSec',
    '- nextTrackStartOffsetSec must be within nextTrack.durationSec',
    '- If you cannot produce a safe plan, set mixPlan to null and explain in error',
    '',
    'Planning rules:',
    '- Prefer aligning transition timing to outro cues, downbeats, or beat-grid points when available',
    '- Prefer starting the next track from intro cue or an early stable downbeat instead of 0 when analysis supports it',
    '- Do not default to currentTrack.durationSec as transitionEndSec unless cue/downbeat data is missing or the tail is clearly the safest window',
    '- Treat source=tail_fallback candidates as safety fallbacks, not AI-selected musical evidence',
    '- Use tail_fallback only when pairContext.readiness is fallback_only or all analysis/cue candidates are unsafe',
    '- If readiness is analysis_pending, either choose a cue/analysis candidate with evidence or return null with an analysis-pending error',
    '- Use reasoningSummary to cite the main evidence: mode, cues, BPM relation, and why the selected style is appropriate',
    '- Prefer choosing one pairContext candidate and include its candidateId, bar indices, phraseAlignment, energyStrategy, and evidence',
    '- Keep style choices operationally conservative unless the mode explicitly allows more aggressive transitions',
    '- Use tempoSync only when BPM values are present and the chosen playback-rate ratio still sounds plausible',
    '- tempoSync.targetRate is a playback-rate ratio from 0.85 to 1.15, not a BPM value; use currentBpm / nextBpm when syncing the next track to the current track',
    '',
    buildModeGuidance(request?.settings?.aiDjMode),
    '',
    buildAnalysisHints(request),
    '',
    buildPairContextHints(request),
    '',
    'Planner request JSON:',
    requestJson
  ].join('\n');
};

const main = async () => {
  const raw = await readStdin();
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    process.stderr.write(
      `invalid planner request json: ${error instanceof Error ? error.message : String(error)}\n`
    );
    process.exit(1);
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'beatdropper-codex-planner-'));
  const schemaPath = path.join(tmpDir, 'planner-response.schema.json');
  const outputPath = path.join(tmpDir, 'planner-response.json');
  fs.writeFileSync(schemaPath, JSON.stringify(plannerSchema, null, 2), 'utf8');

  const repoRoot = path.resolve(__dirname, '..');
  const args = [
    'exec',
    '-',
    '--skip-git-repo-check',
    '--output-schema',
    schemaPath,
    '--output-last-message',
    outputPath,
    '-C',
    repoRoot
  ];

  if (process.env.BEATDROPPER_CODEX_MODEL) {
    args.push('-m', process.env.BEATDROPPER_CODEX_MODEL);
  }

  const prompt = buildPrompt(parsed);
  const result = spawnSync('codex', args, {
    input: prompt,
    encoding: 'utf8',
    env: process.env,
    maxBuffer: 10 * 1024 * 1024
  });

  if (result.error) {
    process.stderr.write(`failed to execute codex: ${result.error.message}\n`);
    process.exit(1);
  }

  if (result.status !== 0) {
    if (result.stderr) {
      process.stderr.write(result.stderr);
    }
    process.exit(result.status || 1);
  }

  const finalMessage = fs.readFileSync(outputPath, 'utf8').trim();
  let response;
  try {
    response = JSON.parse(finalMessage);
  } catch (error) {
    process.stderr.write(
      `codex returned non-json planner output: ${error instanceof Error ? error.message : String(error)}\n`
    );
    process.exit(1);
  }

  process.stdout.write(`${JSON.stringify(response)}\n`);
};

module.exports = {
  buildModeGuidance,
  buildAnalysisHints,
  buildPairContextHints,
  buildPrompt,
  plannerSchema
};

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  });
}
