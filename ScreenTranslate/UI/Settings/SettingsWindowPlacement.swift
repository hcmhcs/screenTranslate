import CoreGraphics

/// 설정 창 배치 — 메뉴바 아이콘 바로 아래에 붙인다. AppKit 없이 테스트한다 (좌하단 원점 전역 좌표).
/// 아이콘을 못 찾으면(숨김·메뉴바 정리 앱·다른 모니터) 그 화면의 메뉴바 아래 가운데.
nonisolated enum SettingsWindowPlacement {
    static let gap: CGFloat = 4
    static let screenMargin: CGFloat = 8

    /// 이 화면 메뉴바에 있는 아이콘 창. 모니터마다 하나씩 있으므로(macOS 26 실측) 화면 맨 위에 붙은 것을 고른다.
    /// 자동 숨김 메뉴바는 화면 바로 위로 비켜 있을 수 있어 아이콘 높이의 2배까지 허용한다.
    static func anchor(among iconFrames: [CGRect], on screenFrame: CGRect) -> CGRect? {
        iconFrames
            .filter { $0.midX >= screenFrame.minX && $0.midX < screenFrame.maxX }
            .map { (frame: $0, distance: abs($0.midY - (screenFrame.maxY - $0.height / 2))) }
            .filter { $0.distance <= $0.frame.height * 2 }
            .min { $0.distance < $1.distance }?
            .frame
    }

    /// 창의 윗변 왼쪽 점. 창은 빈 크기로 만들어진 뒤 윗변을 고정한 채 내용 크기로 커지므로(실측) 높이는 쓰지 않는다.
    /// 윗변은 메뉴바 아래 — 아이콘 창이 메뉴바보다 낮게 잡혀도(노치) 쓸 수 있는 영역 위로는 안 올린다.
    static func topLeft(windowWidth: CGFloat, anchor: CGRect?, screenFrame: CGRect,
                        visibleFrame: CGRect, menuBarThickness: CGFloat) -> CGPoint {
        let top: CGFloat
        let centerX: CGFloat
        if let anchor {
            top = min(anchor.minY, visibleFrame.maxY) - gap
            centerX = anchor.midX
        } else {
            // 보조 모니터는 쓸 수 있는 영역에 메뉴바가 포함될 수 있다 (실측)
            top = min(visibleFrame.maxY, screenFrame.maxY - menuBarThickness) - gap
            centerX = visibleFrame.midX
        }
        let maxX = visibleFrame.maxX - screenMargin - windowWidth
        let x = max(visibleFrame.minX + screenMargin, min(centerX - windowWidth / 2, maxX))
        return CGPoint(x: x, y: top)
    }
}
