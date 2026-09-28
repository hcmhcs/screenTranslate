import CoreGraphics
import Testing
@testable import ScreenTranslate

/// 실시간 번역 창 배치 — 영역 좌표 변환, 자막 바 위치, 이동·크기 조절 제한.
@Suite struct LiveLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)  // 메뉴바 25pt 제외

    @Test("a top-left local region maps to a bottom-left global frame")
    func globalFrame() {
        let frame = LiveLayout.globalFrame(of: CGRect(x: 100, y: 700, width: 600, height: 80), screenFrame: screen)
        #expect(frame == CGRect(x: 100, y: 120, width: 600, height: 80))
    }

    @Test("the bar follows the region width within limits")
    func barWidth() {
        #expect(LiveLayout.subtitleBarWidth(regionWidth: 600, visibleFrame: visible) == 600)
        #expect(LiveLayout.subtitleBarWidth(regionWidth: 100, visibleFrame: visible) == LiveLayout.barMinWidth)
        #expect(LiveLayout.subtitleBarWidth(regionWidth: 2000, visibleFrame: visible) == 1440 - LiveLayout.screenMargin * 2)
    }

    @Test("the bar sits just below the region when there is room")
    func barBelow() {
        let region = CGRect(x: 400, y: 300, width: 600, height: 80)
        let bar = LiveLayout.subtitleBarFrame(regionFrame: region, barSize: CGSize(width: 600, height: 40),
                                              toolbarHeight: 26, visibleFrame: visible)
        #expect(bar == CGRect(x: 400, y: 300 - LiveLayout.barGap - 40, width: 600, height: 40))
    }

    @Test("the bar moves above the toolbar when the region is at the bottom")
    func barAbove() {
        let region = CGRect(x: 400, y: 10, width: 600, height: 60)
        let bar = LiveLayout.subtitleBarFrame(regionFrame: region, barSize: CGSize(width: 600, height: 40),
                                              toolbarHeight: 26, visibleFrame: visible)
        #expect(bar.minY == 70 + 26 + LiveLayout.barGap)
    }

    @Test("the bar stays inside the screen horizontally")
    func barClamped() {
        let region = CGRect(x: 1300, y: 300, width: 140, height: 60)
        let bar = LiveLayout.subtitleBarFrame(regionFrame: region, barSize: CGSize(width: 280, height: 40),
                                              toolbarHeight: 26, visibleFrame: visible)
        #expect(bar.maxX == 1440 - LiveLayout.screenMargin)
    }

    @Test("moving never pushes the region off the screen")
    func movedClamped() {
        let rect = CGRect(x: 10, y: 10, width: 200, height: 50)
        let moved = LiveLayout.moved(rect, by: CGSize(width: -100, height: 5000), within: screen.size)
        #expect(moved == CGRect(x: 0, y: 900 - 50, width: 200, height: 50))
    }

    @Test("resizing keeps a minimum size and stops at the screen edge")
    func resizedClamped() {
        let rect = CGRect(x: 1300, y: 10, width: 100, height: 50)
        let smaller = LiveLayout.resized(rect, by: CGSize(width: -500, height: -500), within: screen.size)
        #expect(smaller.size == LiveLayout.minRegionSize)
        let larger = LiveLayout.resized(rect, by: CGSize(width: 500, height: 0), within: screen.size)
        #expect(larger.maxX == 1440)
    }
}
