# ScreenTranslate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** macOS 메뉴바 앱 — 단축키로 화면 영역을 선택하면 OCR → 번역 → 플로팅 팝업으로 결과를 표시한다.

**Architecture:** SwiftUI `MenuBarExtra` 기반 메뉴바 앱. 화면 선택은 AppKit `NSWindow` 오버레이로 처리하고, OCR/번역은 각각 프로토콜로 추상화해 Apple Vision / Apple Translation을 기본 구현체로 사용한다. Apple Translation Framework는 SwiftUI `.translationTask` modifier가 필요하므로 `TranslationBridge` 패턴으로 연결한다. `TranslationCoordinator`가 전체 흐름을 조율한다.

**Tech Stack:** Swift 6 (Strict Concurrency), SwiftUI, AppKit, Vision framework (`RecognizeTextRequest`), Translation framework (macOS 15+), ScreenCaptureKit / SCScreenshotManager (macOS 14+), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (SPM)

---

## 준비사항

- macOS 15.0+ 개발 환경
- Xcode 16+
- Apple Developer 계정 (Screen Recording 권한 entitlement 필요)

---

## Phase 구성

| Phase | 파일 | Tasks | 내용 |
|-------|------|-------|------|
| **1** | [phase-1-project-setup.md](./phase-1-project-setup.md) | Task 1 | Xcode 프로젝트 생성, Info.plist, entitlements, SPM 의존성 |
| **2** | [phase-2-core-providers.md](./phase-2-core-providers.md) | Task 2, 3 | OCR Provider + Translation Provider + TranslationBridge |
| **3** | [phase-3-capture-pipeline.md](./phase-3-capture-pipeline.md) | Task 4, 5, 6 | TranslationCoordinator + 화면 선택 오버레이 + 화면 캡처 |
| **4** | [phase-4-ui.md](./phase-4-ui.md) | Task 7, 8, 9 | 번역 팝업 UI + 설정창 + 메뉴바 뷰 + 전체 연결 |
| **5** | [phase-5-permissions.md](./phase-5-permissions.md) | Task 10 | 권한 처리 및 첫 실행 안내 |

---

## 의존 관계

```
Phase 1: 프로젝트 셋업
  └─→ Phase 2: Core Providers (OCR + Translation)
        └─→ Phase 3: Capture Pipeline (Coordinator + Overlay + Capture)
              └─→ Phase 4: UI (Popup + Settings + MenuBar + 전체 연결)
                    └─→ Phase 5: Permissions (권한 처리 + 최종 테스트)
```

### Task 단위 의존 관계

```
Task 1 (프로젝트 셋업)
  ├─→ Task 2 (OCR Provider)
  └─→ Task 3 (Translation Provider + Bridge)
        │
        ├─→ Task 4 (TranslationCoordinator) ←── Task 2
        │     └─→ Task 5 (SelectionOverlay)
        │           └─→ Task 6 (ScreenCapture)
        │                 └─→ Task 7 (번역 팝업 UI) ←── Task 4
        │                       └─→ Task 8 (설정창)
        │                             └─→ Task 9 (메뉴바 + 전체 연결) ←── Task 4, 5, 6, 7, 8
        │                                   └─→ Task 10 (권한 처리)
        │
        └─ (TranslationBridge는 Task 9에서 AppDelegate에 호스팅)
```

---

## 완료 기준

- [ ] 모든 단위 테스트 PASS (`xcodebuild test`)
- [ ] 메뉴바에서 앱 동작
- [ ] 단축키 → 오버레이 → 드래그 → OCR → 번역 → 팝업 전체 플로우 동작
- [ ] 로딩 상태 표시 (인식 중 / 번역 중)
- [ ] 에러 상태 표시 (OCR 실패, 번역 실패, 권한 미승인)
- [ ] 복사 버튼 동작 + 피드백
- [ ] 설정에서 타겟 언어 변경 반영
- [ ] 설정에서 단축키 변경 가능
- [ ] ESC로 오버레이/팝업 닫기
- [ ] Retina 디스플레이에서 올바른 캡처
- [ ] 현재 마우스 위치 디스플레이에서 오버레이 표시

---

## 참고 문서

- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [Apple Translation Framework](https://developer.apple.com/documentation/translation)
- [TranslationSession.Configuration](https://developer.apple.com/documentation/translation/translationsession/configuration)
- [ScreenCaptureKit / SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [KeyboardShortcuts (sindresorhus)](https://github.com/sindresorhus/KeyboardShortcuts)
- [SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink)
- [@Observable + UserDefaults 패턴](https://fatbobman.com/en/posts/userdefaults-and-observation/)

---

## 변경 이력

### v1.3 (2026-03-02) — 구현계획서 Phase 분리

단일 파일(1,892줄)을 5개 Phase 파일 + Overview로 분리.

### v1.2 (2026-03-02) — 아키텍처/HIG 점검 피드백 반영

| Task | 변경 사항 |
|---|---|
| 전체 | Swift 5.9+ → Swift 6 (Strict Concurrency), `Sendable` 프로토콜/구조체 명시 |
| Task 2 | `VNRecognizeTextRequest` → `RecognizeTextRequest` (Swift-native async/await API), `OCRResult: Sendable`, `OCRProvider: Sendable`, `CGImage: @unchecked Sendable` |
| Task 3 | `TranslationProvider: Sendable` 추가 |
| Task 4 | `TranslationCoordinator`에 `@MainActor` 격리 추가 |
| Task 1, 9 | 기본 단축키 `Cmd+Shift+T` → `Ctrl+Shift+T` (Safari/Terminal 충돌 방지) |
| Task 5 | 오버레이 윈도우 레벨 `.screenSaver` → `.statusBar + 1` |
| Task 7 | NSPanel: `.nonactivatingPanel` → `becomesKeyOnlyIfNeeded = true`, `isMovableByWindowBackground = false` |
| Task 9 | TranslationBridge를 SwiftUI Window Scene 대신 AppDelegate의 상주 NSWindow에 호스팅 |
| Task 9 | AppOrchestrator 역할을 UI 생명주기 관리로 명확화 |
| Task 10 | PermissionGuard: NSAlert → floating NSPanel 팝업 (비모달) |

### v1.1 (2026-03-02) — 리뷰 피드백 반영

| Task | 변경 사항 |
|---|---|
| Task 1 | KeyboardShortcuts URL 수정: `nicklockwood` → `sindresorhus` |
| Task 2 | `OCRResult` 구조체 도입 (text + detectedLanguage + confidence), continuation 이중 resume 방지 |
| Task 3 | `TranslationBridge` 추가 — SwiftUI `.translationTask` modifier 연동. `AppleTranslationProvider`가 실제로 번역 수행 |
| Task 4 | `TranslationCoordinator`에 `TranslationResult` (lowConfidence 플래그), OCRResult 기반 언어 전달 |
| Task 5 | ESC를 AppKit `keyDown(with:)` override로 처리. 멀티 디스플레이: 현재 마우스 위치 디스플레이 감지 |
| Task 6 | `backingScaleFactor` 반영. 좌표 변환 로직 문서화 |
| Task 7 | 팝업에 로딩 상태 (스피너), 에러 상태, 낮은 신뢰도 경고 추가. 위치 보정 로직 강화 |
| Task 8 | `@Observable` + UserDefaults: `access(keyPath:)` / `withMutation(keyPath:)` 수동 호출 패턴 |
| Task 9 | `SettingsLink` 사용. `TranslationBridgeView` 삽입. 팝업 재실행 시 기존 닫기 |
| Task 10 | 권한 요청을 첫 번역 시도 시로 변경 (lazy) |
