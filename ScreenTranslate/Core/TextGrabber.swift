import AppKit
import ApplicationServices
import OSLog

private let logger = Logger(subsystem: "com.app.screentranslate", category: "textGrabber")

/// 다른 앱에서 선택된 텍스트를 가져오는 유틸리티.
/// Accessibility API를 우선 시도하고, 실패 시 Cmd+C fallback.
enum TextGrabber {

    /// Accessibility 권한 확인
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 권한 요청 다이얼로그 트리거 (시스템 설정 유도)
    static func requestAccessibilityPermission() {
        // kAXTrustedCheckOptionPrompt는 전역 var라 strict concurrency에서 경고 — 문서화된 키 문자열을 직접 쓴다
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 선택된 텍스트를 가져온다. A(Accessibility) → B(Cmd+C) fallback.
    static func getSelectedText() async -> String? {
        // A: Accessibility API 시도
        if let text = tryAccessibilityAPI(), !text.isEmpty {
            logger.debug("Accessibility API로 텍스트 획득: \(text.prefix(50))")
            return text
        }

        // B: Cmd+C fallback
        if let text = await tryCopyFallback(), !text.isEmpty {
            logger.debug("Cmd+C fallback으로 텍스트 획득: \(text.prefix(50))")
            return text
        }

        logger.debug("선택된 텍스트를 가져올 수 없음")
        return nil
    }

    // MARK: - A: Accessibility API

    /// AXUIElement로 포커스된 앱의 선택 텍스트를 읽는다.
    private static func tryAccessibilityAPI() -> String? {
        let systemElement = AXUIElementCreateSystemWide()

        // 포커스된 앱의 포커스된 UI 요소 가져오기
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let appElement = asAXUIElement(focusedApp) else {
            return nil
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let uiElement = asAXUIElement(focusedElement) else {
            return nil
        }

        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(uiElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success else {
            return nil
        }

        return selectedText as? String
    }

    /// M9: 일부 앱은 포커스 속성으로 AXUIElement가 아닌 CFType을 돌려준다. 타입 확인 후 변환한다.
    private static func asAXUIElement(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)  // 타입 ID를 확인했으므로 안전
    }

    // MARK: - B: Cmd+C Fallback

    /// 폴백 재진입 방지 — 동시에 두 번 실행되면 백업/복원이 서로 꼬인다
    private static var isCopyFallbackRunning = false

    /// CGEvent로 Cmd+C를 전송하고 클립보드에서 텍스트를 읽는다.
    /// 클립보드는 모든 타입을 스냅샷해 두었다가 그대로 복원한다 (C3).
    private static func tryCopyFallback() async -> String? {
        guard !isCopyFallbackRunning else { return nil }
        isCopyFallbackRunning = true
        defer { isCopyFallbackRunning = false }

        let pasteboard = NSPasteboard.general
        let originalChangeCount = pasteboard.changeCount

        // 클립보드 원본 백업 (문자열뿐 아니라 이미지·파일·서식 텍스트 전부)
        let snapshot = PasteboardSnapshot(of: pasteboard)

        // Cmd+C 이벤트 전송
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),  // 'c' key
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            return nil
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // 클립보드 업데이트 대기 (최대 500ms, 50ms 간격 폴링)
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            if pasteboard.changeCount != originalChangeCount {
                break
            }
        }

        // 복원 전에 복사 성공 여부 판정 (복원이 changeCount를 변경하므로)
        let copySucceeded = pasteboard.changeCount != originalChangeCount
        let newText = pasteboard.string(forType: .string)

        // 클립보드 원본 복원 (비어있었으면 비운 상태로 복원)
        snapshot.restore(to: pasteboard)

        guard copySucceeded, let text = newText, !text.isEmpty else {
            return nil
        }

        return text
    }
}
