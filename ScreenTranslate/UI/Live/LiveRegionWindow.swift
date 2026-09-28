import AppKit

/// 실시간 번역이 지켜보는 영역의 테두리·툴바·크기 손잡이.
/// 테두리는 클릭을 통과시키고 툴바(이동·중지)와 손잡이(크기)만 마우스를 받는다. 모두 포커스를 빼앗지 않는다.
final class LiveRegionWindow {
    static let toolbarSize = CGSize(width: 196, height: 26)
    private static let handleSize: CGFloat = 16

    /// 화면 로컬·좌상단 원점·포인트 (오버레이·캡처와 같은 좌표)
    private(set) var region: CGRect
    let screen: NSScreen
    var onStop: (() -> Void)?
    var onRegionChange: (() -> Void)?

    private let outline: NSPanel
    private let toolbar: NSPanel
    private let handle: NSPanel
    private var gestureStartRegion: CGRect = .zero

    init(region: CGRect, screen: NSScreen) {
        self.region = region
        self.screen = screen
        outline = Self.makePanel()
        toolbar = Self.makePanel()
        handle = Self.makePanel()

        outline.ignoresMouseEvents = true
        outline.contentView = OutlineView()

        let toolbarView = RegionControlView(kind: .move)
        toolbarView.toolTip = L10n.liveToolbarLabel
        toolbarView.onBegin = { [weak self] in self?.beginGesture() }
        toolbarView.onDrag = { [weak self] delta in self?.move(by: delta) }
        toolbarView.onStop = { [weak self] in self?.onStop?() }
        let stop = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n.stopLiveTranslation)
                ?? NSImage(),
            target: toolbarView,
            action: #selector(RegionControlView.stopPressed)
        )
        stop.isBordered = false
        stop.contentTintColor = .white
        stop.toolTip = L10n.stopLiveTranslation
        stop.frame = CGRect(x: Self.toolbarSize.width - 26, y: 3, width: 22, height: 20)
        toolbarView.addSubview(stop)
        toolbar.contentView = toolbarView

        let handleView = RegionControlView(kind: .resize)
        handleView.toolTip = L10n.liveResizeHelp
        handleView.onBegin = { [weak self] in self?.beginGesture() }
        handleView.onDrag = { [weak self] delta in self?.resize(by: delta) }
        handle.contentView = handleView

        relayout()
    }

    /// AppKit 전역 좌표의 영역 프레임
    var regionFrame: CGRect { LiveLayout.globalFrame(of: region, screenFrame: screen.frame) }

    func show() {
        [outline, toolbar, handle].forEach { $0.orderFrontRegardless() }
    }

    func close() {
        [outline, toolbar, handle].forEach { $0.close() }
    }

    /// 영역이나 화면 배치가 바뀌면 세 창을 다시 놓는다
    func relayout() {
        let frame = regionFrame
        outline.setFrame(frame.insetBy(dx: -3, dy: -3), display: true)  // 테두리는 캡처 영역 바깥에
        let visible = screen.visibleFrame
        let toolbarOrigin = CGPoint(
            x: min(max(frame.minX, visible.minX), visible.maxX - Self.toolbarSize.width),
            y: min(frame.maxY + 4, visible.maxY - Self.toolbarSize.height)
        )
        toolbar.setFrame(CGRect(origin: toolbarOrigin, size: Self.toolbarSize), display: true)
        handle.setFrame(CGRect(x: frame.maxX - Self.handleSize / 2, y: frame.minY - Self.handleSize / 2,
                               width: Self.handleSize, height: Self.handleSize), display: true)
    }

    private func beginGesture() {
        gestureStartRegion = region
    }

    private func move(by delta: CGSize) {
        apply(LiveLayout.moved(gestureStartRegion, by: delta, within: screen.frame.size))
    }

    private func resize(by delta: CGSize) {
        apply(LiveLayout.resized(gestureStartRegion, by: delta, within: screen.frame.size))
    }

    private func apply(_ newRegion: CGRect) {
        guard newRegion != region else { return }
        region = newRegion
        relayout()
        onRegionChange?()
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // 전체 화면 영상 위에도
        return panel
    }
}

private final class OutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 4
        path.stroke()
        NSColor.systemTeal.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

/// 툴바(이동)와 손잡이(크기) — 비활성 앱에서도 첫 클릭부터 드래그되도록 acceptsFirstMouse
private final class RegionControlView: NSView {
    enum Kind { case move, resize }
    let kind: Kind
    var onBegin: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onStop: (() -> Void)?
    private var startPoint: NSPoint = .zero

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: kind == .move ? .openHand : .crosshair)
    }

    @objc func stopPressed() {
        onStop?()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        // AppKit은 위로 갈수록 +y, 영역 좌표는 아래로 갈수록 +y
        onDrag?(CGSize(width: point.x - startPoint.x, height: startPoint.y - point.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
        let radius: CGFloat = kind == .move ? 7 : 4
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius).fill()
        NSColor.systemTeal.setFill()
        if kind == .move {
            NSBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 7, height: 7)).fill()
            (L10n.liveToolbarLabel as NSString).draw(
                at: CGPoint(x: 23, y: 6),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                 .foregroundColor: NSColor.white]
            )
        } else {
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 2, yRadius: 2).fill()
        }
    }
}
