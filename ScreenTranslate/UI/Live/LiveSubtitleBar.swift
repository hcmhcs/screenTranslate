import AppKit
import SwiftUI

/// 실시간 번역 결과를 영역 옆에 보여주는 자막 바 — 클릭을 통과시키고 포커스를 빼앗지 않는다.
final class LiveSubtitleBar: NSPanel {
    private let hostingView = NSHostingView(
        rootView: LiveSubtitleView(display: .hidden, width: LiveLayout.barMinWidth)
    )

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
    }

    func update(display: LiveTranslationSession.Display, regionFrame: CGRect, visibleFrame: CGRect) {
        guard display != .hidden else {
            fadeOut()
            return
        }
        let width = LiveLayout.subtitleBarWidth(regionWidth: regionFrame.width, visibleFrame: visibleFrame)
        hostingView.rootView = LiveSubtitleView(display: display, width: width)
        let size = hostingView.fittingSize
        setFrame(LiveLayout.subtitleBarFrame(regionFrame: regionFrame, barSize: size,
                                             toolbarHeight: LiveRegionWindow.toolbarSize.height,
                                             visibleFrame: visibleFrame), display: true)
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    private func fadeOut() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // NSAnimationContext 완료 핸들러는 메인 스레드에서 불리지만 @Sendable로 선언되어 있다
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }
}

private struct LiveSubtitleView: View {
    let display: LiveTranslationSession.Display
    let width: CGFloat

    var body: some View {
        content
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: width)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch display {
        case .subtitle(let text):
            Text(text)
                .font(FontManager.shared.swiftUIFont(size: AppSettings.shared.popupFontSize + 6))
                .foregroundStyle(.white)
        case .message(let text):
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
        case .hidden:
            EmptyView()
        }
    }
}
