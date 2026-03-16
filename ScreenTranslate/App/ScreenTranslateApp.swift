import SwiftUI
import KeyboardShortcuts
import TelemetryDeck

extension KeyboardShortcuts.Name {
    static let translate = Self("translate", default: .init(.t, modifiers: [.command, .shift]))
    static let dragTranslate = Self("dragTranslate", default: .init(.z, modifiers: [.command, .option]))
}

@main
struct ScreenTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("ScreenTranslate", image: "MenuBarIcon") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}

/// TranslationBridge를 상주시키기 위한 AppDelegate.
/// MenuBarExtra 콘텐츠는 메뉴가 열릴 때만 생성되므로,
/// TranslationBridge를 별도의 off-screen NSWindow에 호스팅한다.
///
/// 또한 KeyboardShortcuts 등록을 NSApplication이 완전히 초기화된 후
/// (applicationDidFinishLaunching)에 수행하여 초기화 순서 문제를 방지한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bridgeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // TelemetryDeck 초기화
        let config = TelemetryDeck.Config(appID: "D40DAE14-17FE-4D5E-86B9-294CA7E45B7F")
        TelemetryDeck.initialize(config: config)
        TelemetryDeck.signal("appLaunched")

        // 키보드 단축키 등록 — NSApplication 초기화 완료 후 안전하게 수행
        AppOrchestrator.shared.setup()

        // TranslationBridge 호스팅 윈도우 생성
        // .translationTask는 윈도우가 ordered 상태여야 SwiftUI 업데이트가 동작한다.
        // orderOut하면 SwiftUI 렌더링 파이프라인이 중단되어 configuration 변경 감지 불가.
        // → alphaValue = 0 (투명) + orderBack (뒤로 보내기)으로 보이지 않게 유지한다.
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = NSHostingView(rootView: TranslationBridgeView())
        window.orderBack(nil)
        self.bridgeWindow = window

        // 첫 실행 온보딩 표시
        AppOrchestrator.shared.showOnboardingIfNeeded()
    }
}
