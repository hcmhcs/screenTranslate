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
    }

    /// H1: NSHostingView를 재사용하여 rootView만 교체한다.
    /// 매번 새 NSHostingView를 생성하면 뷰 트리가 처음부터 재구성되어 깜빡임이 발생한다.
    private var hostingView: NSHostingView<TranslationPopupView>?

    /// 최초 표시용 — 윈도우 위치를 설정하고 표시한다.
    func show(state: TranslationCoordinator.State, near selectionRect: CGRect, on screen: NSScreen? = nil) {
        let popupView = makePopupView(state: state)
        let size = calculateSize(for: state)

        if let existing = hostingView {
            existing.rootView = popupView
        } else {
            let hv = NSHostingView(rootView: popupView)
            hv.frame = CGRect(origin: .zero, size: size)
            contentView = hv
            hostingView = hv
        }

        let origin = calculateOrigin(near: selectionRect, popupSize: size, on: screen)
        setFrameOrigin(origin)
        setContentSize(size)
        makeKeyAndOrderFront(nil)
    }

    /// H1: 상태만 업데이트 — NSHostingView.rootView 교체로 깜빡임 없이 갱신
    func updateState(_ state: TranslationCoordinator.State, near selectionRect: CGRect, on screen: NSScreen? = nil) {
        let popupView = makePopupView(state: state)

        if let existing = hostingView {
            existing.rootView = popupView
        } else {
            show(state: state, near: selectionRect, on: screen)
            return
        }

        // 동적 크기 변경 + 애니메이션
        let newSize = calculateSize(for: state)
        let newOrigin = calculateOrigin(near: selectionRect, popupSize: newSize, on: screen)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(
                NSRect(origin: newOrigin, size: newSize),
                display: true
            )
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

    // MARK: - 동적 크기 계산

    private func calculateSize(for state: TranslationCoordinator.State) -> NSSize {
        switch state {
        case .idle:
            return NSSize(width: 320, height: 120)
        case .recognizing, .translating:
            return NSSize(width: 320, height: 120)
        case .completed(let result):
            let translatedHeight = estimateTextHeight(result.translatedText)
            // 원문 보기 토글 시를 위해 sourceText 높이도 고려하여 여유 확보
            let sourceHeight = estimateTextHeight(result.sourceText)
            let maxTextHeight = max(translatedHeight, translatedHeight + sourceHeight * 0.5)
            let contentHeight = maxTextHeight + 100  // 패딩 + 버튼 + 토글 + 구분선
            let height = min(max(contentHeight, 180), 500)
            let width: CGFloat = maxTextHeight > 200 ? 480 : (maxTextHeight > 100 ? 400 : 320)
            return NSSize(width: width, height: height)
        case .failed:
            return NSSize(width: 320, height: 180)
        }
    }

    /// 텍스트 높이를 추정한다 (줄 수 × 줄 높이).
    private func estimateTextHeight(_ text: String) -> CGFloat {
        let lineHeight: CGFloat = 20
        let charsPerLine: CGFloat = 35  // 평균 한 줄 글자 수 (한글 기준)
        let lineCount = max(
            CGFloat(text.components(separatedBy: .newlines).count),
            ceil(CGFloat(text.count) / charsPerLine)
        )
        return lineCount * lineHeight
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

    override var canBecomeKey: Bool { true }
}
