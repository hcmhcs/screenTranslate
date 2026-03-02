# ScreenTranslate — 앱 설계 문서

**작성일**: 2026-03-02
**수정일**: 2026-03-02 (v1.3 — 아키텍처/동시성/좌표계 정밀 리뷰 반영)
**플랫폼**: macOS 15.0+
**목표**: 단축키 한 번으로 화면 영역을 선택 → OCR → 번역 → 팝업 표시

---

## 1. 개요

메뉴바에만 상주하는 macOS 앱. 단축키를 누르면 스크린샷처럼 화면 영역을 드래그로 선택하고, 해당 영역의 텍스트를 OCR로 인식한 뒤 번역 결과를 플로팅 팝업으로 표시한다. 모든 처리는 로컬에서 이루어지며, 추후 외부 API/모델로 교체할 수 있도록 설계한다.

> **최소 지원 버전 근거**: Apple Translation Framework가 macOS 15+(Sequoia)부터 사용 가능하며, 이것이 앱의 핵심 기능이므로 macOS 15.0을 최소 배포 타겟으로 설정한다. ScreenCaptureKit(`SCScreenshotManager.captureImage`)도 macOS 14+에서 추가된 API이므로 macOS 15 타겟에서 호환성 문제가 없다.

---

## 2. 기술 스택

