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
    private let capturer = ScreenCapturer()
    private var currentScreen: NSScreen?

    /// SwiftData 컨테이너 — 히스토리 영구 저장
    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: TranslationRecord.self)
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
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
    }

    func setup() {
        KeyboardShortcuts.onKeyUp(for: .translate) { [weak self] in
            Task { @MainActor in
                self?.startTranslation()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .dragTranslate) { [weak self] in
            Task { @MainActor in
                self?.startDragTranslation()
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

        // H4: 기존 작업 취소 + 팝업 닫기
        processingTask?.cancel()
        processingTask = nil
        coordinator.cancel()
        removeClickOutsideMonitor()
        popupWindow?.close()
        popupWindow = nil

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
        // 기존 작업 취소 + 팝업 닫기
        processingTask?.cancel()
        processingTask = nil
        coordinator.cancel()
        removeClickOutsideMonitor()
        popupWindow?.close()
        popupWindow = nil

        // Accessibility 권한 확인
        guard TextGrabber.isAccessibilityTrusted else {
            PermissionGuard.requestAccessibilityPermission()
            return
        }

        processingTask = Task { @MainActor in
            await processDragTranslation()
        }
    }

    private func processDragTranslation() async {
        // 설정에서 변경된 언어를 반영
        coordinator.sourceLanguage = AppSettings.shared.sourceLanguage
        coordinator.targetLanguage = AppSettings.shared.targetLanguage

        // 마우스 위치 기반 화면 감지
        let mouseLocation = NSEvent.mouseLocation
        currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

        // 선택된 텍스트 가져오기
        guard let selectedText = await TextGrabber.getSelectedText(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let popup = TranslationPopupWindow()
            self.popupWindow = popup
            let cursorRect = cursorScreenRect()
            popup.show(state: .failed(L10n.noSelectedText), near: cursorRect, on: currentScreen)
            installClickOutsideMonitor(for: popup)
            return
        }

        // 팝업 윈도우 생성/재사용
        let popup: TranslationPopupWindow
        if let existing = popupWindow {
            popup = existing
        } else {
            popup = TranslationPopupWindow()
            self.popupWindow = popup
        }

        // 마우스 위치 기준 가상 rect
        let cursorRect = cursorScreenRect()

        // 로딩 상태 표시 (바로 '번역 중...')
        popup.show(state: .translating, near: cursorRect, on: currentScreen)

        do {
            // OCR 스킵 — 텍스트 직접 번역
            coordinator.startProcessing(text: selectedText)

            while true {
                try Task.checkCancellation()
                let state = coordinator.state
                popup.updateState(state, near: cursorRect, on: currentScreen)

                if case .completed = state { break }
                if case .failed = state { break }
                if case .idle = state { break }
                try await Task.sleep(for: .milliseconds(50))
            }

            // 히스토리 기록
            let finalState = coordinator.state
            if case .completed(let result) = finalState {
                TelemetryDeck.signal("dragTranslationCompleted", parameters: ["engine": coordinator.translationProvider.name])
                historyManager.recordSuccess(
                    sourceText: result.sourceText,
                    translatedText: result.translatedText,
                    sourceLanguageCode: result.sourceLanguage?.minimalIdentifier,
                    targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                )
                if AppSettings.shared.autoCopyToClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.translatedText, forType: .string)
                    popup.autoCopied = true
                    popup.updateState(finalState, near: cursorRect, on: currentScreen)
                }
            } else if case .failed(let message) = finalState {
                historyManager.recordFailure(
                    sourceText: selectedText,
                    errorMessage: message,
                    targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                )
            }

            installClickOutsideMonitor(for: popup)

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
        let screen = currentScreen ?? NSScreen.main!
        let swiftUIY = screen.frame.maxY - mouse.y
        let swiftUIX = mouse.x - screen.frame.origin.x
        return CGRect(x: swiftUIX, y: swiftUIY, width: 1, height: 1)
    }

    /// H5: 팝업 외부 클릭 감지용 글로벌 마우스 모니터
    private var clickMonitor: Any?

    private func processCapture(rect: CGRect) async {
        // 설정에서 변경된 언어를 반영
        coordinator.sourceLanguage = AppSettings.shared.sourceLanguage
        coordinator.targetLanguage = AppSettings.shared.targetLanguage

        // H1: 팝업 윈도우를 재사용하여 NSHostingView 재생성으로 인한 깜빡임 방지
        let popup: TranslationPopupWindow
        if let existing = popupWindow {
            popup = existing
        } else {
            popup = TranslationPopupWindow()
            self.popupWindow = popup
        }

        // 로딩 상태 표시
        popup.show(state: .recognizing, near: rect, on: currentScreen)

        // H5: 진행 중에는 외부 클릭으로 닫히지 않도록,
        // 완료/실패 후에만 클릭 모니터를 설치한다.

        do {
            let image = try await capturer.capture(rect: rect, screen: currentScreen)

            // C4/H4: coordinator의 startProcessing()을 호출하고
            // state 변경을 폴링하여 팝업을 업데이트한다.
            coordinator.startProcessing(image: image)

            while true {
                try Task.checkCancellation()  // 외부 취소 허용
                let state = coordinator.state
                popup.updateState(state, near: rect, on: currentScreen)

                if case .completed = state { break }
                if case .failed = state { break }
                if case .idle = state { break }  // 취소됨
                try await Task.sleep(for: .milliseconds(50))
            }

            // 히스토리 기록
            let finalState = coordinator.state
            if case .completed(let result) = finalState {
                TelemetryDeck.signal("translationCompleted", parameters: ["engine": coordinator.translationProvider.name])
                historyManager.recordSuccess(
                    sourceText: result.sourceText,
                    translatedText: result.translatedText,
                    sourceLanguageCode: result.sourceLanguage?.minimalIdentifier,
                    targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                )
                if AppSettings.shared.autoCopyToClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.translatedText, forType: .string)
                    popup.autoCopied = true
                    popup.updateState(finalState, near: rect, on: currentScreen)
                }
            } else if case .failed(let message) = finalState {
                historyManager.recordFailure(
                    sourceText: nil,
                    errorMessage: message,
                    targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                )
            }

            // H5: 번역 완료/실패 후 외부 클릭 시 닫기 모니터 설치
            installClickOutsideMonitor(for: popup)

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
