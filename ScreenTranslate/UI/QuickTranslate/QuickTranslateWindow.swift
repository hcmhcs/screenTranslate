import AppKit
import SwiftUI
import TelemetryDeck

final class QuickTranslateWindow: NSPanel {
    /// 패널의 상태와 동작. 별도 TranslationCoordinator를 소유해 OCR/드래그 번역과 독립적으로 동작한다.
    /// QuickTranslate는 OCR을 사용하지 않지만, TranslationCoordinator가
    /// ocrProvider를 required param으로 받으므로 dummy로 주입한다.
    let model: QuickTranslateModel

    var coordinator: TranslationCoordinator { model.coordinator }

    // MARK: - 크기 상수

    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 320

    private var keyMonitor: Any?

    init() {
        let coordinator = TranslationCoordinator(
            ocrProvider: VisionOCRProvider(),
            translationProvider: TranslationProviderFactory.make(
                name: AppSettings.shared.translationProviderName
            ),
            targetLanguage: AppSettings.shared.targetLanguage
        )
        self.model = QuickTranslateModel(
            coordinator: coordinator,
            historyManager: AppOrchestrator.shared.historyManager,
            sourceLanguageCode: AppSettings.shared.sourceLanguageCode,
            targetLanguageCode: AppSettings.shared.targetLanguageCode,
            autoCopyEnabled: { AppSettings.shared.autoCopyToClipboard },
            copyToClipboard: { Clipboard.copy($0) },
            telemetry: { engine in
                TelemetryDeck.signal("quickTranslateCompleted", parameters: ["engine": engine])
            }
        )

        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false  // ARC 환경에서 close() 시 이중 해제 방지
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false  // 텍스트 입력 필수 — TranslationPopupWindow과 다름
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private var hostingView: NSHostingView<QuickTranslateView>?

    /// 패널 표시 — 화면 상단 중앙에 위치
    func showPanel() {
        let panelSize = NSSize(width: Self.panelWidth, height: Self.panelHeight)

        if hostingView == nil {
            let view = QuickTranslateView(model: model)
            let hv = NSHostingView(rootView: view)
            hv.sizingOptions = []
            hv.frame = CGRect(origin: .zero, size: panelSize)
            hv.autoresizingMask = [.width, .height]
            contentView = hv
            hostingView = hv
        }

        let origin = calculateCenterTopOrigin(size: panelSize)
        setFrame(NSRect(origin: origin, size: panelSize), display: true)
        makeKeyAndOrderFront(nil)
        NSApp.activate()  // 메뉴바 앱은 기본적으로 active 아님 — 키 입력 수신 필수
        installKeyMonitor()
    }

    /// 패널 숨기기 — 입력·결과를 비운다 (언어 선택은 모델에 남아 다음에 열 때 유지).
    /// hostingView는 파괴해 다음 showPanel()에서 onAppear가 다시 실행되어 입력창에 포커스가 간다.
    func hidePanel() {
        removeKeyMonitor()
        orderOut(nil)
        model.resetForNewSession()
        hostingView = nil
        contentView = nil
        DispatchQueue.main.async {
            NSApp.orderBackAuxiliaryWindows()
        }
    }

    /// 번역 엔진 변경 시 provider 갱신
    func updateTranslationProvider() {
        let provider = TranslationProviderFactory.make(
            name: AppSettings.shared.translationProviderName
        )
        coordinator.updateProvider(provider)
    }

    // MARK: - 키 이벤트 처리

    /// ESC 키 → 패널 닫기.
    /// NSPanel 레벨에서 처리하여 TextEditor가 ESC를 소비하는 것을 방지한다.
    override func cancelOperation(_ sender: Any?) {
        hidePanel()
    }

    /// 키보드 이벤트 모니터 설치 — Enter(번역), Cmd+Shift+C(복사), Cmd+/(스왑)
    /// flags 비교에 `.contains()` 패턴을 사용하여 .function, .capsLock 등
    /// 추가 플래그가 있어도 안정적으로 동작한다.
    /// 모델을 직접 호출하므로 뷰가 keyWindow를 찾아 콜백을 꽂던 타이밍 문제가 없다.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCmd = flags.contains(.command)
            let hasShift = flags.contains(.shift)
            let hasOption = flags.contains(.option)
            let hasControl = flags.contains(.control)

            // Enter → 번역 실행 (modifier 키 없을 때만)
            // Shift+Enter → 줄바꿈 (이벤트 통과)
            if event.keyCode == 36 {  // 36 = Return
                if hasShift { return event }  // Shift+Enter → 줄바꿈
                if !hasCmd && !hasOption && !hasControl {
                    self.model.translate()
                    return nil  // 이벤트 소비
                }
                return event
            }

            // Cmd+Shift+C → 결과 복사 (keyCode 8 = C키, 입력기 무관)
            if hasCmd && hasShift && !hasOption && !hasControl
                && event.keyCode == 8 {
                self.model.copyResult()
                return nil
            }

            // Cmd+/ → 언어 스왑 (keyCode 44 또는 문자 "/" 이중 매칭)
            if hasCmd && !hasShift && !hasOption && !hasControl
                && (event.keyCode == 44 || event.charactersIgnoringModifiers == "/") {
                self.model.swapLanguages()
                return nil
            }

            return event  // 나머지 이벤트 통과
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    override var canBecomeKey: Bool { true }

    /// 팝업이 key window가 되면 보조 윈도우(설정, About 등)가
    /// 다른 앱 위로 올라오는 것을 방지한다.
    override func becomeKey() {
        super.becomeKey()
        NSApp.activate()  // 앱 전환 후 복귀 시 local monitor가 이벤트를 받을 수 있도록
        NSApp.orderBackAuxiliaryWindows(excluding: self)
    }

    override func close() {
        removeKeyMonitor()
        model.resetForNewSession()
        super.close()
        DispatchQueue.main.async {
            NSApp.orderBackAuxiliaryWindows()
        }
    }

    // MARK: - 좌표 계산

    /// 메뉴바 아이콘 바로 아래에 패널을 배치한다.
    /// NSStatusBarWindow에서 아이콘의 x 좌표를 추출하여 패널 중앙을 맞추고,
    /// 찾지 못하면 화면 중앙으로 fallback한다.
    private func calculateCenterTopOrigin(size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return .zero
        }
        let screenFrame = screen.visibleFrame
        let gap: CGFloat = 8

        // 메뉴바 아이콘의 x 중앙 좌표 추출 시도
        let statusBarMidX = NSApp.windows
            .first { String(describing: type(of: $0)).contains("NSStatusBarWindow") }?
            .frame.midX

        let x: CGFloat
        if let midX = statusBarMidX {
            // 패널 중앙을 아이콘 중앙에 맞추되, 화면 밖으로 나가지 않도록 클램핑
            x = min(max(midX - size.width / 2, screenFrame.minX + gap),
                    screenFrame.maxX - size.width - gap)
        } else {
            // Fallback: 화면 중앙
            x = screenFrame.midX - size.width / 2
        }

        // visibleFrame.maxY = 메뉴바 바로 아래 지점
        let y = screenFrame.maxY - size.height - gap
        return NSPoint(x: x, y: max(y, screenFrame.minY))
    }
}
