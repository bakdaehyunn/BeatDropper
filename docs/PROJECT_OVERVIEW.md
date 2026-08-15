# BeatDropper 프로젝트 파악 노트

## 한 줄 요약
BeatDropper는 사용자가 직접 고른 로컬 음악 라이브러리와 세트를 중심으로, native macOS 앱에서 DSP 분석과 AI-assisted mix planning을 이용해 DJ 스타일 전환을 수행하는 데스크톱 앱이다. 제품 런타임은 Swift 기반 native macOS 앱 하나로 통합되어 있다.

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
- 이전 데스크톱 버전의 library/settings state를 native state가 없을 때 한 번만 가져오는 compatibility migration
- Native DSP analyzer for waveform detail, energy, spectral bands, transient markers, BPM, beat/bar/phrase grids, cue candidates, and quality warnings
- Bounded analysis queue and large-library stress coverage
- Planner evidence builders: compact `analysisSummary`, `pairContext`, candidate ranking, deterministic native fallback planner

### 3) AI Mix Planner Bridge
- Native app bundles `scripts/codex-mix-planner.cjs` inside app resources.
- The bridge sends compact DSP evidence to Codex CLI through JSON stdin/stdout and validates returned `MixPlan` timing before scheduling playback.
- If Node/Codex/planner execution fails, native fallback plans are built from `pairContext` evidence so playback remains usable.
- Release readiness now checks Node runtime, Codex CLI availability, source/toolchain provenance, clean release source state, bundled planner script syntax, bundled Node license/notice evidence, quarantine-simulated Gatekeeper evidence, and local fallback/stress evidence.

### 4) Native-only Runtime Boundary
- 앱 런타임과 UI는 `native/` 아래 Swift targets가 소유한다.
- Node scripts는 Codex planner bridge, benchmark, calibration, packaging, release verification 용도로만 사용한다.
- 이전 데스크톱 state migration은 기존 사용자 데이터 호환을 위해 native core 안에 제한적으로 유지한다.

## UI/UX 모드 원칙

BeatDropper native UI는 같은 기능을 한 화면에 모두 노출하는 구조가 아니라, 사용자의 작업 맥락에 따라 두 가지 관점을 분리한다.

### 1) Playing Mode
- 목적: DJ가 지금 재생 중인 세트와 다음 전환에 집중하는 모드.
- 메인 화면에 항상 보여야 하는 것:
  - current deck, next deck, transition/mix point, playback state, meters
  - 현재 세트의 playlist 순서와 최소한의 mix-ready 정보
  - AI mix timing 결과와 confidence 같은 즉시 판단 가능한 값
- 메인 화면에서 피해야 하는 것:
  - raw DSP point counts, JSON/debug evidence, long reasoning text
  - saved-set 관리 form, library maintenance, relink/rescan bulk actions
  - 사용법 설명 문장이나 기능 홍보성 문구

### 2) Creative Mode
- 목적: 사용자가 자신의 취향대로 라이브러리와 플레이리스트를 구성하고, AI가 나중에 playing할 때 참고할 준비 데이터를 세팅하는 모드.
- 다뤄야 하는 것:
  - folder/library browsing, saved taste playlist 구성, playlist ordering
  - BPM/beat grid 확인과 향후 BPM 맞추기 보정
  - hot cue, intro/outro, phrase boundary, energy/cue preference 같은 user-authored hints
  - missing file relink, folder rescan, analysis refresh 같은 maintenance
- AI의 역할:
  - 취향이나 playlist 선택을 대신하지 않는다.
  - 사용자가 만든 set과 cue/hint/DSP evidence를 참고해서 transition timing, fade style, tempo sync, energy strategy를 결정한다.

이 원칙상 Playing Mode의 메인 화면은 performance surface이고, Creative Mode는 preparation surface다. 패널, sheet, inspector, settings는 Creative Mode와 세부 검증을 위한 공간으로 우선 배치한다.

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
- native-only 프로그램 디자인 재설계와 실제 사용 세션 기반 UX 검증
