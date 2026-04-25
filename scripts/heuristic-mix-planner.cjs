#!/usr/bin/env node

const readStdin = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)));
  }
  return Buffer.concat(chunks).toString('utf8');
};

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

const asNumber = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : null);

const asNumberList = (value) =>
  Array.isArray(value) ? value.filter((item) => typeof item === 'number' && Number.isFinite(item)) : [];

const pickPointAtOrBefore = (points, target, floor) => {
  const candidates = points
    .filter((point) => point >= floor && point <= target)
    .sort((left, right) => right - left);
  return candidates[0] ?? null;
};

const pickPointAtOrAfter = (points, target, ceiling) => {
  const candidates = points
    .filter((point) => point >= target && point <= ceiling)
    .sort((left, right) => left - right);
  return candidates[0] ?? null;
};

const buildModePolicy = (mode, fadeDurationSec) => {
  if (mode === 'safe') {
    return {
      desiredWindowSec: Math.min(fadeDurationSec, 8),
      minWindowSec: Math.max(3, fadeDurationSec * 0.65),
      tempoRange: [0.97, 1.03],
      style: 'smooth_blend'
    };
  }

  if (mode === 'adventurous') {
    return {
      desiredWindowSec: Math.min(fadeDurationSec, 4.5),
      minWindowSec: Math.max(1.5, fadeDurationSec * 0.35),
      tempoRange: [0.92, 1.08],
      style: 'energy_swap'
    };
  }

  return {
    desiredWindowSec: Math.min(fadeDurationSec, 6),
    minWindowSec: Math.max(2.5, fadeDurationSec * 0.55),
    tempoRange: [0.95, 1.06],
    style: 'smooth_blend'
  };
};

const resolveTempoSync = (currentBpm, nextBpm, tempoRange) => {
  if (!Number.isFinite(currentBpm) || !Number.isFinite(nextBpm) || nextBpm <= 0) {
    return {
      enabled: false,
      targetRate: null
    };
  }

  const desiredRate = currentBpm / nextBpm;
  if (desiredRate < tempoRange[0] || desiredRate > tempoRange[1]) {
    return {
      enabled: false,
      targetRate: null
    };
  }

  return {
    enabled: true,
    targetRate: clamp(desiredRate, tempoRange[0], tempoRange[1])
  };
};

const chooseStyle = ({ mode, bpmGap, nextIntroCueSec, currentOutroCueSec, transitionWindowSec }) => {
  if (mode === 'safe') {
    return 'smooth_blend';
  }

  if (mode === 'balanced') {
    if (currentOutroCueSec !== null && nextIntroCueSec !== null) {
      return 'smooth_blend';
    }

    if (bpmGap <= 6 && transitionWindowSec <= 5) {
      return 'energy_swap';
    }

    return 'smooth_blend';
  }

  if (
    bpmGap > 10 ||
    transitionWindowSec < 2 ||
    nextIntroCueSec === null ||
    currentOutroCueSec === null
  ) {
    return 'hard_cut';
  }

  if (bpmGap <= 8) {
    return 'energy_swap';
  }

  return 'smooth_blend';
};

