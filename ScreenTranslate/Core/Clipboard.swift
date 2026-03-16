import AppKit

enum Clipboard {
    /// 텍스트를 시스템 클립보드에 복사한다.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
