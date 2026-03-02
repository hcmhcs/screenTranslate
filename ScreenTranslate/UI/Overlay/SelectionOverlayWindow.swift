import AppKit
import SwiftUI

/// 전체 화면을 덮는 투명 오버레이 창.
/// 사용자가 드래그로 영역을 선택하면 completion 핸들러를 호출한다.
final class SelectionOverlayWindow: NSWindow {
    private var completion: ((CGRect?) -> Void)?

    init() {
        // 현재 마우스 위치의 디스플레이를 찾는다
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]

        super.init(
            contentRect: screen.frame,
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
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]
        setFrame(screen.frame, display: true)

        let overlayView = SelectionOverlayView(
            onComplete: { [weak self] rect in
                self?.completion = nil  // 이중 호출 방지
                self?.close()
                completion(rect)
            },
            onCancel: { [weak self] in
                self?.completion = nil  // 이중 호출 방지
                self?.close()
                completion(nil)
            }
        )

        contentView = NSHostingView(rootView: overlayView)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    // ESC 키 처리 — AppKit 레벨 (SwiftUI onKeyPress는 포커스 필요)
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            close()
            completion?(nil)
            completion = nil
        } else {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
