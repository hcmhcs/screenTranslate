# Phase 4: UI

> [← Phase 3](./phase-3-capture-pipeline.md) | [Overview](./00-overview.md) | [Phase 5 →](./phase-5-permissions.md)

---

## Task 7: 번역 팝업 UI (로딩/에러 상태 포함)

**Files:**
- Create: `ScreenTranslate/UI/Popup/TranslationPopupView.swift`
- Create: `ScreenTranslate/UI/Popup/TranslationPopupWindow.swift`

**Step 1: TranslationPopupView 작성 (로딩 + 에러 + 결과)**

`ScreenTranslate/UI/Popup/TranslationPopupView.swift`:

```swift
import SwiftUI

struct TranslationPopupView: View {
    let state: TranslationCoordinator.State
    let onCopy: (String) -> Void
    let onClose: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .idle:
                EmptyView()

            case .recognizing:
                loadingView(message: "인식 중...")

            case .translating:
                loadingView(message: "번역 중...")

            case .completed(let result):
                completedView(result: result)

            case .failed(let message):
                errorView(message: message)
            }

            HStack {
                Spacer()

                if case .completed(let result) = state {
                    Button(didCopy ? "복사됨" : "복사") {
                        onCopy(result.text)
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            didCopy = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(didCopy ? .green : .accentColor)
                }

                Button("닫기") {
                    onClose()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12, y: 4)
    }

    // MARK: - Subviews

    private func loadingView(message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private func completedView(result: TranslationCoordinator.TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.lowConfidence {
                Label("인식 정확도가 낮습니다", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView {
                Text(result.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
```

**Step 2: TranslationPopupWindow 작성**

`ScreenTranslate/UI/Popup/TranslationPopupWindow.swift`:

```swift
import AppKit
import SwiftUI

final class TranslationPopupWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false  // 텍스트 드래그 선택과 충돌 방지
        hidesOnDeactivate = false
    }

    /// ⚠️ H1: NSHostingView를 재사용하여 rootView만 교체한다.
    /// 매번 새 NSHostingView를 생성하면 뷰 트리가 처음부터 재구성되어 깜빡임이 발생한다.
    private var hostingView: NSHostingView<TranslationPopupView>?

    /// 최초 표시용 — 윈도우 위치를 설정하고 표시한다.
    func show(state: TranslationCoordinator.State, near selectionRect: CGRect, on screen: NSScreen? = nil) {
        let popupView = makePopupView(state: state)

        if let existing = hostingView {
            existing.rootView = popupView
        } else {
            let hv = NSHostingView(rootView: popupView)
            hv.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
            contentView = hv
            hostingView = hv
        }

        let origin = calculateOrigin(near: selectionRect, on: screen)
        setFrameOrigin(origin)
        setContentSize(NSSize(width: 400, height: 300))
        makeKeyAndOrderFront(nil)
    }

    /// ⚠️ H1: 상태만 업데이트 — NSHostingView.rootView 교체로 깜빡임 없이 갱신
    func updateState(_ state: TranslationCoordinator.State, near selectionRect: CGRect, on screen: NSScreen? = nil) {
        let popupView = makePopupView(state: state)

        if let existing = hostingView {
            existing.rootView = popupView
        } else {
            show(state: state, near: selectionRect, on: screen)
        }
    }

    private func makePopupView(state: TranslationCoordinator.State) -> TranslationPopupView {
        TranslationPopupView(
            state: state,
            onCopy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
    }

    /// ⚠️ H2: 좌표 변환 — SwiftUI 좌상단 원점(윈도우-로컬) → AppKit 좌하단 원점(스크린-글로벌)
    /// 오버레이가 전체 화면이므로 윈도우-로컬 ≈ 스크린-로컬(좌상단)이다.
    /// AppKit의 NSWindow.setFrameOrigin은 좌하단 원점을 기대하므로 Y축 변환이 필요하다.
    private func calculateOrigin(near selectionRect: CGRect, on screen: NSScreen?) -> NSPoint {
        let targetScreen = screen ?? NSScreen.main!
        let screenFrame = targetScreen.frame
        let popupHeight: CGFloat = 300
        let popupWidth: CGFloat = 400
        let gap: CGFloat = 8

        // SwiftUI 좌상단 → AppKit 좌하단 변환
        let appKitX = screenFrame.origin.x + selectionRect.origin.x
        let appKitSelectionBottom = screenFrame.maxY - selectionRect.maxY

        // 기본 위치: 선택 영역 하단 8pt 아래
        var origin = CGPoint(
            x: appKitX,
            y: appKitSelectionBottom - popupHeight - gap
        )

        // 하단이 화면 밖 → 선택 영역 상단으로
        if origin.y < screenFrame.minY {
            let appKitSelectionTop = screenFrame.maxY - selectionRect.minY
            origin.y = appKitSelectionTop + gap
        }

        // 오른쪽이 화면 밖 → 왼쪽으로 보정
        if origin.x + popupWidth > screenFrame.maxX {
            origin.x = screenFrame.maxX - popupWidth - gap
        }

        // 왼쪽이 화면 밖 → 최소 gap 유지
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + gap
        }

        return origin
    }

    override var canBecomeKey: Bool { true }
}
```

