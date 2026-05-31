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

const arrayCount = (value) => (Array.isArray(value) ? value.length : 0);

const compactCueCandidate = (cue) => {
  if (!cue || typeof cue !== 'object') {
    return cue ?? null;
  }

  return {
    id: cue.id,
    type: cue.type,
    startSec: cue.startSec,
    endSec: cue.endSec,
    confidence: cue.confidence,
    label: cue.label
  };
};

const compactAnalysisForPrompt = (analysis) => {
  if (!analysis || typeof analysis !== 'object') {
    return null;
  }

  return {
    schemaVersion: analysis.schemaVersion,
    trackId: analysis.trackId,
    generatedAt: analysis.generatedAt,
    source: analysis.source,
    bpm: analysis.bpm,
    bpmConfidence: analysis.bpmConfidence,
    introCueSec: analysis.introCueSec,
    outroCueSec: analysis.outroCueSec,
    analysisConfidence: analysis.analysisConfidence,
    analysisQuality: analysis.analysisQuality,
    analysisWarnings: analysis.analysisWarnings,
    cueCandidates: Array.isArray(analysis.cueCandidates)
      ? analysis.cueCandidates.slice(0, 8).map(compactCueCandidate)
      : [],
    counts: {
      beatGridSec: arrayCount(analysis.beatGridSec),
      downbeatsSec: arrayCount(analysis.downbeatsSec),
      barGrid: arrayCount(analysis.barGrid),
      phraseMarkers: arrayCount(analysis.phraseMarkers),
      energyProfile: arrayCount(analysis.energyProfile),
      waveformPeaks: arrayCount(analysis.waveformPeaks),
      waveformDetail: arrayCount(analysis.waveformDetail),
      spectralBands: arrayCount(analysis.spectralBands),
      transientMarkers: arrayCount(analysis.transientMarkers)
    }
  };
};

const compactCandidateForPrompt = (candidate) => {
  if (!candidate || typeof candidate !== 'object') {
    return candidate ?? null;
  }

  return {
    id: candidate.id,
    currentTrackId: candidate.currentTrackId,
    nextTrackId: candidate.nextTrackId,
    source: candidate.source,
    evidenceLevel: candidate.evidenceLevel,
    requiresAnalysisUpgrade: candidate.requiresAnalysisUpgrade,
    currentMixOutSec: candidate.currentMixOutSec,
    nextMixInSec: candidate.nextMixInSec,
    currentBarIndex: candidate.currentBarIndex,
    nextBarIndex: candidate.nextBarIndex,
    phraseAlignment: candidate.phraseAlignment,
    bpmDelta: candidate.bpmDelta,
    tempoSyncRate: candidate.tempoSyncRate,
    energyDelta: candidate.energyDelta,
    style: candidate.style,
    score: candidate.score,
    confidence: candidate.confidence,
    reason: candidate.reason
  };
};

const compactPairContextForPrompt = (pairContext) => {
  if (!pairContext || typeof pairContext !== 'object') {
    return null;
  }

  return {
    currentTrackId: pairContext.currentTrackId,
    nextTrackId: pairContext.nextTrackId,
    recommendedCandidateId: pairContext.recommendedCandidateId,
    readiness: pairContext.readiness,
    candidates: Array.isArray(pairContext.candidates)
      ? pairContext.candidates.slice(0, 8).map(compactCandidateForPrompt)
      : []
  };
};

const buildPromptRequest = (request) => ({
  schemaVersion: request?.schemaVersion,
  currentTrack: request?.currentTrack,
  nextTrack: request?.nextTrack,
  currentPlayback: request?.currentPlayback,
  analysis: {
    current: compactAnalysisForPrompt(request?.analysis?.current),
    next: compactAnalysisForPrompt(request?.analysis?.next)
  },
  analysisSummary: request?.analysisSummary ?? null,
  pairContext: compactPairContextForPrompt(request?.pairContext),
  preparation: request?.preparation ?? null,
  settings: request?.settings
});

