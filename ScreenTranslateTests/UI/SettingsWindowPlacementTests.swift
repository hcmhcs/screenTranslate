import CoreGraphics
import Testing
@testable import ScreenTranslate

/// 설정 창 배치 — 메뉴바 아이콘 바로 아래. 모니터 한 대, 노치 맥북, 보조 모니터, 아이콘 없음까지.
/// 창은 빈 크기로 만들어진 뒤 윗변을 고정한 채 커지므로(실측) 윗변 왼쪽 점을 계산한다.
@Suite struct SettingsWindowPlacementTests {
    private let width: CGFloat = 480
    private let gap = SettingsWindowPlacement.gap
    private let margin = SettingsWindowPlacement.screenMargin

    // 외장 모니터 한 대 (메뉴바 30pt)
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)

    private func topLeft(anchor: CGRect?, screen: CGRect, visible: CGRect) -> CGPoint {
        SettingsWindowPlacement.topLeft(windowWidth: width, anchor: anchor, screenFrame: screen,
                                        visibleFrame: visible, menuBarThickness: 24)
    }

    @Test("the window sits right below the icon, centered on it")
    func centeredBelowIcon() {
        let icon = CGRect(x: 1079, y: 1050, width: 34, height: 30)
        #expect(topLeft(anchor: icon, screen: screen, visible: visible) == CGPoint(x: 1096 - 240, y: 1050 - gap))
    }

    @Test("an icon at the right end keeps the window inside the screen")
    func clampsRight() {
        let icon = CGRect(x: 1880, y: 1050, width: 34, height: 30)
        #expect(topLeft(anchor: icon, screen: screen, visible: visible).x == 1920 - margin - 480)
    }

    @Test("an icon at the left end keeps the window inside the screen")
    func clampsLeft() {
        let icon = CGRect(x: 10, y: 1050, width: 34, height: 30)
        #expect(topLeft(anchor: icon, screen: screen, visible: visible).x == margin)
    }

    @Test("MacBook with a notch — never overlaps the taller menu bar, even if the icon window is shorter")
    func notchedMacBook() {
        let macScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let macVisible = CGRect(x: 0, y: 0, width: 1512, height: 945)  // 메뉴바 37pt
        let fullHeightIcon = CGRect(x: 1300, y: 945, width: 34, height: 37)
        let shortIcon = CGRect(x: 1300, y: 951, width: 34, height: 24)
        #expect(topLeft(anchor: fullHeightIcon, screen: macScreen, visible: macVisible).y == 945 - gap)
        #expect(topLeft(anchor: shortIcon, screen: macScreen, visible: macVisible).y == 945 - gap)
    }

    @Test("a second display whose visible frame includes the menu bar still goes below the icon")
    func secondaryDisplay() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let icon = CGRect(x: -841, y: 1050, width: 34, height: 30)
        #expect(topLeft(anchor: icon, screen: left, visible: left) == CGPoint(x: -824 - 240, y: 1050 - gap))
    }

    @Test("without an icon (hidden) the window goes to the top center, below the menu bar")
    func noIcon() {
        #expect(topLeft(anchor: nil, screen: screen, visible: visible) == CGPoint(x: 960 - 240, y: 1050 - gap))
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(topLeft(anchor: nil, screen: left, visible: left).y == 1080 - 24 - gap)
    }

    @Test("picks the icon on the given display")
    func anchorOnDisplay() {
        let primaryIcon = CGRect(x: 1079, y: 1050, width: 34, height: 30)
        let leftIcon = CGRect(x: -841, y: 1050, width: 34, height: 30)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(SettingsWindowPlacement.anchor(among: [leftIcon, primaryIcon], on: screen) == primaryIcon)
        #expect(SettingsWindowPlacement.anchor(among: [leftIcon, primaryIcon], on: left) == leftIcon)
        #expect(SettingsWindowPlacement.anchor(among: [primaryIcon], on: screen) == primaryIcon)
    }

    @Test("an icon moved off screen (menu bar managers) or on another display is not used")
    func anchorMissing() {
        let offScreen = CGRect(x: -5000, y: 1050, width: 34, height: 30)
        #expect(SettingsWindowPlacement.anchor(among: [offScreen], on: screen) == nil)
        #expect(SettingsWindowPlacement.anchor(among: [], on: screen) == nil)
    }

    @Test("displays stacked vertically — the icon of the display above is not used")
    func stackedDisplays() {
        let upper = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let upperIcon = CGRect(x: 1079, y: 2130, width: 34, height: 30)
        let lowerIcon = CGRect(x: 1079, y: 1050, width: 34, height: 30)
        #expect(SettingsWindowPlacement.anchor(among: [upperIcon, lowerIcon], on: screen) == lowerIcon)
        #expect(SettingsWindowPlacement.anchor(among: [upperIcon, lowerIcon], on: upper) == upperIcon)
        #expect(SettingsWindowPlacement.anchor(among: [upperIcon], on: screen) == nil)
    }

    @Test("an auto-hidden menu bar keeps the icon usable and the window inside the screen")
    func autoHiddenMenuBar() {
        let hiddenIcon = CGRect(x: 1079, y: 1080, width: 34, height: 30)  // 화면 위로 숨은 메뉴바
        let anchor = SettingsWindowPlacement.anchor(among: [hiddenIcon], on: screen)
        #expect(anchor == hiddenIcon)
        #expect(topLeft(anchor: anchor, screen: screen, visible: screen) == CGPoint(x: 1096 - 240, y: 1080 - gap))
    }
}
