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

    /// SwiftData 컨테이너 — 히스토리 영구 저장.
    /// 스키마 마이그레이션 실패 시 기존 데이터를 삭제하고 재생성한다.
    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: TranslationRecord.self)
        } catch {
            // DB 손상/마이그레이션 실패 시 기존 데이터 삭제 후 재시도
            // SwiftData는 default.store + WAL/SHM 파일을 함께 사용하므로 모두 삭제
            let storeURL = URL.applicationSupportDirectory
                .appending(path: "default.store")
            for suffix in ["", "-shm", "-wal"] {
                let fileURL = URL(fileURLWithPath: storeURL.path() + suffix)
                try? FileManager.default.removeItem(at: fileURL)
            }
            do {
                return try ModelContainer(for: TranslationRecord.self)
            } catch {
                // 최후 수단: 인메모리 컨테이너 (히스토리 미저장)
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try! ModelContainer(for: TranslationRecord.self, configurations: config)
            }
        }
    }()

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

        // 드래그 번역: 커스텀 단축키 등록 + Cmd+C+C 글로벌 모니터 설치 (항상)
        // 모니터는 콜백 내부에서 모드를 확인하여 동작 여부를 결정한다.
        if AppSettings.shared.dragTranslateMode == "doubleCopy" {
            KeyboardShortcuts.disable(.dragTranslate)
        } else {
            KeyboardShortcuts.onKeyUp(for: .dragTranslate) { [weak self] in
                Task { @MainActor in
                    self?.startDragTranslation()
                }
            }
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

    func startTranslation() {
        // 오버레이가 이미 표시 중이면 무시 (중복 호출 방지)
        guard overlayWindow == nil else { return }

        cancelCurrentWork()

        // 권한 확인
        Task {
            let hasPermission = await ScreenCapturer.checkPermission()
            guard hasPermission else {
                PermissionGuard.requestScreenRecordingPermission()
                return
            }

            // 현재 마우스 위치의 디스플레이 감지
            let mouseLocation = NSEvent.mouseLocation
            currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

            overlayWindow = SelectionOverlayWindow()
            overlayWindow?.show { [weak self] rect in
                self?.overlayWindow = nil  // 사용 후 해제
                guard let self, let rect else { return }
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
        sourceTextFallback: String?
    ) async throws {
        for await state in coordinator.stateStream {
            try Task.checkCancellation()
            popup.updateState(state, near: rect, on: currentScreen)

            switch state {
            case .completed(let result):
                TelemetryDeck.signal(telemetryEvent, parameters: ["engine": coordinator.translationProvider.name])
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
                return  // 취소됨

            case .recognizing, .translating:
                continue  // 다음 상태 대기
            }
        }
    }

    private func processDragTranslation() async {
        coordinator.sourceLanguage = AppSettings.shared.sourceLanguage
        coordinator.targetLanguage = AppSettings.shared.targetLanguage

        let mouseLocation = NSEvent.mouseLocation
        currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

        guard let selectedText = await TextGrabber.getSelectedText(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let popup = TranslationPopupWindow()
            self.popupWindow = popup
            let cursorRect = cursorScreenRect()
            popup.show(state: .failed(L10n.noSelectedText), near: cursorRect, on: currentScreen)
            installClickOutsideMonitor(for: popup)
            return
        }

        let popup = popupWindow ?? TranslationPopupWindow()
        self.popupWindow = popup
        let cursorRect = cursorScreenRect()

        popup.show(state: .translating, near: cursorRect, on: currentScreen)

        do {
            coordinator.startProcessing(text: selectedText)
            try await observeAndRecord(
                popup: popup,
                rect: cursorRect,
                telemetryEvent: "dragTranslationCompleted",
                sourceTextFallback: selectedText
            )
        } catch is CancellationError {
            // 취소 시 조용히 종료
        } catch {
            popup.updateState(
                .failed(error.localizedDescription),
                near: cursorRect,
                on: currentScreen
            )
            installClickOutsideMonitor(for: popup)
        }
    }

    /// 마우스 커서 위치를 기반으로 팝업 배치용 가상 rect를 생성한다.
    /// AppKit 좌하단 원점을 SwiftUI 좌상단 원점으로 변환한다.
    private func cursorScreenRect() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = currentScreen ?? NSScreen.main ?? NSScreen.screens.first!
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
    func updateDragTranslateMode() {
        if AppSettings.shared.dragTranslateMode == "doubleCopy" {
            KeyboardShortcuts.disable(.dragTranslate)
        } else {
            KeyboardShortcuts.onKeyUp(for: .dragTranslate) { [weak self] in
                Task { @MainActor in
                    self?.startDragTranslation()
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
    /// Accessibility 권한 불필요 — 클립보드에서 직접 읽는다.
    private func startClipboardTranslation() {
        cancelCurrentWork()

        processingTask = Task { @MainActor in
            await processClipboardTranslation()
        }
    }

    private func processClipboardTranslation() async {
        coordinator.sourceLanguage = AppSettings.shared.sourceLanguage
        coordinator.targetLanguage = AppSettings.shared.targetLanguage

        let mouseLocation = NSEvent.mouseLocation
        currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

        // 클립보드에서 텍스트 읽기
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let popup = TranslationPopupWindow()
            self.popupWindow = popup
            let cursorRect = cursorScreenRect()
            popup.show(state: .failed(L10n.noClipboardText), near: cursorRect, on: currentScreen)
            installClickOutsideMonitor(for: popup)
            return
        }

        let popup = popupWindow ?? TranslationPopupWindow()
        self.popupWindow = popup
        let cursorRect = cursorScreenRect()

        popup.show(state: .translating, near: cursorRect, on: currentScreen)

        do {
            coordinator.startProcessing(text: clipboardText)
            try await observeAndRecord(
                popup: popup,
                rect: cursorRect,
                telemetryEvent: "doubleCopyTranslationCompleted",
                sourceTextFallback: clipboardText
            )
        } catch is CancellationError {
            // 취소 시 조용히 종료
        } catch {
            popup.updateState(
                .failed(error.localizedDescription),
                near: cursorRect,
                on: currentScreen
            )
            installClickOutsideMonitor(for: popup)
        }
    }

    private func processCapture(rect: CGRect) async {
        coordinator.sourceLanguage = AppSettings.shared.sourceLanguage
        coordinator.targetLanguage = AppSettings.shared.targetLanguage

        let popup = popupWindow ?? TranslationPopupWindow()
        self.popupWindow = popup

        popup.show(state: .recognizing, near: rect, on: currentScreen)

        do {
            let image = try await capturer.capture(rect: rect, screen: currentScreen)
            coordinator.startProcessing(image: image, preprocessOCR: AppSettings.shared.ocrTextPreprocessing)
            try await observeAndRecord(
                popup: popup,
                rect: rect,
                telemetryEvent: "translationCompleted",
                sourceTextFallback: nil
            )
        } catch is CancellationError {
            // 취소 시 조용히 종료
        } catch {
            popup.updateState(
                .failed(L10n.captureError(error.localizedDescription)),
                near: rect,
                on: currentScreen
            )
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
        let onboardingView = OnboardingView {
            window.close()
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
        window.title = L10n.settingsMenu.replacingOccurrences(of: "...", with: "")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
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
                    HistoryView(historyManager: historyManager, initialExpandedID: recordID)
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
            rootView: HistoryView(historyManager: historyManager, initialExpandedID: recordID)
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
