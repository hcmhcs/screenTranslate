import AppKit

extension NSApplication {
    /// 보조 윈도우(설정, About, 히스토리 등)를 다른 앱 뒤로 보낸다.
    /// 앱 activate 시 normal-level 윈도우가 다른 앱 위로 올라오는 것을 방지하기 위해 사용한다.
    /// - Parameter excluding: orderBack 대상에서 제외할 윈도우 (보통 호출자 자신)
    func orderBackAuxiliaryWindows(excluding: NSWindow? = nil) {
        for window in windows where window !== excluding
            && window.isVisible
            && window.level == .normal
            && window.alphaValue > 0 {
            window.orderBack(nil)
        }
    }
}