**Step 3: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

**Step 4: Commit**

```bash
git add ScreenTranslate/UI/Popup/
git commit -m "feat: add TranslationPopupView with loading, error, and result states"
```

---

## Task 8: 설정창 (SettingsView + AppSettings)

**Files:**
- Create: `ScreenTranslate/UI/Settings/AppSettings.swift`
- Create: `ScreenTranslate/UI/Settings/SettingsView.swift`

**Step 1: AppSettings 작성 (@Observable 수동 tracking)**

`ScreenTranslate/UI/Settings/AppSettings.swift`:

```swift
import Foundation
import Observation

/// @Observable + UserDefaults 연동.
/// computed property에서는 @Observable의 자동 tracking이 동작하지 않으므로
/// access(keyPath:) / withMutation(keyPath:) 를 수동으로 호출한다.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Target Language

    @ObservationIgnored
    private var _targetLanguageCode: String?

    var targetLanguageCode: String {
        get {
            access(keyPath: \.targetLanguageCode)
            return UserDefaults.standard.string(forKey: "com.screentranslate.targetLanguageCode") ?? "ko"
        }
        set {
            withMutation(keyPath: \.targetLanguageCode) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.targetLanguageCode")
            }
        }
    }

    // MARK: - OCR Provider

    @ObservationIgnored
    private var _ocrProviderName: String?

    var ocrProviderName: String {
        get {
            access(keyPath: \.ocrProviderName)
            return UserDefaults.standard.string(forKey: "com.screentranslate.ocrProviderName") ?? "Apple Vision"
        }
        set {
            withMutation(keyPath: \.ocrProviderName) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.ocrProviderName")
            }
        }
    }

    // MARK: - Translation Provider

    @ObservationIgnored
    private var _translationProviderName: String?

    var translationProviderName: String {
        get {
            access(keyPath: \.translationProviderName)
            return UserDefaults.standard.string(forKey: "com.screentranslate.translationProviderName") ?? "Apple Translation"
        }
        set {
            withMutation(keyPath: \.translationProviderName) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.translationProviderName")
            }
        }
    }

    // MARK: - Computed Helpers

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetLanguageCode)
    }

    // MARK: - Supported Languages

    static let supportedLanguages: [(code: String, name: String)] = [
        ("ko", "한국어"),
        ("en", "English"),
        ("ja", "日本語"),
        ("zh-Hans", "中文(简体)"),
        ("zh-Hant", "中文(繁體)"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("pt", "Português"),
        ("it", "Italiano"),
        ("ru", "Русский"),
        ("ar", "العربية"),
    ]
}
```

> **변경점**: `@ObservationIgnored` 더미 프로퍼티와 `access(keyPath:)` / `withMutation(keyPath:)` 수동 호출로 `@Observable` + UserDefaults computed property가 SwiftUI 뷰 업데이트를 올바르게 트리거한다.

**Step 2: SettingsView 작성**

