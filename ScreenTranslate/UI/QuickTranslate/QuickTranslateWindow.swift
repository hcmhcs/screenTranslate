import AppKit
import SwiftUI

final class QuickTranslateWindow: NSPanel {
    /// 별도 TranslationCoordinator — OCR/드래그 번역과 독립적으로 동작.
    /// QuickTranslate는 OCR을 사용하지 않지만, TranslationCoordinator가
    /// ocrProvider를 required param으로 받으므로 dummy로 주입한다.
    let coordinator: TranslationCoordinator

    // MARK: - 크기 상수

    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 320

    /// Enter 번역 실행 콜백 — SwiftUI 뷰에서 설정
    var onTranslateAction: (() -> Void)?

    /// Cmd+Shift+C 결과 복사 콜백 — SwiftUI 뷰에서 설정
    var onCopyResultAction: (() -> Void)?

    /// Cmd+/ 언어 스왑 콜백 — SwiftUI 뷰에서 설정
    var onSwapAction: (() -> Void)?

    private var keyMonitor: Any?

    init() {
        self.coordinator = TranslationCoordinator(
            ocrProvider: VisionOCRProvider(),
            translationProvider: TranslationProviderFactory.make(
                name: AppSettings.shared.translationProviderName
            ),
            targetLanguage: AppSettings.shared.targetLanguage
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
            let view = QuickTranslateView(coordinator: coordinator)
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

    /// 패널 숨기기 — 상태 초기화.
    /// hostingView를 파괴하여 다음 showPanel()에서 @State가 초기값으로 리셋된다.
    func hidePanel() {
        removeKeyMonitor()
        orderOut(nil)
        coordinator.cancel()
        hostingView = nil
        contentView = nil
        onTranslateAction = nil
        onCopyResultAction = nil
        onSwapAction = nil
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
                    self.onTranslateAction?()
                    return nil  // 이벤트 소비
                }
                return event
            }

            // Cmd+Shift+C → 결과 복사 (keyCode 8 = C키, 입력기 무관)
            if hasCmd && hasShift && !hasOption && !hasControl
                && event.keyCode == 8 {
                self.onCopyResultAction?()
                return nil
            }

            // Cmd+/ → 언어 스왑 (keyCode 44 또는 문자 "/" 이중 매칭)
            if hasCmd && !hasShift && !hasOption && !hasControl
                && (event.keyCode == 44 || event.charactersIgnoringModifiers == "/") {
                self.onSwapAction?()
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
        coordinator.cancel()
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