const buildHeuristicResponse = (request) => {
  const fadeDurationSec = asNumber(request?.settings?.fadeDurationSec) ?? 8;
  const currentDurationSec = asNumber(request?.currentTrack?.durationSec) ?? 0;
  const elapsedSec = asNumber(request?.currentPlayback?.elapsedSec) ?? 0;
  const currentBpm =
    asNumber(request?.currentTrack?.bpm) ?? asNumber(request?.analysis?.current?.bpm);
  const nextBpm = asNumber(request?.nextTrack?.bpm) ?? asNumber(request?.analysis?.next?.bpm);
  const mode = request?.settings?.aiDjMode ?? 'balanced';
  const currentOutroCueSec = asNumber(request?.analysis?.current?.outroCueSec);
  const nextIntroCueSec = asNumber(request?.analysis?.next?.introCueSec);
  const currentPoints = [
    ...asNumberList(request?.analysis?.current?.downbeatsSec),
    ...asNumberList(request?.analysis?.current?.beatGridSec)
  ].sort((left, right) => left - right);
  const nextPoints = [
    ...asNumberList(request?.analysis?.next?.downbeatsSec),
    ...asNumberList(request?.analysis?.next?.beatGridSec)
  ].sort((left, right) => left - right);
  const policy = buildModePolicy(mode, fadeDurationSec);

  const preferredEndSec =
    currentOutroCueSec !== null && currentOutroCueSec > elapsedSec + 0.25
      ? currentOutroCueSec
      : currentDurationSec;
  const alignedEndSec =
    pickPointAtOrBefore(currentPoints, preferredEndSec, elapsedSec + 0.1) ??
    clamp(preferredEndSec, elapsedSec + 0.1, currentDurationSec);

  const desiredStartSec = Math.max(elapsedSec, alignedEndSec - policy.desiredWindowSec);
  const alignedStartSec =
    pickPointAtOrBefore(currentPoints, desiredStartSec, elapsedSec) ??
    clamp(desiredStartSec, elapsedSec, alignedEndSec);

  let transitionStartSec = alignedStartSec;
  let transitionEndSec = alignedEndSec;

  if (transitionEndSec - transitionStartSec < policy.minWindowSec) {
    transitionStartSec = clamp(
      transitionEndSec - policy.minWindowSec,
      elapsedSec,
      Math.max(elapsedSec, transitionEndSec - 0.1)
    );
  }

  const inferredNextOffsetSec =
    nextIntroCueSec ??
    pickPointAtOrAfter(nextPoints, 0, asNumber(request?.nextTrack?.durationSec) ?? 0) ??
    0;
  const tempoSync = resolveTempoSync(currentBpm, nextBpm, policy.tempoRange);
  const bpmGap =
    Number.isFinite(currentBpm) && Number.isFinite(nextBpm) ? Math.abs(currentBpm - nextBpm) : 999;
  const style = chooseStyle({
    mode,
    bpmGap,
    nextIntroCueSec,
    currentOutroCueSec,
    transitionWindowSec: transitionEndSec - transitionStartSec
  });
  const confidence = clamp(
    0.46 +
      (currentOutroCueSec !== null ? 0.12 : 0) +
      (nextIntroCueSec !== null ? 0.12 : 0) +
      (tempoSync.enabled ? 0.08 : 0) +
      (style !== 'smooth_blend' ? 0.04 : 0) +
      (mode === 'safe' ? 0.03 : mode === 'adventurous' ? 0.01 : 0.02),
    0.35,
    0.86
  );

  return {
    schemaVersion: 1,
    error: null,
    mixPlan: {
      transitionStartSec,
      transitionEndSec,
      nextTrackStartOffsetSec: Math.max(0, inferredNextOffsetSec),
      style,
      confidence,
      reasoningSummary: [
        `Mode ${mode}`,
        currentOutroCueSec !== null
          ? `aligned to current outro cue near ${currentOutroCueSec.toFixed(2)}s`
          : 'used current track tail',
        nextIntroCueSec !== null
          ? `started next track from intro cue ${nextIntroCueSec.toFixed(2)}s`
          : 'used earliest stable next-track beat',
        tempoSync.enabled
          ? `tempo sync ${tempoSync.targetRate.toFixed(3)}x`
          : 'tempo sync disabled'
      ].join('; '),
      tempoSync
    }
  };
};

const main = async () => {
  const raw = await readStdin();
  let request;
  try {
    request = JSON.parse(raw);
  } catch (error) {
    process.stderr.write(
      `invalid planner request json: ${error instanceof Error ? error.message : String(error)}\n`
    );
    process.exit(1);
  }

  const response = buildHeuristicResponse(request);
  process.stdout.write(`${JSON.stringify(response)}\n`);
};

module.exports = {
  buildModePolicy,
  resolveTempoSync,
  buildHeuristicResponse
};

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  });
}