`ScreenTranslate/UI/Settings/SettingsView.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("번역") {
                Picker("번역 결과 언어", selection: $settings.targetLanguageCode) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)

                Picker("OCR 엔진", selection: $settings.ocrProviderName) {
                    Text("Apple Vision").tag("Apple Vision")
                }
                .pickerStyle(.menu)
                .disabled(true)  // v1에서는 단일 옵션

                Picker("번역 엔진", selection: $settings.translationProviderName) {
                    Text("Apple Translation (로컬)").tag("Apple Translation")
                }
                .pickerStyle(.menu)
                .disabled(true)  // v1에서는 단일 옵션
            }

            Section("단축키") {
                KeyboardShortcuts.Recorder("번역 단축키", name: .translate)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 280)
    }
}
```

**Step 3: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

**Step 4: Commit**

```bash
git add ScreenTranslate/UI/Settings/
git commit -m "feat: add SettingsView and AppSettings with manual Observable tracking"
```

---

## Task 9: 메뉴바 뷰 + 전체 연결

**Files:**
- Modify: `ScreenTranslate/App/ScreenTranslateApp.swift`
- Modify: `ScreenTranslate/UI/MenuBar/MenuBarView.swift`
- Create: `ScreenTranslate/App/AppOrchestrator.swift`

**Step 1: AppOrchestrator 작성 (전체 흐름 관리)**

`ScreenTranslate/App/AppOrchestrator.swift`:

```swift
import AppKit
import CoreGraphics
import KeyboardShortcuts
import Observation

/// UI 생명주기를 관리하는 싱글턴.
/// 오버레이/팝업 윈도우 표시·숨김, 권한 확인, 사용자 인터랙션 처리.
/// 데이터 파이프라인(캡처→OCR→번역)은 TranslationCoordinator에 위임한다.
@Observable
@MainActor
final class AppOrchestrator {
    static let shared = AppOrchestrator()

    private var overlayWindow: SelectionOverlayWindow?
    private var popupWindow: TranslationPopupWindow?
    private let capturer = ScreenCapturer()
    private var currentScreen: NSScreen?

    /// ⚠️ C2: stored 프로퍼티로 소유. computed 프로퍼티로 만들면 매번 새 인스턴스가
    /// 생성되어 @Observable 상태 추적이 불가능하고, 진행 중인 Task가 소실된다.
    let coordinator = TranslationCoordinator(
        ocrProvider: VisionOCRProvider(),
        translationProvider: AppleTranslationProvider(),
        targetLanguage: AppSettings.shared.targetLanguage
    )

    func setup() {
        KeyboardShortcuts.onKeyUp(for: .translate) { [weak self] in
            Task { @MainActor in
                self?.startTranslation()
            }
        }
    }

    func startTranslation() {
        // ⚠️ H4: 기존 작업 취소 + 팝업 닫기
        coordinator.cancel()
        removeClickOutsideMonitor()
        popupWindow?.close()
        popupWindow = nil

        // 권한 확인
        Task {
            let hasPermission = await ScreenCapturer.checkPermission()
            guard hasPermission else {
                await PermissionGuard.requestScreenRecordingPermission()
                return
            }

            // 현재 마우스 위치의 디스플레이 감지
            let mouseLocation = NSEvent.mouseLocation
            currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

            overlayWindow = SelectionOverlayWindow()
            overlayWindow?.show { [weak self] rect in
                guard let self, let rect else { return }
                Task { @MainActor in
                    await self.processCapture(rect: rect)
                }
            }
        }
    }

    /// ⚠️ H5: 팝업 외부 클릭 감지용 글로벌 마우스 모니터
    private var clickMonitor: Any?

    private func processCapture(rect: CGRect) async {
        // ⚠️ H1: 팝업 윈도우를 재사용하여 NSHostingView 재생성으로 인한 깜빡임 방지
        let popup: TranslationPopupWindow
        if let existing = popupWindow {
            popup = existing
        } else {
            popup = TranslationPopupWindow()
            self.popupWindow = popup
        }

        // 로딩 상태 표시
        popup.show(state: .recognizing, near: rect, on: currentScreen)

        // ⚠️ H5: 팝업 외부 클릭 시 닫기 — 글로벌 마우스 이벤트 모니터
        installClickOutsideMonitor(for: popup)

        do {
            let image = try await capturer.capture(rect: rect, screen: currentScreen)

            // ⚠️ C4/H4: coordinator의 startProcessing()을 호출하고
            // @Observable state 변경을 관찰하여 팝업을 업데이트한다.
            // coordinator가 state를 .recognizing → .translating → .completed/.failed로
            // 변경할 때마다 withObservationTracking 등으로 팝업을 갱신한다.
            coordinator.startProcessing(image: image)

            // coordinator의 state 변화를 관찰하여 팝업 갱신
            // (간소화된 폴링 패턴 — 실제 구현에서는 withObservationTracking 권장)
            while true {
                let state = coordinator.state
                popup.updateState(state, near: rect, on: currentScreen)

                if case .completed = state { break }
                if case .failed = state { break }
                if case .idle = state { break }  // 취소됨
                try await Task.sleep(for: .milliseconds(50))
            }

        } catch {
            popup.updateState(
                .failed("캡처 오류: \(error.localizedDescription)"),
                near: rect,
                on: currentScreen
            )
        }
    }

    /// ⚠️ H5: 팝업 외부 클릭 시 닫기
    private func installClickOutsideMonitor(for panel: TranslationPopupWindow) {
        removeClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak panel] event in
            guard let panel, panel.isVisible else { return }
            let clickLocation = event.locationInWindow
            if !panel.frame.contains(clickLocation) {
                panel.close()
                self?.removeClickOutsideMonitor()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
```

