import AppKit
import Combine
import CoreGraphics
import KeyboardShortcuts
import Observation
import Sparkle
import SwiftData
import SwiftUI
import TelemetryDeck

/// UI 생명주기를 관리하는 싱글턴.
/// 오버레이/팝업 윈도우 표시/숨김, 권한 확인, 사용자 인터랙션 처리.
/// 데이터 파이프라인(캡처->OCR->번역)은 TranslationCoordinator에 위임한다.
@MainActor @Observable
final class AppOrchestrator {
    static let shared = AppOrchestrator()

    private var overlayWindow: SelectionOverlayWindow?
    private var popupWindow: TranslationPopupWindow?
    private var quickTranslateWindow: QuickTranslateWindow?
    private let capturer = ScreenCapturer()
    private var currentScreen: NSScreen?

    /// SwiftData 컨테이너 — 히스토리 영구 저장 (위치·복구·이전은 HistoryStore 담당, H2)
    let modelContainer: ModelContainer

    /// 스토어를 열 수 없어 인메모리로 동작 중인지 — 히스토리 뷰에 경고를 띄운다
    let historyIsInMemory: Bool

    private init() {
        // 단위 테스트는 앱을 호스트로 실행하므로, 그대로 두면 테스트마다 실제 사용자 히스토리를 열고
        // 이전(migration)까지 수행한다. 테스트 환경에서는 인메모리 스토어만 쓴다.
        if Self.isRunningUnitTests {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            modelContainer = try! ModelContainer(for: TranslationRecord.self, configurations: config)
            historyIsInMemory = true
            return
        }
        HistoryStore.migrateLegacyStoreIfNeeded(from: HistoryStore.legacyStoreURL, to: HistoryStore.defaultStoreURL)
        let result = HistoryStore.makeContainer(at: HistoryStore.defaultStoreURL)
        modelContainer = result.container
        historyIsInMemory = result.isInMemory
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// 번역 히스토리 관리자 — @Observable이 lazy를 지원하지 않으므로 추적 제외
    @ObservationIgnored
    lazy var historyManager = TranslationHistoryManager(modelContainer: modelContainer)

    /// Sparkle 자동 업데이트 컨트롤러
    @ObservationIgnored
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Sparkle 업데이트 확인 가능 여부 — MenuBarView/AboutView에서 버튼 비활성화에 사용
    private(set) var canCheckForUpdates = false

    @ObservationIgnored
    private var updateCancellable: AnyCancellable?

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// 폴링 루프를 실행하는 Task — 새 번역 시작 시 취소한다.
    private var processingTask: Task<Void, any Error>?

    /// C2: stored 프로퍼티로 소유. computed 프로퍼티로 만들면 매번 새 인스턴스가
    /// 생성되어 @Observable 상태 추적이 불가능하고, 진행 중인 Task가 소실된다.
    let coordinator = TranslationCoordinator(
        ocrProvider: VisionOCRProvider(),
        translationProvider: TranslationProviderFactory.make(name: AppSettings.shared.translationProviderName),
        targetLanguage: AppSettings.shared.targetLanguage
    )

    /// 설정에서 번역 엔진이 변경되면 Provider를 교체한다.
    func updateTranslationProvider() {
        let provider = TranslationProviderFactory.make(name: AppSettings.shared.translationProviderName)
        coordinator.updateProvider(provider)
        quickTranslateWindow?.updateTranslationProvider()
    }

    func setup() {
        // 번들 폰트 등록 및 카탈로그 로드
        FontManager.shared.registerBundledFonts()
        FontManager.shared.loadCatalog()
        FontManager.shared.scanInstalledFonts()

        KeyboardShortcuts.onKeyUp(for: .translate) { [weak self] in
            Task { @MainActor in
                self?.startTranslation()
            }
        }

        // 드래그 번역: 단축키 핸들러는 앱 생명주기 동안 한 번만 등록한다 (C3-a).
        // KeyboardShortcuts.onKeyUp은 핸들러를 배열에 append하므로 재등록하면 누적된다.
        // 모드 확인은 콜백 안에서 하고, updateDragTranslateMode는 enable/disable만 한다.
        KeyboardShortcuts.onKeyUp(for: .dragTranslate) { [weak self] in
            Task { @MainActor in
                guard AppSettings.shared.dragTranslateMode != "doubleCopy" else { return }
                self?.startDragTranslation()
            }
        }
        if AppSettings.shared.dragTranslateMode == "doubleCopy" {
            KeyboardShortcuts.disable(.dragTranslate)
        }
        installDoubleCopyMonitor()  // 항상 설치, 콜백에서 모드 확인

        KeyboardShortcuts.onKeyUp(for: .quickTranslate) { [weak self] in
            Task { @MainActor in
                self?.toggleQuickTranslate()
            }
        }

        // Sparkle canCheckForUpdates KVO → @Observable 브리지
        updateCancellable = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    /// 영역 선택이 진행 중인지 — 권한 확인 await 동안에도 true (H1: 단축키 연타로 오버레이 2개 생성 방지)
    private var isSelectingRegion = false

    func startTranslation() {
        // 오버레이가 이미 표시 중이거나 준비 중이면 무시 (중복 호출 방지)
        guard !isSelectingRegion, overlayWindow == nil else { return }
        isSelectingRegion = true

        cancelCurrentWork()

        // 권한 확인
        Task {
            let hasPermission = await ScreenCapturer.checkPermission()
            guard hasPermission else {
                isSelectingRegion = false
                PermissionGuard.requestScreenRecordingPermission()
                return
            }

            // 현재 마우스 위치의 디스플레이 감지
            currentScreen = NSScreen.underMouse

            overlayWindow = SelectionOverlayWindow()
            overlayWindow?.show { [weak self] rect in
                guard let self else { return }
                self.overlayWindow = nil  // 사용 후 해제
                self.isSelectingRegion = false
                guard let rect else { return }
                self.processingTask = Task { @MainActor in
                    await self.processCapture(rect: rect)
                }
            }
        }
    }

    func startDragTranslation() {
        cancelCurrentWork()

        // Accessibility 권한 확인
        guard TextGrabber.isAccessibilityTrusted else {
            TextGrabber.requestAccessibilityPermission()
            PermissionGuard.requestAccessibilityPermission()
            return
        }

        processingTask = Task { @MainActor in
            await processDragTranslation()
        }
    }

    func toggleQuickTranslate() {
        if let existing = quickTranslateWindow, existing.isVisible {
            existing.hidePanel()
            return
        }

        if quickTranslateWindow == nil {
            quickTranslateWindow = QuickTranslateWindow()
        }
        quickTranslateWindow?.showPanel()
    }

    /// 진행 중인 번역 작업을 취소하고 팝업을 닫는다.
    private func cancelCurrentWork() {
        processingTask?.cancel()
        processingTask = nil
        coordinator.cancel()
        removeClickOutsideMonitor()
        popupWindow?.close()
        popupWindow = nil
    }

    /// 번역 상태를 관찰하고 완료 시 히스토리 기록 + 자동복사를 수행한다.
    private func observeAndRecord(
        popup: TranslationPopupWindow,
        rect: CGRect,
        telemetryEvent: String,
        telemetryParameters: [String: String] = [:],
        sourceTextFallback: String?
    ) async throws {
        for await state in coordinator.makeStateStream() {
            try Task.checkCancellation()
            popup.updateState(state, near: rect, on: currentScreen)

            switch state {
            case .completed(let result):
                var params = telemetryParameters
                params["engine"] = coordinator.translationProvider.name
                TelemetryDeck.signal(telemetryEvent, parameters: params)
                historyManager.recordSuccess(
                    sourceText: result.sourceText,
                    translatedText: result.translatedText,
                    sourceLanguageCode: result.sourceLanguage?.minimalIdentifier,
                    targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                )
                if AppSettings.shared.autoCopyToClipboard {
                    Clipboard.copy(result.translatedText)
                    popup.autoCopied = true
                    popup.updateState(state, near: rect, on: currentScreen)
                }
                installClickOutsideMonitor(for: popup)
                return

            case .failed(let message):
                historyManager.recordFailure(
                    sourceText: sourceTextFallback,
                    errorMessage: message,
                    targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                )
                installClickOutsideMonitor(for: popup)
                return

            case .idle:
                // 취소됨 (다른 번역 요청이 이 실행을 밀어낸 경우 포함) — 빈 팝업을 남기지 않는다
                popup.close()
                if popupWindow === popup { popupWindow = nil }
                return

            case .recognizing, .translating:
                continue  // 다음 상태 대기
            }
        }
    }

    /// 팝업을 만들고 닫힘 훅을 연결한다. 팝업이 어떤 경로로든 닫히면 외부 클릭 모니터를 제거한다.
    private func makePopup() -> TranslationPopupWindow {
        let popup = TranslationPopupWindow()
        popup.onDidClose = { [weak self] in
            self?.removeClickOutsideMonitor()
        }
        return popup
    }

    private func processDragTranslation() async {
        currentScreen = NSScreen.underMouse

        guard let selectedText = await TextGrabber.getSelectedText(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFailurePopup(L10n.noSelectedText)
            return
        }
        await runTranslation(.text(selectedText, trigger: "shortcut"))
    }

    /// 마우스 커서 위치를 기반으로 팝업 배치용 가상 rect를 생성한다.
    /// AppKit 좌하단 원점을 SwiftUI 좌상단 원점으로 변환한다.
    private func cursorScreenRect() -> CGRect {
        let mouse = NSEvent.mouseLocation
        guard let screen = currentScreen ?? NSScreen.main ?? NSScreen.screens.first else {
            return CGRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        }
        let swiftUIY = screen.frame.maxY - mouse.y
        let swiftUIX = mouse.x - screen.frame.origin.x
        return CGRect(x: swiftUIX, y: swiftUIY, width: 1, height: 1)
    }

    /// H5: 팝업 외부 클릭 감지용 글로벌 마우스 모니터
    private var clickMonitor: Any?

    /// Cmd+C+C 감지용 글로벌 모니터
    private var doubleCopyMonitor: Any?
    /// 마지막 Cmd+C 시간 — 0.4초 이내 재입력 시 번역 트리거
    private var lastCmdCTime: Date?

    // MARK: - Cmd+C+C 클립보드 번역

    /// 드래그 번역 모드 전환 — 설정에서 변경 시 호출.
    /// 글로벌 모니터는 항상 설치되어 있으므로 KeyboardShortcuts만 전환한다.
    /// doubleCopy 모드는 NSEvent.addGlobalMonitorForEvents(.keyDown)를 사용하므로
    /// Accessibility 권한이 필요하다. 권한이 없으면 안내 팝업을 표시한다.
    func updateDragTranslateMode() {
        if AppSettings.shared.dragTranslateMode == "doubleCopy" {
            KeyboardShortcuts.disable(.dragTranslate)
            // Accessibility 권한 확인 — 글로벌 키보드 모니터에 필요
            if !TextGrabber.isAccessibilityTrusted {
                TextGrabber.requestAccessibilityPermission()
                PermissionGuard.requestAccessibilityPermission()
                reinstallDoubleCopyMonitorWhenTrusted()
            }
        } else {
            // 핸들러는 setup()에서 한 번만 등록했으므로 핫키만 다시 켠다 (C3-a)
            KeyboardShortcuts.enable(.dragTranslate)
        }
    }

    /// M3: 권한 없이 설치된 글로벌 키 모니터는 권한을 나중에 허용해도 이벤트를 받지 못한다.
    /// 최대 3분 동안 2초마다 확인해 권한이 생기면 모니터를 한 번 재설치한다.
    private var trustPollingTask: Task<Void, Never>?

    private func reinstallDoubleCopyMonitorWhenTrusted() {
        trustPollingTask?.cancel()
        trustPollingTask = Task { [weak self] in
            for _ in 0..<90 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                if TextGrabber.isAccessibilityTrusted {
                    self.installDoubleCopyMonitor()
                    self.trustPollingTask = nil
                    return
                }
            }
        }
    }

    /// Cmd+C+C 글로벌 모니터 설치 (앱 생명주기 동안 1회만 호출).
    /// 글로벌 모니터는 다른 앱에서 발생한 Cmd+C도 감지한다.
    /// 콜백 내부에서 dragTranslateMode를 확인하여 doubleCopy 모드일 때만 동작한다.
    /// 모니터를 제거/재설치하면 macOS에서 간헐적으로 이벤트가 전달되지 않는 문제가 있어
    /// 항상 설치된 상태를 유지한다.
    private func installDoubleCopyMonitor() {
        removeDoubleCopyMonitor()
        doubleCopyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // doubleCopy 모드가 아니면 무시
            guard AppSettings.shared.dragTranslateMode == "doubleCopy" else { return }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Cmd+C 감지 — keyCode 8 (C키 물리 위치, 입력기 무관)
            // .contains() 패턴으로 .function, .capsLock, .numericPad 등 추가 플래그 허용
            guard flags.contains(.command),
                  !flags.contains(.shift), !flags.contains(.option), !flags.contains(.control),
                  event.keyCode == 8 else { return }  // 8 = C key

            Task { @MainActor in
                guard let self else { return }
                let now = Date()
                if let last = self.lastCmdCTime, now.timeIntervalSince(last) < 0.4 {
                    // 두 번째 Cmd+C — 번역 실행
                    self.lastCmdCTime = nil
                    self.startClipboardTranslation()
                } else {
                    // 첫 번째 Cmd+C — 시간 기록
                    self.lastCmdCTime = now
                }
            }
        }
    }

