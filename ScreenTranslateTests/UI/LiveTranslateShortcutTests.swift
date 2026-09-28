import AppKit
import Foundation
import KeyboardShortcuts
import Testing
@testable import ScreenTranslate

extension SerializedDefaultsSuite {
/// 베타를 끄면 실시간 번역 단축키도 풀려야 한다 — Carbon 핫키는 콜백이 무시해도 그 키 조합을 다른 앱에서 가로챈다.
@MainActor
@Suite struct LiveTranslateShortcutTests {

    @Test("turning the beta off releases the hotkey and turning it on restores it")
    func followsBetaSetting() {
        let key = "com.screentranslate.liveTranslateEnabled"
        let savedBeta = UserDefaults.standard.object(forKey: key)
        let savedShortcut = KeyboardShortcuts.getShortcut(for: .liveTranslate)
        defer {
            KeyboardShortcuts.setShortcut(savedShortcut, for: .liveTranslate)
            if let savedBeta { UserDefaults.standard.set(savedBeta, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            AppOrchestrator.shared.updateLiveTranslateShortcut()
        }
        // 잘 쓰지 않는 조합으로 잠시 지정 (isEnabled는 단축키가 있어야 참이다)
        KeyboardShortcuts.setShortcut(.init(.f12, modifiers: [.command, .option, .control]), for: .liveTranslate)

        AppSettings.shared.liveTranslateEnabled = false
        AppOrchestrator.shared.updateLiveTranslateShortcut()
        #expect(!KeyboardShortcuts.isEnabled(for: .liveTranslate))

        AppSettings.shared.liveTranslateEnabled = true
        AppOrchestrator.shared.updateLiveTranslateShortcut()
        #expect(KeyboardShortcuts.isEnabled(for: .liveTranslate))
    }
}
}
