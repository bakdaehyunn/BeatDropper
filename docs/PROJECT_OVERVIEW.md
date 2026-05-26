# BeatDropper 프로젝트 파악 노트

## 한 줄 요약
BeatDropper는 사용자가 직접 고른 로컬 음악 라이브러리와 세트를 중심으로, native macOS 앱에서 DSP 분석과 AI-assisted mix planning을 이용해 DJ 스타일 전환을 수행하는 데스크톱 앱이다. Electron 구현은 native parity와 notarized release가 증명될 때까지 남아 있는 reference path다.

## 아키텍처 개요

### 1) Native macOS App (`native/Sources/BeatDropperNative`)
- SwiftUI/AppKit 기반 macOS window, command menu, Settings scene
- Finder Open With, drag-and-drop, file/folder import
- DJ workspace: current deck, next deck, AI mix point, playlist, library browser, optional inspector
- `NativeAudioEngine`: AVAudioEngine two-deck playback, per-deck meters, master gain, equal-power crossfade, device/configuration recovery
- `BeatDropperAppModel`: playlist/library orchestration, analysis queue draining, planner request scheduling, missing-file/relink workflows

### 2) Native Core (`native/Sources/BeatDropperCore`)
- Codable model contract shared with planner request/response JSON
- Application Support persistence for library records, source folders, current set, saved taste playlists, player settings, and analysis cache
- Electron library/settings migration when native state is missing
- Native DSP analyzer for waveform detail, energy, spectral bands, transient markers, BPM, beat/bar/phrase grids, cue candidates, and quality warnings
- Bounded analysis queue and large-library stress coverage
- Planner evidence builders: compact `analysisSummary`, `pairContext`, candidate ranking, deterministic native fallback planner

### 3) AI Mix Planner Bridge
- Native app bundles `scripts/codex-mix-planner.cjs` inside app resources.
- The bridge sends compact DSP evidence to Codex CLI through JSON stdin/stdout and validates returned `MixPlan` timing before scheduling playback.
- If Node/Codex/planner execution fails, native fallback plans are built from `pairContext` evidence so playback remains usable.
- Release readiness now checks Node runtime, Codex CLI availability, source/toolchain provenance, clean release source state, bundled planner script syntax, bundled Node license/notice evidence, quarantine-simulated Gatekeeper evidence, and local fallback/stress evidence.

### 4) Electron Reference Path
- `src/main`, `src/preload`, `src/renderer`, `src/shared`, and Electron tests remain only as reference material during migration.
- Electron source, scripts, dependencies, and docs are removed only after notarized native release verification, normal and quarantine-simulated Gatekeeper evidence, pre-retirement parity, and `native:retire:check` all pass.

## 실행 및 검증 루틴
1. `npm run native:build`
2. `npm run native:test`
3. `npm run native:package`
4. `npm run native:preflight:local`
5. `npm run native:parity:report`

## 개선 후보(다음 스텝)
- Developer ID signing identity와 Apple notary credentials 준비
- `npm run native:release`로 notarized ZIP/DMG 생성, strict release verification PASS, source-provenance-bound smoke evidence 확보
- clean-machine Gatekeeper 검증
- Electron retirement plan 실행 및 native-only package/docs 정리
