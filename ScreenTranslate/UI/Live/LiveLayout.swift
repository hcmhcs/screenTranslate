import CoreGraphics

/// 실시간 번역 창들의 배치 계산 — AppKit 없이 테스트한다.
/// 영역 좌표는 화면 로컬·좌상단 원점(오버레이와 같음), 프레임은 AppKit 전역·좌하단 원점.
nonisolated enum LiveLayout {
    static let barGap: CGFloat = 6
    static let barMinWidth: CGFloat = 280
    static let screenMargin: CGFloat = 16
    static let minRegionSize = CGSize(width: 80, height: 24)

    static func globalFrame(of rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + rect.minX, y: screenFrame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    static func subtitleBarWidth(regionWidth: CGFloat, visibleFrame: CGRect) -> CGFloat {
        min(max(regionWidth, barMinWidth), visibleFrame.width - screenMargin * 2)
    }

    /// 영역 아래에 두고, 아래 공간이 없으면 툴바 위로 올린다. 가로는 화면 안으로 제한.
    static func subtitleBarFrame(regionFrame: CGRect, barSize: CGSize, toolbarHeight: CGFloat,
                                 visibleFrame: CGRect) -> CGRect {
        let x = min(max(regionFrame.midX - barSize.width / 2, visibleFrame.minX + screenMargin),
                    visibleFrame.maxX - screenMargin - barSize.width)
        let below = regionFrame.minY - barGap - barSize.height
        let y = below >= visibleFrame.minY
            ? below
            : min(regionFrame.maxY + toolbarHeight + barGap, visibleFrame.maxY - barSize.height)
        return CGRect(x: x, y: y, width: barSize.width, height: barSize.height)
    }

    /// 툴바 드래그로 이동 — delta는 화면 로컬 방향(아래로 끌면 +y)
    static func moved(_ rect: CGRect, by delta: CGSize, within screenSize: CGSize) -> CGRect {
        var result = rect.offsetBy(dx: delta.width, dy: delta.height)
        result.origin.x = min(max(0, result.origin.x), screenSize.width - result.width)
        result.origin.y = min(max(0, result.origin.y), screenSize.height - result.height)
        return result
    }

    /// 오른쪽 아래 손잡이로 크기 조절 — 최소 크기, 화면 끝까지
    static func resized(_ rect: CGRect, by delta: CGSize, within screenSize: CGSize) -> CGRect {
        var result = rect
        result.size.width = min(max(minRegionSize.width, rect.width + delta.width), screenSize.width - rect.minX)
        result.size.height = min(max(minRegionSize.height, rect.height + delta.height), screenSize.height - rect.minY)
        return result
    }
}