    private func removeDoubleCopyMonitor() {
        if let monitor = doubleCopyMonitor {
            NSEvent.removeMonitor(monitor)
            doubleCopyMonitor = nil
        }
        lastCmdCTime = nil
    }

    /// Cmd+C+C로 트리거된 클립보드 텍스트 번역.
    /// 글로벌 모니터 콜백에서 호출되므로 이 시점에서 Accessibility 권한은 이미 있지만,
    /// 방어적으로 한 번 더 확인한다.
    private func startClipboardTranslation() {
        guard TextGrabber.isAccessibilityTrusted else {
            TextGrabber.requestAccessibilityPermission()
            PermissionGuard.requestAccessibilityPermission()
            return
        }

        cancelCurrentWork()

        processingTask = Task { @MainActor in
            await processClipboardTranslation()
        }
    }

    private func processClipboardTranslation() async {
        currentScreen = NSScreen.underMouse

        // 클립보드에서 텍스트 읽기
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFailurePopup(L10n.noClipboardText)
            return
        }
        await runTranslation(.text(clipboardText, trigger: "doubleCopy"))
    }

    private func processCapture(rect: CGRect) async {
        await runTranslation(.capture(rect))
    }

    // MARK: - 번역 실행 (캡처 / 텍스트 공통 경로)

    /// 번역 입력. 캡처는 OCR을 거치고, 텍스트는 바로 번역한다.
    private enum TranslationInput {
        case capture(CGRect)
        /// trigger: 텔레메트리용 ("shortcut" | "doubleCopy")
        case text(String, trigger: String)
    }

    /// 커서 근처에 실패 메시지 팝업을 띄운다 (번역할 텍스트를 얻지 못한 경우).
    private func showFailurePopup(_ message: String) {
        let popup = makePopup()
        popupWindow = popup
        let cursorRect = cursorScreenRect()
        popup.show(state: .failed(message), near: cursorRect, on: currentScreen)
        installClickOutsideMonitor(for: popup)
    }

    /// 캡처·드래그·클립보드 번역의 공통 경로: 팝업 표시 → 파이프라인 시작 → 상태 관찰·기록.
    private func runTranslation(_ input: TranslationInput) async {
        coordinator.sourceLanguage = AppSettings.shared.sourceLanguage
        coordinator.targetLanguage = AppSettings.shared.targetLanguage

        let popup = popupWindow ?? makePopup()
        popupWindow = popup

        let rect: CGRect
        let telemetryEvent: String
        var telemetryParameters: [String: String] = [:]
        let sourceTextFallback: String?
        switch input {
        case .capture(let captureRect):
            rect = captureRect
            telemetryEvent = "translationCompleted"
            sourceTextFallback = nil
            popup.show(state: .recognizing, near: rect, on: currentScreen)
        case .text(let text, let trigger):
            rect = cursorScreenRect()
            telemetryEvent = "dragTranslationCompleted"
            telemetryParameters["trigger"] = trigger
            sourceTextFallback = text
            popup.show(state: .translating, near: rect, on: currentScreen)
        }

        do {
            switch input {
            case .capture(let captureRect):
                let image = try await capturer.capture(rect: captureRect, screen: currentScreen)
                coordinator.startProcessing(image: image, preprocessOCR: AppSettings.shared.ocrTextPreprocessing)
            case .text(let text, _):
                coordinator.startProcessing(text: text)
            }
            try await observeAndRecord(
                popup: popup,
                rect: rect,
                telemetryEvent: telemetryEvent,
                telemetryParameters: telemetryParameters,
                sourceTextFallback: sourceTextFallback
            )
        } catch is CancellationError {
            // 취소 시 조용히 종료
        } catch {
            let message: String
            if case .capture = input {
                message = L10n.captureError(error.localizedDescription)
            } else {
                message = error.localizedDescription
            }
            popup.updateState(.failed(message), near: rect, on: currentScreen)
            installClickOutsideMonitor(for: popup)
        }
    }

    /// H5: 팝업 외부 클릭 시 닫기 — 글로벌 마우스 이벤트 모니터
    /// 글로벌 모니터 콜백은 MainActor 보장이 없으므로 Task로 디스패치한다.
    private func installClickOutsideMonitor(for panel: TranslationPopupWindow) {
        removeClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let panel, panel.isVisible else { return }
                let clickLocation = NSEvent.mouseLocation
                if !panel.frame.contains(clickLocation) {
                    panel.close()
                    self?.removeClickOutsideMonitor()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - 온보딩 윈도우

    private var onboardingWindow: NSWindow?

    func showOnboardingIfNeeded() {
        // 중복 윈도우 방지
        if let existing = onboardingWindow, existing.isVisible { return }

        // 기존 사용자 판별: UserDefaults에 앱 설정 키가 하나라도 있으면 기존 사용자로 간주.
        // (이 키들은 computed property + ?? 기본값이라 사용자가 명시적으로 변경해야만 저장됨)
        let existingUserKeys = [
            "com.screentranslate.targetLanguageCode",
            "com.screentranslate.sourceLanguageCode",
            "com.screentranslate.translationProviderName",
            "com.screentranslate.ocrTextPreprocessing",
        ]
        let isExistingUser = existingUserKeys.contains { UserDefaults.standard.object(forKey: $0) != nil }
        if isExistingUser {
            AppSettings.shared.hasCompletedOnboarding = true
            return
        }

        guard !AppSettings.shared.hasCompletedOnboarding else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenTranslate"
        window.isReleasedWhenClosed = false
        window.center()

        // onComplete: finishOnboarding()이 hasCompletedOnboarding 설정을 담당하고,
        // X 버튼은 OnboardingWindowDelegate가 처리하므로 여기서는 윈도우만 닫는다.
        let onboardingView = OnboardingView { [weak window] in
            window?.close()  // 강한 캡처 시 window → contentView → rootView → 클로저 → window 순환 (M12)
        }
        window.contentView = NSHostingView(rootView: onboardingView)

        // X 버튼으로 닫으면 온보딩 미완료 → 다음 실행 시 재표시
        window.delegate = OnboardingWindowDelegate.shared

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    // MARK: - 설정 윈도우

    private var settingsWindow: NSWindow?

    func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settingsWindowTitle
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: SettingsView())
        window.contentView = hostingView

        // 메뉴바 바로 아래, 화면 중앙에 위치
        if let screen = NSScreen.main {
            let contentSize = hostingView.fittingSize
            let x = screen.visibleFrame.midX - contentSize.width / 2
            let y = screen.visibleFrame.maxY - contentSize.height
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    // MARK: - About 윈도우

    private var aboutWindow: NSWindow?

    func showAbout() {
        if let existing = aboutWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.aboutApp
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.aboutWindow = window
    }

    // MARK: - 히스토리 윈도우

    private var historyWindow: NSWindow?

    func showHistory(expandingRecord recordID: UUID? = nil) {
        if let existing = historyWindow, existing.isVisible {
            // 기존 윈도우가 열려있으면 rootView를 교체하여 initialExpandedID 반영
            if let recordID {
                (existing.contentView as? NSHostingView<HistoryView>)?.rootView =
                    HistoryView(historyManager: historyManager, initialExpandedID: recordID, isInMemory: historyIsInMemory)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.translationHistory
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: HistoryView(historyManager: historyManager, initialExpandedID: recordID, isInMemory: historyIsInMemory)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.historyWindow = window
    }
}

/// 온보딩 윈도우의 X 버튼 클릭 시 — 온보딩 미완료 상태 유지.
/// 다음 앱 실행 시 온보딩이 다시 표시된다.
/// "시작하기" 또는 "나중에 다운로드"로 완료한 경우만 hasCompletedOnboarding = true.
@MainActor
final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        // 의도적으로 비워둠: X 버튼 닫기 시 온보딩 미완료
    }
}
