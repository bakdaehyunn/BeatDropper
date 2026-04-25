# BeatDropper 프로젝트 파악 노트

## 한 줄 요약
BeatDropper는 로컬 오디오 파일(`.mp3`, `.wav`)을 재생하고, 트랙 끝부분에서 DJ 스타일 크로스페이드를 자동으로 수행하는 Electron 기반 데스크톱 MVP다.

## 아키텍처 개요

### 1) Electron Main Process (`src/main`)
- 로컬 파일 선택/파싱 및 트랙 라이브러리 관리
- 설정 저장(`settingsStore`) 및 레지스트리(`trackRegistry`) 관리
- IPC 채널 제공(`ipc.ts`)

### 2) Preload (`src/preload`)
- `contextBridge`로 Main ↔ Renderer 간 안전한 API 노출

### 3) Renderer (`src/renderer`)
- React UI (`App.tsx`)
- Web Audio 기반 플레이어 엔진 모듈
  - `audioEngine`: 듀얼 deck 재생/볼륨 램프
  - `transitionScheduler`: 크로스페이드 시작 시점 계산/스케줄링
  - `tempoSyncPolicy`, `bpmEstimator`, `ruleBasedAdvisor`: BPM/템포 동기화 정책
  - 향후 `BeatAwareAdvisor`: 분석 결과와 AI DJ 플랜 기반 전환 판단

### 4) Shared (`src/shared`)
- 메인/렌더러 공통 타입 및 설정 스키마
- `plannerContract.ts`로 CLI planner 요청/응답 계약을 정의
- `mixPlanExport.ts`로 exported `MixPlan` envelope 계약을 정의

### 5) 계획된 AI DJ 계층
- `main` 프로세스에서 트랙 분석 캐시와 AI planner를 소유
- `renderer`는 planner가 만든 `MixPlan`을 실행
- 특정 벤더 SDK 대신 agent-agnostic CLI 계약(JSON stdin/stdout)으로 planner 연동
- 실시간 루프에서 특정 AI를 직접 호출하지 않고, 전환 직전 1회 planning + 실패 시 rule-based fallback 사용
- 현재는 `AudioEngine`이 planner 결과로 전환 시점 재배치, next-track offset 시작, 고정 tempo sync rate 적용까지 수행
- 설정 드로어에서 planner enable/mode/command/args/timeout을 편집할 수 있고, `scripts/codex-mix-planner.cjs`를 sample wrapper로 제공
- sample Codex wrapper는 mode-aware prompt로 cue/downbeat 정렬을 더 강하게 유도하고, `scripts/heuristic-mix-planner.cjs`도 mode-aware baseline으로 동작한다
- queue 패널에서 마지막 MixPlan/최근 fallback을 볼 수 있고, `scripts/heuristic-mix-planner.cjs`로 외부 AI 없이 계약을 시험할 수 있다
- `tests/fixtures/planner-requests/`와 `scripts/evaluate-planner-modes.cjs`로 representative fixture corpus 기준 mode 차이를 오프라인 점검할 수 있다
- settings drawer의 planner debug 섹션에서 마지막 planner request/response JSON을 복사 가능한 형태로 확인할 수 있다
- planner debug 섹션에서 현재 planner command/args/timeout 및 감지된 preset을 함께 보고, 마지막 성공 MixPlan을 JSON 파일로 export할 수 있다
- exported MixPlan 파일은 `src/shared/mixPlanExport.ts` 계약에 따라 schema/version, planner source, preset, export timestamp를 포함한 envelope 형식으로 저장된다
- 새로 export되는 MixPlan/compare artifact는 가능하면 current/next track identity와 compact analysis metadata까지 함께 담는다
- exported MixPlan 파일은 planner debug 섹션으로 다시 불러와 세션 내 여러 artifact를 쌓아 두고 최근 local MixPlan과 비교할 수 있지만, 현재는 debug compare 전용이고 playback override에는 쓰지 않는다
- planner debug 섹션에서 선택한 imported artifact를 최신 local MixPlan 또는 다른 imported artifact와 직접 pairwise 비교할 수 있다
- pairwise compare 결과도 JSON artifact로 copy/export 할 수 있다
- exported pairwise comparison artifact도 planner debug 섹션으로 다시 불러와 세션 review snapshot으로 볼 수 있다
- imported comparison snapshot과 현재 live pairwise compare를 같은 drawer에서 직접 대조할 수 있다

## 실행 및 검증 루틴
1. `npm install`
2. `npm run dev` (renderer/main/electron 동시 실행)
3. `npm run test` (unit + integration)
4. `npm run test:e2e` (Playwright smoke)

## 개선 후보(다음 스텝)
- 곡 분석(키,에너지) 기반 전환 룰 고도화
- 큐/재생 상태 UI 가시성 강화(전환 예상 시점, 다음 곡 준비 상태)
- 오류/디코딩 실패 시 UX 개선(리트라이, 사용자 알림)
- AI DJ planner와 CLI 기반 `MixPlan` 계약 추가
