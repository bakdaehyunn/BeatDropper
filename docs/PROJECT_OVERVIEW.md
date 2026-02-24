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

### 4) Shared (`src/shared`)
- 메인/렌더러 공통 타입 및 설정 스키마

## 실행 및 검증 루틴
1. `npm install`
2. `npm run dev` (renderer/main/electron 동시 실행)
3. `npm run test` (unit + integration)
4. `npm run test:e2e` (Playwright smoke)

## 개선 후보(다음 스텝)
- 곡 분석(키,에너지) 기반 전환 룰 고도화
- 큐/재생 상태 UI 가시성 강화(전환 예상 시점, 다음 곡 준비 상태)
- 오류/디코딩 실패 시 UX 개선(리트라이, 사용자 알림)