**Step 2: MenuBarView 업데이트**

`ScreenTranslate/UI/MenuBar/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button("번역하기") {
            AppOrchestrator.shared.startTranslation()
        }
        .keyboardShortcut("T", modifiers: [.control, .shift])

        Divider()

        SettingsLink {
            Text("설정...")
        }

        Divider()

        Button("ScreenTranslate 종료") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

> **변경점**: `SettingsLink`를 사용하여 Settings Scene을 올바르게 열도록 수정. macOS 14+에서 `SettingsLink`가 공식 지원됨.

**Step 3: App 진입점 업데이트 (TranslationBridgeView 삽입)**

`ScreenTranslate/App/ScreenTranslateApp.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translate = Self("translate", default: .init(.t, modifiers: [.control, .shift]))
}

@main
struct ScreenTranslateApp: App {
    @State private var orchestrator = AppOrchestrator.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppOrchestrator.shared.setup()
    }

    var body: some Scene {
        MenuBarExtra("ScreenTranslate", systemImage: "text.viewfinder") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// TranslationBridge를 상주시키기 위한 AppDelegate.
/// MenuBarExtra 콘텐츠는 메뉴가 열릴 때만 생성되므로,
/// TranslationBridge를 별도의 off-screen NSWindow에 호스팅한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bridgeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: TranslationBridgeView())
        window.orderOut(nil)  // 숨김 상태로 유지, 메모리에서 해제하지 않음
        self.bridgeWindow = window
    }
}
```

> **변경점**: `TranslationBridgeView`를 SwiftUI `Window` Scene 대신 `AppDelegate`에서 생성한 전용 상주 `NSWindow`에 호스팅한다. `MenuBarExtra` 콘텐츠는 메뉴가 닫히면 파괴되므로, 이 방식으로 `.translationTask` modifier가 앱 전체 생명주기 동안 항상 활성 상태를 유지한다.

**Step 4: 빌드 및 수동 동작 확인**

```
Xcode → Product → Run (Cmd+R)
```

확인 목록:
- [ ] 메뉴바에 `text.viewfinder` 아이콘 표시
- [ ] Dock 아이콘 없음
- [ ] "번역하기" 클릭 시 오버레이 표시
- [ ] 드래그로 영역 선택 후 로딩 → 번역 결과 팝업 표시
- [ ] 복사 버튼 동작 + "복사됨" 피드백
- [ ] ESC로 오버레이 취소 동작
- [ ] ESC로 팝업 닫기 동작
- [ ] 설정... 클릭 시 설정 창 열림
- [ ] 설정에서 언어 변경 후 번역 결과 반영
- [ ] Ctrl+Shift+T 단축키 동작
- [ ] 팝업 표시 중 다시 단축키 → 기존 팝업 닫히고 새 선택 시작
- [ ] OCR 실패 시 (빈 영역) 에러 메시지 표시

**Step 5: Commit**

```bash
git add ScreenTranslate/App/ ScreenTranslate/UI/MenuBar/
git commit -m "feat: wire AppOrchestrator, MenuBarView, TranslationBridge, and full flow"
```
