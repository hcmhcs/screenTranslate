import SwiftUI
import KeyboardShortcuts
import TelemetryDeck
import os

private let logger = Logger(subsystem: "com.app.screentranslate", category: "lifecycle")

extension KeyboardShortcuts.Name {
    static let translate = Self("translate", default: .init(.e, modifiers: [.command]))
    static let dragTranslate = Self("dragTranslate", default: .init(.z, modifiers: [.command, .option]))
    static let quickTranslate = Self("quickTranslate", default: .init(.e, modifiers: [.command, .shift]))
    /// 실시간 번역(베타) — 기본값 없음: 다른 앱 단축키와의 충돌을 피하고, 베타를 켠 사람만 직접 정한다
    static let liveTranslate = Self("liveTranslate")
}

@main
struct ScreenTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// 아이콘을 숨겨도 단축키는 AppOrchestrator.setup()에서 따로 등록되므로 계속 동작한다
    @AppStorage(AppSettings.showMenuBarIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        // 같은 값 되쓰기를 걸러야 한다 — 그대로 연결하면 CPU 100% 루프 (Binding+WritingOnlyChanges 참고)
        MenuBarExtra("ScreenTranslate", image: "MenuBarIcon", isInserted: $showMenuBarIcon.writingOnlyChanges()) {
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
        // 실행 Apple 이벤트는 이 콜백 안에서만 읽힌다 — 다른 작업보다 먼저 읽어 둔다
        let launchKind = MenuBarIconPolicy.launchKind(from: NSAppleEventManager.shared().currentAppleEvent)
        // 로그인 실행 판정이 실제로 되는지 확인하기 위한 기록 (사전 확인에서 실측하지 못한 부분).
        // info는 디스크에 남지 않아 로그인 뒤 log show로 볼 수 없으므로 notice로 남긴다
        logger.notice("launch kind=\(String(describing: launchKind), privacy: .public) menuBarIconVisible=\(AppSettings.shared.showMenuBarIcon, privacy: .public)")

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
        // 아이콘이 숨겨진 채 직접 켰으면 실행 중임을 알린다
        AppOrchestrator.shared.showBackgroundNoticeIfNeeded(launchKind: launchKind)
    }

    /// Finder·Spotlight·Raycast 등에서 이미 실행 중인 앱을 다시 열면 호출된다.
    /// hasVisibleWindows는 투명 브리지 창 때문에 항상 true라 판단에 쓰지 않는다 (2026-09-29 실측).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppOrchestrator.shared.handleReopen()
        return false  // 직접 처리했으므로 AppKit 기본 동작은 하지 않는다
    }
}
