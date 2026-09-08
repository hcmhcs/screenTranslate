import AppKit

/// The outline passes clicks through; only the toolbar and corner handles receive them.
final class LiveTranslationRegionWindow: NSPanel {
    private(set) var captureRect: CGRect
    private(set) var revision = 0
    var onChange: (() -> Void)?
    var onStop: (() -> Void)?
    private let captureScreen: NSScreen
    private var controls: [NSPanel] = []

    init(rect: CGRect, screen: NSScreen) {
        captureRect = rect
        captureScreen = screen
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        configure(self)
        ignoresMouseEvents = true
        contentView = RegionOutlineView()

        let toolbar = RegionControlView(corner: nil)
        toolbar.owner = self
        toolbar.toolTip = L10n.liveRegionHelp
        addControl(toolbar, size: NSSize(width: 170, height: 30))
        for corner in 0..<4 {
            let handle = RegionControlView(corner: corner)
            handle.owner = self
            handle.toolTip = L10n.resizeLiveRegion
            addControl(handle, size: NSSize(width: 16, height: 16))
        }
        layoutRegion()
    }

    private func configure(_ panel: NSPanel) {
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func addControl(_ view: NSView, size: NSSize) {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel)
        panel.contentView = view
        controls.append(panel)
        addChildWindow(panel, ordered: .above)
    }

    private func layoutRegion() {
        let rect = captureRect
        let frame = CGRect(x: captureScreen.frame.minX + rect.minX,
                           y: captureScreen.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height)
        setFrame(frame, display: true)
        let visible = captureScreen.visibleFrame
        controls[0].setFrameOrigin(CGPoint(
            x: min(max(frame.minX, visible.minX), visible.maxX - 170),
            y: min(frame.maxY + 6, visible.maxY - 30)))
        let corners = [CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY),
                       CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY)]
        for (index, point) in corners.enumerated() {
            controls[index + 1].setFrameOrigin(CGPoint(x: point.x - 8, y: point.y - 8))
        }
    }

    func adjust(from start: CGRect, delta: CGPoint, corner: Int?) {
        let size = captureScreen.frame.size
        var rect = start
        if let corner {
            let left = corner == 0 || corner == 2
            let top = corner < 2
            let minWidth = min(40, start.width)
            let minHeight = min(20, start.height)
            if left {
                rect.origin.x = min(max(0, start.minX + delta.x), start.maxX - minWidth)
                rect.size.width = start.maxX - rect.minX
            } else {
                rect.size.width = max(minWidth, min(size.width, start.maxX + delta.x) - start.minX)
            }
            if top {
                rect.origin.y = min(max(0, start.minY + delta.y), start.maxY - minHeight)
                rect.size.height = start.maxY - rect.minY
            } else {
                rect.size.height = max(minHeight, min(size.height, start.maxY + delta.y) - start.minY)
            }
        } else {
            rect.origin.x = min(max(0, start.minX + delta.x), size.width - start.width)
            rect.origin.y = min(max(0, start.minY + delta.y), size.height - start.height)
        }
        guard rect != captureRect else { return }
        captureRect = rect
        revision += 1
        layoutRegion()
        onChange?()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        controls.forEach { $0.orderFrontRegardless() }
    }

    override func close() {
        controls.forEach { $0.close() }
        super.close()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RegionOutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 4
        path.stroke()
        NSColor.systemTeal.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

private final class RegionControlView: NSView {
    weak var owner: LiveTranslationRegionWindow?
    let corner: Int?
    private var startPoint = CGPoint.zero
    private var startRect = CGRect.zero

    init(corner: Int?) {
        self.corner = corner
        super.init(frame: .zero)
        if corner == nil {
            let stop = NSButton(image: NSImage(systemSymbolName: "stop.fill", accessibilityDescription: L10n.stopLiveTranslation)!,
                                target: self, action: #selector(stopLive))
            stop.isBordered = false
            stop.contentTintColor = .white
            stop.frame = CGRect(x: 140, y: 3, width: 26, height: 24)
            stop.toolTip = L10n.stopLiveTranslation
            addSubview(stop)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func stopLive() { owner?.onStop?() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: corner == nil ? .openHand : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.12, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: corner == nil ? 8 : 4,
                     yRadius: corner == nil ? 8 : 4).fill()
        NSColor.systemTeal.setFill()
        if corner == nil {
            NSBezierPath(ovalIn: CGRect(x: 12, y: 11, width: 8, height: 8)).fill()
            (L10n.liveRegion as NSString).draw(at: CGPoint(x: 27, y: 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
            ])
        } else {
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 2, yRadius: 2).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        startRect = owner?.captureRect ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        owner?.adjust(from: startRect, delta: CGPoint(x: point.x - startPoint.x, y: startPoint.y - point.y), corner: corner)
    }
}