const buildAnalysisHints = (request) => {
  const currentSummary = request?.analysisSummary?.current;
  const nextSummary = request?.analysisSummary?.next;
  const current = request?.analysis?.current;
  const next = request?.analysis?.next;

  if (currentSummary || nextSummary) {
    const formatCue = (label, cue) =>
      cue && typeof cue.startSec === 'number'
        ? `${label} ${cue.startSec.toFixed(2)}s confidence ${typeof cue.confidence === 'number' ? cue.confidence.toFixed(2) : '--'}`
        : null;
    const formatWindow = (direction, window) =>
      window && typeof window.startSec === 'number'
        ? `${direction} ${window.kind ?? 'window'} ${window.startSec.toFixed(2)}-${typeof window.endSec === 'number' ? window.endSec.toFixed(2) : '--'}s confidence ${typeof window.confidence === 'number' ? window.confidence.toFixed(2) : '--'}`
        : null;
    const formatTrackSummary = (label, summary) => {
      if (!summary) {
        return `- ${label}: no analysis summary available`;
      }

      const cues = [
        formatCue('intro', summary.cues?.intro),
        formatCue('first downbeat', summary.cues?.firstDownbeat),
        formatCue('outro', summary.cues?.outro)
      ].filter(Boolean);
      const energy = summary.energyTrend
        ? `energy ${summary.energyTrend.direction ?? 'unknown'} early ${summary.energyTrend.early ?? '--'} mid ${summary.energyTrend.mid ?? '--'} late ${summary.energyTrend.late ?? '--'}`
        : 'energy unknown';
      const beatStability = summary.beatStability
        ? `beat stability ${summary.beatStability.label ?? 'unknown'} score ${summary.beatStability.score ?? '--'}`
        : 'beat stability unknown';
      const transients = summary.transients
        ? `transients ${summary.transients.count ?? 0}, strong ${summary.transients.strongCount ?? 0}, density ${summary.transients.densityPerSec ?? 0}/s`
        : 'transients unknown';
      const phrases = summary.phrases
        ? `phrases ${summary.phrases.phraseCount ?? 0}, bars ${summary.phrases.barCount ?? 0}, strongest ${Array.isArray(summary.phrases.strongestBoundaries) ? summary.phrases.strongestBoundaries.map((boundary) => `${boundary.startSec}s/${boundary.confidence}`).join(', ') : 'none'}`
        : 'phrases unknown';
      const mixInWindows = Array.isArray(summary.mixWindows?.mixIn)
        ? summary.mixWindows.mixIn.slice(0, 3).map((window) => formatWindow('in', window)).filter(Boolean)
        : [];
      const mixOutWindows = Array.isArray(summary.mixWindows?.mixOut)
        ? summary.mixWindows.mixOut.slice(0, 3).map((window) => formatWindow('out', window)).filter(Boolean)
        : [];
      const windows = mixInWindows.length > 0 || mixOutWindows.length > 0
        ? `mix windows ${[...mixOutWindows, ...mixInWindows].join('; ')}`
        : 'mix windows none';
      const quality = summary.analysisQuality
        ? `quality beat ${summary.analysisQuality.beatGrid ?? 0}, spectral ${summary.analysisQuality.spectralBands ?? 0}, transient ${summary.analysisQuality.transientMarkers ?? 0}`
        : 'quality unknown';
      const warnings = Array.isArray(summary.analysisWarnings) && summary.analysisWarnings.length > 0
        ? `warnings ${summary.analysisWarnings.join(', ')}`
        : 'warnings none';

      return [
        `- ${label}: plannerReady ${Boolean(summary.plannerReady)}`,
        `BPM ${typeof summary.bpm === 'number' ? summary.bpm.toFixed(2) : '--'} confidence ${typeof summary.bpmConfidence === 'number' ? summary.bpmConfidence.toFixed(2) : '--'}`,
        quality,
        beatStability,
        cues.length > 0 ? `cues ${cues.join('; ')}` : 'cues none',
        energy,
        transients,
        phrases,
        windows,
        warnings
      ].join('; ');
    };

    return [
      'Analysis hints:',
      'Prefer analysisSummary and pairContext for decisions; raw DSP arrays are intentionally omitted from this prompt.',
      formatTrackSummary('current', currentSummary),
      formatTrackSummary('next', nextSummary)
    ].join('\n');
  }

  const currentHints = [];
  const nextHints = [];
  const currentCounts = current?.counts ?? {};
  const nextCounts = next?.counts ?? {};

  if (typeof current?.outroCueSec === 'number') {
    currentHints.push(`current outro cue ${current.outroCueSec.toFixed(2)}s`);
  }
  if (Array.isArray(current?.downbeatsSec) && current.downbeatsSec.length > 0) {
    currentHints.push(`current downbeats ${current.downbeatsSec.length}`);
  } else if (currentCounts.downbeatsSec > 0) {
    currentHints.push(`current downbeats ${currentCounts.downbeatsSec}`);
  }
  if (Array.isArray(current?.beatGridSec) && current.beatGridSec.length > 0) {
    currentHints.push(`current beat-grid points ${current.beatGridSec.length}`);
  } else if (currentCounts.beatGridSec > 0) {
    currentHints.push(`current beat-grid points ${currentCounts.beatGridSec}`);
  }

  if (typeof next?.introCueSec === 'number') {
    nextHints.push(`next intro cue ${next.introCueSec.toFixed(2)}s`);
  }
  if (Array.isArray(next?.downbeatsSec) && next.downbeatsSec.length > 0) {
    nextHints.push(`next downbeats ${next.downbeatsSec.length}`);
  } else if (nextCounts.downbeatsSec > 0) {
    nextHints.push(`next downbeats ${nextCounts.downbeatsSec}`);
  }
  if (Array.isArray(next?.beatGridSec) && next.beatGridSec.length > 0) {
    nextHints.push(`next beat-grid points ${next.beatGridSec.length}`);
  } else if (nextCounts.beatGridSec > 0) {
    nextHints.push(`next beat-grid points ${nextCounts.beatGridSec}`);
  }

  return [
    'Analysis hints:',
    'Raw DSP arrays are intentionally omitted from this prompt; use compact cue/count evidence.',
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

const buildPreparationHints = (request) => {
  const formatPreparation = (label, preparation) => {
    if (!preparation) {
      return `- ${label}: no user prep`;
    }
    const bpm = typeof preparation.bpmOverride === 'number'
      ? `prep BPM ${preparation.bpmOverride.toFixed(1)}`
      : 'prep BPM --';
    const cues = Array.isArray(preparation.hotCues) && preparation.hotCues.length > 0
      ? preparation.hotCues
        .slice()
        .sort((left, right) => (left.timeSec ?? 0) - (right.timeSec ?? 0))
        .slice(0, 8)
        .map((cue) => `${cue.label ?? cue.kind ?? 'cue'} ${typeof cue.timeSec === 'number' ? cue.timeSec.toFixed(2) : '--'}s`)
        .join('; ')
      : 'hot cues none';
    return `- ${label}: ${bpm}; ${cues}`;
  };

  const current = request?.preparation?.current;
  const next = request?.preparation?.next;
  if (!current && !next) {
    return 'Preparation hints: none';
  }

  return [
    'Preparation hints:',
    'Treat user prep BPM and hot cues as human intent; prefer them when they are plausible and do not violate safety rules.',
    formatPreparation('current', current),
    formatPreparation('next', next)
  ].join('\n');
};

const buildPrompt = (request) => {
  const promptRequest = buildPromptRequest(request);
  const requestJson = JSON.stringify(promptRequest, null, 2);
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
    buildModeGuidance(promptRequest?.settings?.aiDjMode),
    '',
    buildAnalysisHints(promptRequest),
    '',
    buildPairContextHints(promptRequest),
    '',
    buildPreparationHints(promptRequest),
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
  buildPreparationHints,
  buildPromptRequest,
  buildPrompt,
  plannerSchema
};

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  });
}
