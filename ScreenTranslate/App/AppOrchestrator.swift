import AppKit
import CoreGraphics
import KeyboardShortcuts
import Observation
import SwiftData
import SwiftUI

/// UI 생명주기를 관리하는 싱글턴.
/// 오버레이/팝업 윈도우 표시/숨김, 권한 확인, 사용자 인터랙션 처리.
/// 데이터 파이프라인(캡처->OCR->번역)은 TranslationCoordinator에 위임한다.
@Observable
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

    /// 폴링 루프를 실행하는 Task — 새 번역 시작 시 취소한다.
    private var processingTask: Task<Void, any Error>?

    /// C2: stored 프로퍼티로 소유. computed 프로퍼티로 만들면 매번 새 인스턴스가
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
                historyManager.recordSuccess(
                    sourceText: result.sourceText,
                    translatedText: result.translatedText,
                    sourceLanguageCode: result.sourceLanguage?.minimalIdentifier,
                    targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                )
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
                .failed("캡처 오류: \(error.localizedDescription)"),
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

    // MARK: - 히스토리 윈도우

    private var historyWindow: NSWindow?

    func showHistory() {
        if let existing = historyWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "번역 히스토리"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: HistoryView(historyManager: historyManager)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.historyWindow = window
    }
}
