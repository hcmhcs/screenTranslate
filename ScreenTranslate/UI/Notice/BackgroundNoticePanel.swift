import AppKit
import SwiftUI

/// 메뉴바 아이콘이 숨겨진 채로 앱을 새로 켰을 때 화면 위쪽에 잠깐 띄우는 안내 (이슈 #3).
/// 아무 창 없이 켜지면 "실행이 안 됐다"로 보이므로, 실행 중이라는 사실과 설정으로 가는 길을 알려준다.
/// 포커스를 빼앗지 않는 패널이라 로그인 직후 하던 작업을 방해하지 않는다.
final class BackgroundNoticePanel: NSPanel {
    var onDidClose: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    init(onOpenSettings: @escaping () -> Void) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: BackgroundNoticeView(onOpenSettings: onOpenSettings))
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
    }

    /// 화면 위쪽 가운데(메뉴바 바로 아래)에 띄우고 duration 뒤에 사라진다.
    func present(on screen: NSScreen?, for duration: Duration = .seconds(6)) {
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 12))

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.fadeOutAndClose()
        }
    }

    private func fadeOutAndClose() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // NSAnimationContext 완료 핸들러는 메인 스레드에서 불리지만 @Sendable로 선언되어 있다
            MainActor.assumeIsolated {
                self?.close()
            }
        })
    }

    override func close() {
        dismissTask?.cancel()
        dismissTask = nil
        super.close()
        onDidClose?()
    }

    /// 테두리 없는 패널은 기본적으로 키 창이 될 수 없다 — 번역 팝업과 같이 허용하되
    /// becomesKeyOnlyIfNeeded라 버튼 클릭만으로는 키 창이 되지 않아 포커스를 빼앗지 않는다.
    override var canBecomeKey: Bool { true }
}

private struct BackgroundNoticeView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.backgroundNoticeTitle)
                    .font(.headline)
                Text(L10n.backgroundNoticeBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 본문이 길어도 한 줄로 늘어나지 않고 줄바꿈되도록 폭을 고정한다
            .frame(width: 260, alignment: .leading)
            Button(L10n.openSettings, action: onOpenSettings)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}
