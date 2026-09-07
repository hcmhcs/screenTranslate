import AppKit
import SwiftUI

/// NSHostingView의 두 가지 커서 관리 경로(resetCursorRects, cursorUpdate)를
/// 모두 차단하고 십자 커서를 강제하는 서브클래스.
/// NOTE: 제네릭이 아니라 구체 타입으로 선언한다 — CI(Xcode 26.6, Swift 6.3.3)의
/// EarlyPerfInliner가 제네릭 NSHostingView 서브클래스의 deinit을 Release(-O)
/// 최적화하다 크래시한다 (v1.5.3 첫 배포 시도 로그). 이 뷰는 SelectionOverlayView만
/// 호스팅하므로 제네릭이 필요 없다.
private final class CrosshairHostingView: NSHostingView<SelectionOverlayView> {
    deinit {}

    override func resetCursorRects() {
        // super 호출 안함 — NSHostingView의 기본 화살표 커서를 십자 커서로 완전 대체
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        // super 호출 안함 — NSHostingView의 커서 업데이트 이벤트 전파 차단
        NSCursor.crosshair.set()
    }
}

/// 전체 화면을 덮는 투명 오버레이 창.
/// 사용자가 드래그로 영역을 선택하면 completion 핸들러를 호출한다.
final class SelectionOverlayWindow: NSWindow {
    private var completion: ((CGRect?) -> Void)?

    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false  // ARC 환경에서 close() 시 이중 해제 방지
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    func show(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        // 현재 마우스 위치의 디스플레이에 표시
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else {
            // 화면을 못 찾으면 취소로 끝낸다 — completion을 안 부르면 호출자의 선택 중 플래그가 영영 남는다
            self.completion = nil
            completion(nil)
            return
        }
        setFrame(screen.frame, display: true)

        let overlayView = SelectionOverlayView(
            onComplete: { [weak self] rect in
                guard let self else { return }
                let handler = self.completion
                self.completion = nil
                self.close()
                handler?(rect)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                let handler = self.completion
                self.completion = nil
                self.close()
                handler?(nil)
            }
        )

        contentView = CrosshairHostingView(rootView: overlayView)
        NSApp.activate()
        makeKeyAndOrderFront(nil)

        // 앱 활성화 시 보조 윈도우(설정, About 등)가 다른 앱 위로 올라오는 것을 방지
        NSApp.orderBackAuxiliaryWindows(excluding: self)
    }

    // ESC 키 처리 — AppKit 레벨 (SwiftUI onKeyPress는 포커스 필요)
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            let handler = completion
            completion = nil
            close()
            handler?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