| 역할 | 채택 기술 | 요구 버전 | 비고 |
|---|---|---|---|
| 언어 | Swift 6 | — | Strict Concurrency 활성화 |
| UI 프레임워크 | SwiftUI + AppKit | macOS 15+ | |
| 메뉴바 | `MenuBarExtra` (SwiftUI) | macOS 13+ | |
| 화면 캡처 | `ScreenCaptureKit` / `SCScreenshotManager` | macOS 14+ | |
| OCR (기본) | `Vision` / `RecognizeTextRequest` (Swift-native) | macOS 15+ | 기존 `VNRecognizeTextRequest`는 레거시. macOS 15+에서 도입된 새 async/await 네이티브 API 사용 |
| 번역 (기본) | `Translation` framework | macOS 15+ | SwiftUI `.translationTask` modifier 사용 |
| 전역 단축키 | [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (SPM) | — | 저자: sindresorhus |
| 패키지 관리 | Swift Package Manager | — | |

---

## 3. 아키텍처

### 3.1 레이어 구조

```
┌─────────────────────────────────────────┐
│                   UI Layer              │
│  MenuBarView │ SelectionOverlay │        │
│  TranslationPopup │ SettingsWindow      │
├─────────────────────────────────────────┤
│              Application Layer          │
│  AppOrchestrator (UI 생명주기 관리)       │
│    → 오버레이/팝업 윈도우 표시/숨김         │
│    → 권한 확인, 사용자 인터랙션 처리        │
│  TranslationCoordinator (데이터 파이프라인) │
│    → 캡처 → OCR → 번역 상태 머신          │
│    → @MainActor, Task 취소 관리          │
│  TranslationBridge (SwiftUI ↔ Session)  │
├──────────────────┬──────────────────────┤
│   OCR Provider   │ Translation Provider │
│   (Protocol)     │ (Protocol)           │
├──────────────────┴──────────────────────┤
│            Implementations              │
│  VisionOCRProvider (기본)               │
│  AppleTranslationProvider (기본)        │
└─────────────────────────────────────────┘
```

> **역할 분리**: `AppOrchestrator`는 UI 생명주기(오버레이 표시, 팝업 위치 결정, 윈도우 관리)를 담당하고, `TranslationCoordinator`는 순수 데이터 파이프라인(캡처→OCR→번역)의 상태 머신만 관리한다. `AppOrchestrator`가 `TranslationCoordinator`를 소유하고 결과를 받아 UI에 반영한다.
>
> **중요 — Coordinator 소유 방식**: `AppOrchestrator`는 `TranslationCoordinator`를 **stored 프로퍼티**로 소유해야 한다. computed 프로퍼티(`var coordinator: TranslationCoordinator { ... }`)로 구현하면 매번 새 인스턴스가 생성되어 `@Observable` 상태 추적이 불가능하고, 진행 중인 Task가 소실된다. 반드시 `let coordinator = TranslationCoordinator(...)` 형태로 선언한다.

### 3.2 Provider 프로토콜 (확장성 핵심)

```swift
// OCR 추상화
struct OCRResult: Sendable {
    let text: String
    let detectedLanguage: Locale.Language?
    let confidence: Float  // 0.0 ~ 1.0
}

protocol OCRProvider: Sendable {
    func recognize(image: CGImage) async throws -> OCRResult
}

// 번역 추상화
protocol TranslationProvider: Sendable {
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String

    /// Provider 이름 (설정 UI 표시용)
    var name: String { get }

    /// API Key가 필요한지 여부
    var requiresAPIKey: Bool { get }
}
```

> **Swift 6 Concurrency**: 모든 프로토콜과 데이터 타입에 `Sendable` 준수를 명시한다. `TranslationCoordinator`는 `@MainActor`로 격리하여 UI 상태와 안전하게 상호작용한다. `CGImage`는 Core Foundation 불변 타입이므로 `@unchecked Sendable` 확장으로 처리한다.
>
> **프로토콜 actor 격리 규칙**: `TranslationProvider` 프로토콜의 `translate(text:from:to:)` 메서드는 `nonisolated`로 선언된다. `AppleTranslationProvider`가 내부적으로 `@MainActor`인 `TranslationBridge`를 호출해야 하므로, 구현체 메서드에서 직접 `@MainActor`를 붙이면 프로토콜 준수 위반이 된다. 해결: (a) 프로토콜 자체에 `@MainActor`를 선언하거나, (b) 구현 메서드 내부에서 `await MainActor.run { ... }`로 호출한다. v1에서는 방법 (b)를 채택하여 프로토콜의 범용성을 유지한다.

**현재 구현체**
- `VisionOCRProvider` — Apple Vision Framework (`RecognizeTextRequest`), 완전 로컬
- `AppleTranslationProvider` — Apple Translation Framework, 완전 로컬

**추후 추가 가능한 구현체 예시**
- `TesseractOCRProvider` — 커스텀 로컬 OCR 모델
- `OpenAITranslationProvider` — API Key 기반
- `DeepLTranslationProvider` — API Key 기반
- `ArgosTranslationProvider` — 로컬 오픈소스 모델

설정창에서 Provider를 선택하면 `TranslationCoordinator`가 해당 구현체로 교체.

### 3.3 Apple Translation Framework 연동 설계

Apple Translation Framework는 SwiftUI의 `.translationTask` modifier를 통해 `TranslationSession`을 획득해야 한다. 순수 async 함수에서 직접 세션을 생성할 수 없으므로, **TranslationBridge** 패턴을 사용한다.

```
[TranslationCoordinator]
    ↓ 번역 요청 (text, source, target)
[TranslationBridge] — 숨겨진 SwiftUI View (크기 0)
    ↓ .translationTask(config) { session in ... }
[TranslationSession.translate(text)]
    ↓ 결과 반환
[TranslationCoordinator] → 팝업 표시
```

**핵심 구현 전략:**
1. `TranslationBridge`는 크기 0의 투명 SwiftUI View로, 앱 실행 중 항상 존재
2. `TranslationCoordinator`가 번역을 요청하면 `TranslationBridge`의 `@State config`를 업데이트
3. `.translationTask(config)` modifier가 트리거되어 `TranslationSession`을 획득하고 번역 수행
4. 결과를 `@Observable` 상태로 돌려보내 팝업에 표시

이 패턴을 통해 `TranslationProvider` 프로토콜의 순수 async 시그니처를 유지하면서도 SwiftUI 세션 요구사항을 충족한다.

**동시성 안전 (중요 — C1):**
`TranslationBridge`는 내부에 `CheckedContinuation`을 저장하여 async/await 패턴을 구현한다. 만약 이전 번역이 완료되기 전에 새 번역 요청이 들어오면, 기존 continuation이 resume되지 않은 채 덮어씌워져 **메모리 누수 및 크래시**가 발생한다. 반드시 다음 중 하나로 보호한다:
- 새 요청 시 기존 continuation을 `.translationFailed("취소됨")`으로 resume한 후 교체
- 또는 `isTranslating == true`일 때 새 요청을 거부 (v1 채택)

```swift
// 안전한 패턴 예시
func translate(...) async throws -> String {
    if let existing = continuation {
        existing.resume(throwing: TranslationError.translationFailed("이전 요청 취소"))
        continuation = nil
    }
    return try await withCheckedThrowingContinuation { cont in
        self.continuation = cont
        // ...
    }
}
```

**Configuration 재트리거 (중요 — C5):**
`.translationTask(configuration)` modifier는 `configuration` 값이 **변경**되어야 트리거된다. 같은 언어쌍으로 연속 번역할 경우 동일한 `Configuration` 객체가 설정되어 `.translationTask`가 재트리거되지 않을 수 있다. 해결:
- 매 번역 요청 전 `configuration`을 `nil`로 리셋한 후 새 값을 설정
- 또는 `Configuration.invalidate()`를 호출하여 강제 재트리거

```swift
// 권장 패턴: nil 리셋 → 새 configuration 설정
self.configuration = nil
// SwiftUI 업데이트 사이클 후
self.configuration = TranslationSession.Configuration(source: source, target: target)
```

**TranslationBridge 호스팅 전략 (중요):**

`MenuBarExtra`의 콘텐츠 뷰는 메뉴가 열릴 때만 생성되고 닫히면 파괴되므로, `TranslationBridge`를 `MenuBarExtra` 안에 배치하면 세션이 소멸한다. 이를 해결하기 위해 **전용 상주 NSWindow**를 사용한다:

1. 앱 시작 시 `AppDelegate`에서 크기 0, off-screen의 `NSWindow`를 생성
2. `NSHostingView`로 `TranslationBridge` SwiftUI 뷰를 호스팅
3. `window.orderOut(nil)`로 숨기되 메모리에서 해제하지 않음
4. 이 윈도우는 앱 전체 생명주기 동안 유지되어 `.translationTask` modifier가 항상 활성 상태

```swift
// TranslationBridgeWindow — 앱 시작 시 생성, 앱 종료까지 유지
let bridgeWindow = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
bridgeWindow.contentView = NSHostingView(rootView: TranslationBridgeView())
bridgeWindow.orderOut(nil)  // 숨김 상태로 유지
```

### 3.4 언어팩 다운로드 흐름

Apple Translation Framework는 언어 모델을 로컬에 다운로드해야 번역이 가능하다.

**최초 사용 시 흐름:**
1. 사용자가 번역을 시도
2. 해당 언어쌍의 언어팩이 없으면 → 시스템이 다운로드 프롬프트를 자동으로 표시 (Apple 제공 UI)
3. 다운로드 완료 후 → 번역 수행

**앱 수준에서의 처리:**
- 언어팩 다운로드는 Apple 시스템 UI가 자동으로 처리하므로 별도의 커스텀 UI 불필요
- 다운로드 중 상태는 팝업에 "언어팩 다운로드 중..." 메시지로 표시
- 다운로드 실패 시 팝업에 에러 메시지 표시 + 재시도 안내

---

## 4. 핵심 플로우

### 4.1 정상 플로우 (Happy Path)

```
[단축키: Ctrl+Shift+T (기본값)]
        │
        ▼
[전체 화면 투명 오버레이 표시]
  (SelectionOverlayWindow — NSWindow, level: .statusBar + 1)
  현재 마우스가 위치한 디스플레이에만 표시
        │
        ▼
[사용자 드래그로 영역 선택]
  (마우스 다운 → 드래그 → 업)
  최소 선택 크기: 10x10pt (미만 시 취소 처리)
  ⚠️ 좌표계: SwiftUI DragGesture(.global)는 윈도우-로컬 좌상단 원점 좌표를 반환
        │
        ▼
[좌표 변환: 윈도우-로컬 → 스크린-글로벌]
  SwiftUI 좌표(윈도우 기준 좌상단 원점) → AppKit 스크린 좌표(좌하단 원점) 변환
  변환 공식: screenY = screen.frame.maxY - windowLocalY
  이 변환된 좌표를 캡처 영역 계산과 팝업 위치 계산에 모두 사용
        │
        ▼
[ScreenCaptureKit으로 영역 캡처]
  → CGImage (Retina scale factor 반영)
        │
        ▼
[로딩 팝업 표시 — "인식 중..."]
  선택 영역 하단에 스피너 + "인식 중..." 텍스트
  ⚠️ TranslationCoordinator가 state를 .recognizing으로 설정 → UI가 관찰하여 표시
        │
        ▼
[OCRProvider.recognize(image:)]
  VisionOCRProvider: RecognizeTextRequest (Swift-native Vision API)
  반환: OCRResult { text, detectedLanguage, confidence }
        │
        ▼
[로딩 팝업 업데이트 — "번역 중..."]
  ⚠️ TranslationCoordinator가 state를 .translating으로 설정 → UI가 관찰하여 업데이트
  (중요: process() 내부에서 OCR 완료 후, 번역 호출 전에 state 변경해야 UI가 반영됨)
        │
        ▼
[TranslationProvider.translate(text:from:to:)]
  AppleTranslationProvider: TranslationBridge → .translationTask
        │
        ▼
[TranslationPopup 표시]
  위치: 선택 영역 하단 근처
  내용: 번역 결과 + [복사] [닫기] 버튼
        │
  ESC 또는 팝업 바깥 클릭 → 팝업 닫힘
```

### 4.2 에러 플로우

| 실패 지점 | 시나리오 | 사용자 대면 동작 |
|---|---|---|
| 단축키 실행 | Screen Recording 권한 미승인 | floating 팝업으로 권한 안내 + 시스템 설정 열기 버튼 (비모달) |
| 오버레이 | ESC 키 또는 클릭 없이 드래그 | 오버레이 닫힘, 아무 동작 없음 |
| 오버레이 | 드래그 영역 < 10x10pt | 오버레이 닫힘, 취소 처리 |
| 캡처 | 디스플레이를 찾을 수 없음 | 팝업에 "화면 캡처에 실패했습니다" 표시 |
| OCR | 텍스트를 찾을 수 없음 | 팝업에 "선택한 영역에서 텍스트를 찾을 수 없습니다" 표시 |
| OCR | 인식률 매우 낮음 (confidence < 0.3) | 팝업에 경고 아이콘 + "인식 정확도가 낮습니다" 부가 표시 |
| 번역 | 언어팩 미다운로드 | 시스템 다운로드 프롬프트 자동 표시 → 팝업에 "언어팩 다운로드 중..." |
| 번역 | 미지원 언어쌍 | 팝업에 "이 언어 조합은 지원되지 않습니다" 표시 |
| 번역 | 기타 번역 실패 | 팝업에 "번역에 실패했습니다: [에러 메시지]" 표시 |
| 처리 중 | 사용자가 ESC 누름 | 진행 중인 작업 취소, 팝업/로딩 닫힘 |

**처리 중 ESC 취소 메커니즘 (중요 — H4):**
`TranslationCoordinator`는 `process()` 호출 시 생성한 `Task`의 참조를 stored 프로퍼티로 보관한다. ESC가 눌리면 `AppOrchestrator`가 이 Task를 `.cancel()`하고 coordinator의 상태를 `.idle`로 리셋한다. `process()` 내부에서는 각 단계(캡처 후, OCR 후) 사이에 `try Task.checkCancellation()`을 삽입하여 취소를 빠르게 전파한다.

```swift
// TranslationCoordinator
private var currentTask: Task<Void, Never>?

func startProcessing(rect: CGRect, on display: ...) {
    currentTask?.cancel()
    currentTask = Task {
        do {
            state = .recognizing
            let image = try await capturer.capture(...)
            try Task.checkCancellation()  // ESC 체크 포인트
            let ocrResult = try await ocrProvider.recognize(image: image)
            try Task.checkCancellation()  // ESC 체크 포인트
            state = .translating
            let translated = try await translationProvider.translate(...)
            state = .completed(translated)
        } catch is CancellationError {
            state = .idle  // 조용히 취소
        } catch {
            state = .failed(error)
        }
    }
}

func cancel() {
    currentTask?.cancel()
    currentTask = nil
    state = .idle
}
```

**공통 에러 표시 패턴:**
- 에러 시에도 동일한 팝업 UI를 사용하되, 텍스트 색상을 `.secondary`로 변경
- 모든 에러 팝업에 [닫기] 버튼 포함
- 로깅: v1에서는 `os_log`로 디버그 로그만 기록 (사용자 노출 없음)

---

## 5. UI 컴포넌트

### 5.1 메뉴바

```
[text.viewfinder] ← SF Symbol 아이콘
  ├── 번역하기 (Ctrl+Shift+T)
  ├── ─────────────────
  ├── 설정... (Cmd+,)
  ├── ─────────────────
  └── ScreenTranslate 종료 (Cmd+Q)
```

> **기본 단축키 변경 근거**: `Cmd+Shift+T`는 Safari(닫은 탭 다시 열기), Terminal(새 탭), Chrome 등에서 널리 사용된다. 전역 핫키(Carbon)는 OS 레벨에서 가로채므로 이 앱들의 기능이 완전히 깨진다. `Ctrl+Shift+T`는 주요 앱과 충돌이 적다. 사용자가 설정에서 자유롭게 변경 가능.

> **LSUIElement 앱의 단축키 제한**: `LSUIElement = true` 앱에서는 표준 앱 메뉴가 없으므로, `Cmd+Q`와 `Cmd+,`는 메뉴바 드롭다운이 열려있을 때만 동작한다. 다른 앱이 포커스된 상태에서는 해당 앱의 단축키가 우선한다. 이 제한을 인지하고 메뉴 아이템의 단축키 레이블은 시각적 안내 용도로 유지한다.

- Dock 아이콘 없음 (`LSUIElement = true` in Info.plist)
- 메뉴바 아이콘: `text.viewfinder` (SF Symbol, 텍스트 인식을 연상)
- Settings는 macOS 표준 단축키 `Cmd+,` 사용 (SwiftUI `Settings` Scene이 자동 처리)

### 5.2 SelectionOverlay

- `NSWindow` (전체 화면, borderless, level: `.statusBar + 1`)
- 배경: 반투명 어두운 오버레이 (`rgba(0,0,0,0.3)`)
- 드래그 중: 선택 영역을 밝게 표시 (마치 macOS 스크린샷처럼)
- 커서: 크로스헤어 (`NSCursor.crosshair`)
- ESC: AppKit `keyDown(with:)` override로 처리 (SwiftUI `onKeyPress`는 포커스 필요)
- 최소 선택 크기: 10x10pt (미만 시 취소 처리)
- 클릭만 하고 드래그하지 않은 경우: 취소 처리

**멀티 디스플레이 동작 (v1):**
- 오버레이는 현재 마우스 커서가 위치한 디스플레이에만 표시
- 디스플레이 간 드래그 선택은 v1에서 지원하지 않음
- `NSScreen.main` 대신 `NSEvent.mouseLocation` 기반으로 현재 디스플레이를 감지

**SCDisplay 매칭 (중요 — H7):**
ScreenCaptureKit의 `SCDisplay`와 AppKit의 `NSScreen`을 매칭할 때, **frame 교차 비교가 아닌 `displayID`로 매칭**해야 한다. `NSScreen`의 `deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`로 `CGDirectDisplayID`를 얻고, `SCDisplay.displayID`와 비교한다. frame 비교는 Retina 스케일링, 디스플레이 배치 변경 등으로 불일치할 수 있다.

```swift
// 올바른 매칭 패턴
let mouseScreen = NSScreen.screens.first { screen in
    screen.frame.contains(NSEvent.mouseLocation)
}
let screenID = mouseScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
let scDisplay = availableDisplays.first { $0.displayID == screenID }
```

### 5.3 TranslationPopup

```
┌──────────────────────────────────────┐
│  번역된 텍스트가 여기 표시됩니다.       │
│  긴 텍스트는 스크롤 가능.              │
│  텍스트 선택(드래그) 가능.             │
│                                      │
│                     [복사]  [닫기]    │
└──────────────────────────────────────┘
```

- SwiftUI `NSPanel` (floating, `becomesKeyOnlyIfNeeded = true`)
- `.regularMaterial` 배경 (vibrancy 지원, 다크모드 자동 대응)
- 최대 너비 400pt, 최대 높이 300pt (초과 시 스크롤)
- 텍스트 선택 가능 (`.textSelection(.enabled)`)
- 이동: `isMovableByWindowBackground = false`, 상단 드래그 핸들 영역 제공

> **NSPanel 설정 근거**: Non-activating 패널은 key window가 되지 않으므로 텍스트 선택(`.textSelection(.enabled)`)이 작동하지 않는다. `becomesKeyOnlyIfNeeded = true`를 사용하면 팝업 내부 클릭 시 key window가 되어 텍스트 선택이 가능하면서도, 앱 활성화(다른 앱 윈도우 가리기)를 방지한다.
> `isMovableByWindowBackground = true`는 텍스트 드래그 선택과 충돌하므로, 별도의 드래그 핸들 영역(상단 바)을 두어 윈도우 이동과 텍스트 선택을 분리한다.

**위치 결정 로직 (중요 — H2):**
1. 기본: 선택 영역 하단 8pt 아래
2. 하단이 화면 밖 → 선택 영역 상단 8pt 위
3. 오른쪽이 화면 밖 → 왼쪽으로 보정
4. **좌표 변환 필수**: 선택 영역의 SwiftUI 좌표(윈도우-로컬, 좌상단 원점)를 AppKit 스크린 좌표(글로벌, 좌하단 원점)로 변환해야 한다. `NSWindow.convertPoint(toScreen:)`을 활용하거나, 오버레이가 전체 화면이므로 `screen.frame.maxY - localY`로 변환한다. 변환 없이 SwiftUI 좌표를 직접 `NSPanel.setFrameOrigin()`에 전달하면 팝업이 화면 반대편에 표시된다.

```swift
// 좌표 변환 예시: 오버레이 내 SwiftUI 좌표 → AppKit 스크린 좌표
let screenFrame = overlayWindow.screen?.frame ?? NSScreen.main!.frame
let appKitX = screenFrame.origin.x + selectionRect.origin.x
let appKitY = screenFrame.maxY - selectionRect.maxY - 8  // 선택 영역 하단 8pt 아래
panel.setFrameOrigin(NSPoint(x: appKitX, y: appKitY - panelHeight))
```

**NSPanel 윈도우 재사용 (중요 — H1):**
팝업을 표시할 때마다 새 `NSPanel`과 `NSHostingView`를 생성하면 뷰 트리가 처음부터 재구성되어 깜빡임(flicker)이 발생한다. 대신 `NSPanel`을 한 번 생성하여 재사용하고, 내부 `NSHostingView.rootView`를 업데이트하는 방식을 사용한다.

```swift
// 팝업 재사용 패턴
if let existingPanel = popupWindow {
    (existingPanel.contentView as? NSHostingView<TranslationPopupView>)?.rootView = newPopupView
    existingPanel.setFrameOrigin(newOrigin)
    existingPanel.makeKeyAndOrderFront(nil)
} else {
    // 최초 1회만 생성
    popupWindow = createPanel(with: newPopupView)
}
```

**팝업 동작 상세:**
- 팝업 내부 클릭: 팝업 유지 (텍스트 선택, 버튼 클릭 등)
- **팝업 외부 클릭 닫기 (H5)**: `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)`으로 글로벌 마우스 이벤트를 감지하여, 클릭 위치가 팝업 프레임 외부이면 팝업을 닫는다. 팝업이 닫힐 때 반드시 `NSEvent.removeMonitor()`로 모니터를 해제한다. SwiftUI의 `onTapGesture`나 `background`의 터치 영역으로는 앱 외부 클릭을 감지할 수 없으므로 AppKit 글로벌 모니터가 필수이다.
- ESC: 팝업 닫힘 (`.keyboardShortcut(.cancelAction)`)
- 복사 버튼 클릭: 클립보드에 복사 → 버튼 텍스트 1.5초간 "복사됨" 표시
- 팝업이 표시된 상태에서 다시 단축키: 기존 팝업 닫힘 → 새 선택 시작
- 로딩 상태: 스피너 + "인식 중..." / "번역 중..." 텍스트 표시

### 5.4 SettingsWindow

macOS HIG에 따라 `Settings` Scene 사용 (Cmd+, 자동 연결).

| 섹션 | 항목 | 비고 |
|---|---|---|
| 번역 | 타겟 언어 (기본: 한국어) | Picker, `.menu` 스타일 |
| 번역 | OCR Provider 선택 (기본: Apple Vision) | v1에서는 단일 옵션 |
| 번역 | Translation Provider 선택 (기본: Apple Translation) | v1에서는 단일 옵션 |
| 번역 | API Key 입력 (해당 Provider 선택 시 활성화) | v1에서는 비활성 |
| 단축키 | 번역 단축키 (기본: Ctrl+Shift+T) | `KeyboardShortcuts.Recorder` |

---

## 6. 언어 설정

- **소스 언어**: 자동 감지 (Vision OCR의 `automaticallyDetectsLanguage`, `OCRResult.detectedLanguage`로 전달)
- **타겟 언어**: 사용자 설정 (기본: 한국어 `ko`)
- **지원 언어**: Apple Translation Framework 지원 언어쌍에 한함
- **미지원 언어쌍 처리**: 팝업에 "이 언어 조합은 지원되지 않습니다" 에러 표시

Apple Translation Framework 지원 언어 (macOS 15 기준): 영어, 한국어, 일본어, 중국어(간/번체), 스페인어, 프랑스어, 독일어, 이탈리아어, 포르투갈어, 러시아어, 아랍어, 힌디어, 인도네시아어, 태국어, 터키어, 베트남어, 폴란드어, 우크라이나어 등.

> **참고**: 모든 언어 간 직접 번역이 되는 것은 아니며, 일부 언어쌍은 영어를 pivot language로 사용한다.

---

## 7. 데이터 저장

- 설정값: `UserDefaults` (`@Observable` 저장 프로퍼티 + `didSet` 패턴, 또는 `access(keyPath:)` / `withMutation(keyPath:)` 수동 호출)
- API Key: `Keychain` (보안 저장) — v2에서 활성화
- 히스토리 기능 없음 (v1)
- 키 네이밍: `"com.screentranslate.<항목명>"` 형식으로 네임스페이스 적용

---

## 8. 권한

| 권한 | 용도 | 요청 시점 |
|---|---|---|
| Screen Recording | 화면 캡처 (`ScreenCaptureKit`) | 첫 번역 시도 시 |

**필수 Info.plist 키 (H6):**
```xml
<key>NSScreenCaptureUsageDescription</key>
<string>선택한 화면 영역의 텍스트를 인식하고 번역하기 위해 화면 접근 권한이 필요합니다.</string>
```
> 이 키가 없으면 macOS가 Screen Recording 권한 요청 다이얼로그를 표시하지 않으며, `SCShareableContent` 호출 시 즉시 거부될 수 있다.

**권한 처리 흐름:**
1. 앱 최초 실행 → 메뉴바에 아이콘만 표시 (권한 요청 안 함)
2. 사용자가 첫 번역을 시도 → `SCShareableContent`으로 권한 확인
3. 미승인 시 → TranslationPopup과 동일한 floating 팝업으로 안내 (모달 NSAlert 사용하지 않음)
   - 팝업 내용: "화면 접근 권한이 필요합니다" + [시스템 설정 열기] [닫기] 버튼
   - 사용자가 가벼운 핫키 인터랙션을 기대하므로 블로킹 모달 대신 비모달 팝업 사용
4. 시스템 설정 URL: `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`
5. 권한 승인 후 자동으로 다시 번역 시작하지 않음 → 사용자가 재시도

> **참고**: `KeyboardShortcuts` 라이브러리는 Carbon 기반 전역 핫키 API를 사용하므로 Accessibility 권한이 별도로 필요하지 않다.

---

## 9. v1 범위 (현재 구현 대상)

- [x] 메뉴바 앱 (Dock 없음)
- [x] 단축키로 오버레이 실행 (기본: Ctrl+Shift+T, 변경 가능)
- [x] 드래그로 화면 영역 선택 (현재 디스플레이만)
- [x] Apple Vision OCR (OCRResult: 텍스트 + 감지 언어 + 신뢰도)
- [x] Apple Translation 로컬 번역 (TranslationBridge 패턴)
- [x] 번역 팝업 (결과 + 복사 버튼 + 에러 표시)
- [x] 로딩 상태 표시 (스피너 + 진행 텍스트)
- [x] 설정창 (언어, 단축키) — Cmd+, 연동
- [x] OCRProvider / TranslationProvider 프로토콜 추상화
- [x] 에러 처리 (권한, OCR 실패, 번역 실패, 미지원 언어)
- [x] ESC로 모든 단계에서 취소 가능

## 10. v2+ 후보 기능 (현재 구현 제외)

- [ ] 다양한 Translation Provider (OpenAI, DeepL, Argos)
- [ ] 다양한 OCR Provider (Tesseract, 커스텀 모델)
- [ ] 멀티 디스플레이 간 드래그 선택
- [ ] 번역 히스토리
- [ ] 텍스트 오버레이 (원문 위에 번역문 표시)
- [ ] 자동 언어 감지 결과 표시 (감지된 언어 UI 표시)
- [ ] 로그인 시 자동 시작 (Login Items)
- [ ] 자동 업데이트 (Sparkle 또는 App Store)
- [ ] 배포 방식 결정 (App Store vs 직접 배포)

---

## 11. 디렉토리 구조 (예정)

```
ScreenTranslate/
├── App/
│   ├── ScreenTranslateApp.swift        # @main, MenuBarExtra, Settings Scene
│   ├── AppOrchestrator.swift           # UI 생명주기 관리 (오버레이/팝업 윈도우 표시·숨김, 권한 확인)
│   └── PermissionGuard.swift           # Screen Recording 권한 확인
├── Core/
│   ├── OCR/
│   │   ├── OCRProvider.swift           # Protocol + OCRResult
│   │   └── VisionOCRProvider.swift     # Apple Vision 구현체
│   ├── Translation/
│   │   ├── TranslationProvider.swift   # Protocol
│   │   ├── AppleTranslationProvider.swift  # Apple Translation 구현체
│   │   └── TranslationBridge.swift     # SwiftUI ↔ TranslationSession 브릿지
│   ├── ScreenCapture/
│   │   └── ScreenCapturer.swift        # ScreenCaptureKit 래퍼
│   └── TranslationCoordinator.swift    # @MainActor 데이터 파이프라인 상태 머신 (idle/recognizing/translating/completed/failed)
├── UI/
│   ├── MenuBar/
│   │   └── MenuBarView.swift           # 메뉴바 드롭다운 메뉴
│   ├── Overlay/
│   │   ├── SelectionOverlayWindow.swift  # NSWindow 서브클래스 (keyDown ESC 처리)
│   │   └── SelectionOverlayView.swift    # SwiftUI 드래그 선택 UI
│   ├── Popup/
│   │   ├── TranslationPopupView.swift    # 번역 결과 + 로딩 + 에러 표시
│   │   └── TranslationPopupWindow.swift  # NSPanel (floating, becomesKeyOnlyIfNeeded)
│   └── Settings/
│       ├── SettingsView.swift            # 설정 폼 (언어, 단축키, Provider)
│       └── AppSettings.swift             # @Observable + UserDefaults 래퍼
└── ScreenTranslateTests/
    ├── Core/
    │   ├── OCR/
    │   │   └── VisionOCRProviderTests.swift
    │   ├── Translation/
    │   │   ├── MockTranslationProvider.swift
    │   │   └── TranslationProviderTests.swift
    │   └── TranslationCoordinatorTests.swift
    └── Mocks/
        └── MockOCRProvider.swift
```
