import AppKit
import Testing
@testable import ScreenTranslate

/// 아이콘을 숨긴 채 켜졌을 때의 "실행 중" 안내 패널 (이슈 #3).
/// 오케스트레이터는 onDidClose로 참조를 정리하므로, 스스로 닫히고 그 사실을 한 번만 알려야 한다.
@MainActor
@Suite struct BackgroundNoticePanelTests {

    @Test("closes itself after the given duration and reports it",
          .enabled(if: NSScreen.main != nil, "화면이 없는 환경에서는 패널을 띄울 수 없다"))
    func autoDismisses() async throws {
        let panel = BackgroundNoticePanel(onOpenSettings: {})
        var closeCount = 0
        panel.onDidClose = { closeCount += 1 }

        panel.present(on: NSScreen.main, for: .milliseconds(50))
        #expect(panel.isVisible)

        for _ in 0..<40 where closeCount == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(closeCount == 1)
        #expect(!panel.isVisible)
    }

    @Test("closing early cancels the pending auto-dismiss",
          .enabled(if: NSScreen.main != nil, "화면이 없는 환경에서는 패널을 띄울 수 없다"))
    func earlyCloseReportsOnce() async throws {
        let panel = BackgroundNoticePanel(onOpenSettings: {})
        var closeCount = 0
        panel.onDidClose = { closeCount += 1 }

        panel.present(on: NSScreen.main, for: .milliseconds(100))
        panel.close()
        try await Task.sleep(for: .milliseconds(600))

        #expect(closeCount == 1)
    }

    @Test("does not take focus away from the app the user is in")
    func doesNotActivate() {
        let panel = BackgroundNoticePanel(onOpenSettings: {})
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.becomesKeyOnlyIfNeeded)
    }
}
