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
        isReleasedWhenClosed = false  // ARC 환경에서 close() 시 이중 해제 방지
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true  // 팝업 드래그 이동 허용
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // 앱 전환 시에도 표시

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification, object: self
        )
    }

    /// H1: NSHostingView를 재사용하여 rootView만 교체한다.
    /// 매번 새 NSHostingView를 생성하면 뷰 트리가 처음부터 재구성되어 깜빡임이 발생한다.
    private var hostingView: NSHostingView<TranslationPopupView>?

    /// 현재 표시 중인 선택 영역과 스크린 — 원문 토글 리사이즈에 사용
    private var lastSelectionRect: CGRect = .zero
    private var lastScreen: NSScreen?

    /// 현재 상태 — 원문 토글 시 크기 재계산에 사용
    private var currentState: TranslationCoordinator.State = .idle
    private var isShowingOriginal = false

    /// 자동 복사 여부 — 팝업에 전달
    var autoCopied = false

    /// 사용자가 팝업을 드래그했는지 여부 — 원문 토글 시 위치 결정에 사용
    private var userDidDrag = false
    private var isUpdatingPosition = false

    /// 사용자가 리사이즈했는지 여부 — 자동 크기 계산 스킵에 사용
    var userDidResize = false

    // MARK: - 리사이즈 제한 상수

    let minResizeWidth: CGFloat = 280
    let maxResizeWidth: CGFloat = 800
    let minResizeHeight: CGFloat = 100
    let maxResizeHeight: CGFloat = 800

    // MARK: - 크기 계산 상수

    private let contentPaddingTotal: CGFloat = 32   // 좌우 패딩 16×2
    private let buttonRowHeight: CGFloat = 28       // 복사/닫기 버튼 행
    private let vStackSpacing: CGFloat = 24         // VStack spacing(12+8) + 여유(4)
    private let contentOverhead: CGFloat = 84       // contentPaddingTotal + buttonRowHeight + vStackSpacing
    private let originalTextHeader: CGFloat = 30    // 원문 헤더 + 구분선
    private let maxTranslatedHeight: CGFloat = 300  // 번역문 최대 높이 (fontScale 적용 전)
    private let maxOriginalHeight: CGFloat = 200    // 원문 최대 높이 (fontScale 적용 전)
    private let maxTotalHeight: CGFloat = 600       // 팝업 전체 최대 높이

    /// Wrapper container — NSHostingView와 ResizeGripView를 분리
    private var containerView: NSView?
    private var resizeGripView: ResizeGripView?

    private var shouldAnimate: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 최초 표시용 — 윈도우 위치를 설정하고 표시한다.
    func show(state: TranslationCoordinator.State, near selectionRect: CGRect, on screen: NSScreen? = nil) {
        currentState = state
        isShowingOriginal = false
        userDidDrag = false
        userDidResize = false
        autoCopied = false
        lastSelectionRect = selectionRect
        lastScreen = screen

        let popupView = makePopupView(state: state)
        let size = calculateSize(for: state, showingOriginal: false)

        if let existing = hostingView {
            existing.rootView = popupView
        } else {
            let hv = NSHostingView(rootView: popupView)
            hv.sizingOptions = []  // SwiftUI가 윈도우 크기에 개입하지 않도록 차단

            // Wrapper container: NSHostingView + ResizeGripView를 분리
            // frame-based 레이아웃으로 intrinsicContentSize 경합 방지
            let container = NSView(frame: CGRect(origin: .zero, size: size))
            hv.frame = container.bounds
            hv.autoresizingMask = [.width, .height]
            container.addSubview(hv)

            contentView = container
            containerView = container
            hostingView = hv
        }

        // 위치+크기를 원자적으로 설정 (setFrameOrigin + setContentSize 분리 호출 금지)
        let origin = calculateOrigin(near: selectionRect, popupSize: size, on: screen)
        isUpdatingPosition = true
        setFrame(NSRect(origin: origin, size: size), display: true)
        isUpdatingPosition = false
        makeKeyAndOrderFront(nil)
        installResizeGrip()
    }

    /// H1: 상태만 업데이트 — NSHostingView.rootView 교체로 깜빡임 없이 갱신
    /// 상단-좌측 앵커 고정: 최초 show() 위치를 유지하고 아래/우측으로만 확장한다.
    func updateState(_ state: TranslationCoordinator.State, near selectionRect: CGRect, on screen: NSScreen? = nil) {
        currentState = state
        lastSelectionRect = selectionRect
        lastScreen = screen

        let popupView = makePopupView(state: state)

        if let existing = hostingView {
            existing.rootView = popupView
        } else {
            show(state: state, near: selectionRect, on: screen)
            return
        }

        // 사용자가 리사이즈했으면 크기 변경 없이 뷰만 업데이트
        if userDidResize { return }

        // 상단-좌측 고정: 현재 top-left 기준으로 크기만 변경
        var newSize = calculateSize(for: state, showingOriginal: isShowingOriginal)

        // 크기 변화 없으면 프레임 업데이트 스킵 (폴링에 의한 중복 애니메이션 방지)
        if abs(newSize.width - frame.width) < 1 && abs(newSize.height - frame.height) < 1 { return }

        // 상단 y좌표 (AppKit 기준)
        let currentTopY = frame.origin.y + frame.height
        var origin = frame.origin
        let heightDiff = newSize.height - frame.height
        origin.y -= heightDiff  // AppKit 좌하단 원점 → y를 줄여야 상단 고정

        // 화면 경계 클램핑
        let targetScreen = screen ?? lastScreen ?? NSScreen.main!
        clampToScreen(origin: &origin, size: &newSize, screen: targetScreen)

        animateFrame(to: NSRect(origin: origin, size: newSize))
    }

    private func makePopupView(state: TranslationCoordinator.State) -> TranslationPopupView {
        TranslationPopupView(
            state: state,
            onCopy: { text in
                Clipboard.copy(text)
            },
            onClose: { [weak self] in
                self?.close()
            },
            onToggleOriginal: { [weak self] showing in
                self?.handleToggleOriginal(showing)
            },
            autoCopied: autoCopied,
            onOpenSettings: {
                AppOrchestrator.shared.showSettings()
            }
        )
    }

    /// 원문 보기 토글 시 윈도우 크기를 동적으로 재조정한다.
    private func handleToggleOriginal(_ showing: Bool) {
        isShowingOriginal = showing

        if userDidResize {
            // 현재 폭 유지, 높이는 원문 추가/제거분만 반영
            let currentWidth = self.frame.width
            let autoSize = calculateSize(for: currentState, showingOriginal: showing)
            let prevAutoSize = calculateSize(for: currentState, showingOriginal: !showing)
            let heightDiff = autoSize.height - prevAutoSize.height
            let newHeight = max(minResizeHeight, self.frame.height + heightDiff)
            let newSize = NSSize(width: currentWidth, height: newHeight)

            // 좌상단 고정 위치 조정
            let currentTopY = self.frame.origin.y + self.frame.height
            var origin = self.frame.origin
            origin.y -= heightDiff

            // 화면 경계 클램핑
            let screen = lastScreen ?? NSScreen.main!
            var adjustedSize = newSize
            clampToScreen(origin: &origin, size: &adjustedSize, screen: screen)

            animateFrame(to: NSRect(origin: origin, size: adjustedSize))
            return
        }

        var newSize = calculateSize(for: currentState, showingOriginal: showing)

        var newOrigin: NSPoint
        if userDidDrag {
            // 현재 위치 기준으로 높이만 변경 (상단 고정, 아래로 확장)
            let heightDiff = newSize.height - self.frame.height
            newOrigin = self.frame.origin
            newOrigin.y -= heightDiff

            // 화면 경계 클램핑
            let screen = lastScreen ?? NSScreen.main!
            clampToScreen(origin: &newOrigin, size: &newSize, screen: screen)
        } else {
            newOrigin = calculateOrigin(near: lastSelectionRect, popupSize: newSize, on: lastScreen)
        }

        animateFrame(to: NSRect(origin: newOrigin, size: newSize))
    }

    // MARK: - 리사이즈 그립

    /// ResizeGripView를 container에 설치한다.
    private func installResizeGrip() {
        resizeGripView?.removeFromSuperview()

        guard let container = containerView else { return }
        let gripSize: CGFloat = 16
        let grip = ResizeGripView()
        // frame-based: 우하단 고정, 컨테이너 리사이즈 시 자동 추적
        grip.frame = CGRect(
            x: container.bounds.width - gripSize,
            y: 0,
            width: gripSize,
            height: gripSize
        )
        grip.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(grip)

        resizeGripView = grip
    }

    // MARK: - 애니메이션 + 클램핑 헬퍼

    /// 좌상단 고정 기준으로 프레임을 애니메이션 변경한다.
    private func animateFrame(to newFrame: NSRect) {
        isUpdatingPosition = true
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }, completionHandler: { [weak self] in
                self?.isUpdatingPosition = false
            })
        } else {
            setFrame(newFrame, display: true)
            isUpdatingPosition = false
        }
    }

    /// 주어진 origin과 size를 화면 경계 내로 보정한다.
    /// 좌상단(AppKit의 top = origin.y + height) 기준 고정.
    private func clampToScreen(origin: inout NSPoint, size: inout NSSize, screen: NSScreen) {
        let currentTopY = origin.y + size.height
        let gap: CGFloat = 8

        // 하단 넘침 → 높이 축소
        if origin.y < screen.frame.minY + gap {
            let maxHeight = currentTopY - (screen.frame.minY + gap)
            size.height = max(minResizeHeight, maxHeight)
            origin.y = currentTopY - size.height
        }

        // 우측 넘침
        if origin.x + size.width > screen.frame.maxX - gap {
            origin.x = screen.frame.maxX - size.width - gap
        }

        // 좌측 넘침
        origin.x = max(origin.x, screen.frame.minX + gap)
    }

    // MARK: - 동적 크기 계산

    private func calculateSize(for state: TranslationCoordinator.State, showingOriginal: Bool) -> NSSize {
        let fontScale = AppSettings.shared.popupFontSize / 13.0
        // 설정에 따라 캡처 영역 너비 매칭 또는 글자 수 기반 동적 너비 사용
        let baseWidth: CGFloat
        if AppSettings.shared.matchPopupWidthToSelection {
            let selectionWidth = lastSelectionRect.width
            baseWidth = selectionWidth > 0
                ? min(max(selectionWidth, 280), 800)
                : 320
        } else {
            // 글자 수 기반 동적 너비 (이전 방식)
            if case .completed(let result) = state {
                let textLength = result.translatedText.count
                baseWidth = textLength > 200 ? 480 : (textLength > 100 ? 400 : 320)
            } else {
                baseWidth = 320
            }
        }

        switch state {
        case .idle, .recognizing, .translating:
            return NSSize(width: baseWidth, height: minResizeHeight * fontScale)
        case .completed(let result):
            // 높이: 확정된 폭에서 정확한 측정
            let translatedHeight = measureTextHeight(result.translatedText, width: baseWidth)
            var contentHeight = min(translatedHeight, maxTranslatedHeight * fontScale) + contentOverhead

            if showingOriginal {
                let sourceHeight = measureTextHeight(result.sourceText, width: baseWidth)
                contentHeight += min(sourceHeight, maxOriginalHeight * fontScale) + originalTextHeader
            }

            let height = min(max(contentHeight, minResizeHeight * fontScale), maxTotalHeight)
            return NSSize(width: baseWidth, height: height)
        case .failed(let message):
            let height: CGFloat = (message == L10n.autoDetectFailedMessage)
                ? 220 * fontScale
                : 180 * fontScale
            return NSSize(width: baseWidth, height: height)
        }
    }

    /// NSAttributedString 기반 텍스트 높이 측정 — 폰트 메트릭으로 정확한 높이 계산.
    private func measureTextHeight(_ text: String, width: CGFloat) -> CGFloat {
        let font = FontManager.shared.font(size: AppSettings.shared.popupFontSize)
        let rect = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(
                with: CGSize(width: width - contentPaddingTotal, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        return ceil(rect.height)
    }

    // MARK: - 좌표 계산

    /// H2: 좌표 변환 — SwiftUI 좌상단 원점(윈도우-로컬) -> AppKit 좌하단 원점(스크린-글로벌)
    /// 오버레이가 전체 화면이므로 윈도우-로컬 == 스크린-로컬(좌상단)이다.
    /// AppKit의 NSWindow.setFrameOrigin은 좌하단 원점을 기대하므로 Y축 변환이 필요하다.
    private func calculateOrigin(near selectionRect: CGRect, popupSize: NSSize, on screen: NSScreen?) -> NSPoint {
        let targetScreen = screen ?? NSScreen.main!
        let screenFrame = targetScreen.frame
        let popupWidth = popupSize.width
        let popupHeight = popupSize.height
        let gap: CGFloat = 8

        // SwiftUI 좌상단 -> AppKit 좌하단 변환
        let appKitX = screenFrame.origin.x + selectionRect.origin.x
        let appKitSelectionBottom = screenFrame.maxY - selectionRect.maxY

        // 기본 위치: 선택 영역 하단 8pt 아래
        var origin = CGPoint(
            x: appKitX,
            y: appKitSelectionBottom - popupHeight - gap
        )

        // 하단이 화면 밖 -> 선택 영역 상단으로
        if origin.y < screenFrame.minY {
            let appKitSelectionTop = screenFrame.maxY - selectionRect.minY
            origin.y = appKitSelectionTop + gap
        }

        // 오른쪽이 화면 밖 -> 왼쪽으로 보정
        if origin.x + popupWidth > screenFrame.maxX {
            origin.x = screenFrame.maxX - popupWidth - gap
        }

        // 왼쪽이 화면 밖 -> 최소 gap 유지
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + gap
        }

        return origin
    }

    @objc private func windowDidMove(_ notification: Notification) {
        if !isUpdatingPosition {
            userDidDrag = true
        }
    }

    // MARK: - 앱 activate 시 보조 윈도우 보호

    override func close() {
        super.close()
        // super.close() 후 macOS가 설정/About 등을 key window로 선택하여
        // 앞으로 올라올 수 있다. 다음 run loop에서 orderBack하여 되돌린다.
        // (동기 orderBack은 super.close() 후 macOS 자동 선택에 의해 무효화됨)
        DispatchQueue.main.async {
            NSApp.orderBackAuxiliaryWindows()
        }
    }

    override func becomeKey() {
        super.becomeKey()
        // 팝업이 key window가 되면 앱이 activate되어 보조 윈도우(설정, About 등)가
        // 다른 앱 위로 올라오는 것을 방지한다.
        NSApp.orderBackAuxiliaryWindows(excluding: self)
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - ResizeGripView

/// 우하단 리사이즈 그립 — mouseDownCanMoveWindow = false로
/// isMovableByWindowBackground와의 충돌을 방지한다.
private final class ResizeGripView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    private var resizeStartPoint: NSPoint = .zero
    private var resizeStartSize: NSSize = .zero

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        resizeStartPoint = NSEvent.mouseLocation
        resizeStartSize = window.frame.size
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window as? TranslationPopupWindow else { return }
        let current = NSEvent.mouseLocation
        let deltaX = current.x - resizeStartPoint.x
        let deltaY = resizeStartPoint.y - current.y  // 아래로 드래그 = 높이 증가

        let newWidth = max(window.minResizeWidth, min(resizeStartSize.width + deltaX, window.maxResizeWidth))
        let newHeight = max(window.minResizeHeight, min(resizeStartSize.height + deltaY, window.maxResizeHeight))

        // 좌상단 고정 리사이즈 (AppKit 좌하단 원점이므로 origin.y 조정)
        var newFrame = window.frame
        let heightDiff = newHeight - newFrame.height
        newFrame.size = NSSize(width: newWidth, height: newHeight)
        newFrame.origin.y -= heightDiff

        // 화면 경계 클램핑
        if let screen = window.screen {
            newFrame.origin.y = max(newFrame.origin.y, screen.frame.minY + 8)
            if newFrame.origin.x + newFrame.width > screen.frame.maxX - 8 {
                newFrame.size.width = screen.frame.maxX - 8 - newFrame.origin.x
            }
        }

        window.setFrame(newFrame, display: true)
        window.userDidResize = true
    }

    override func mouseUp(with event: NSEvent) {
        // 드래그 종료
    }
}
