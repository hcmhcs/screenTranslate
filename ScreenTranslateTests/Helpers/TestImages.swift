import CoreGraphics

/// 실시간 번역 테스트용 이미지 — 회색 바탕에 흰 사각형(글자 대신)을 그린다
enum TestImages {
    static func gray(_ level: UInt8, width: Int = 96, height: Int = 24) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(gray: CGFloat(level) / 255, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// x 위치에 흰 사각형이 있는 이미지 — 위치를 바꾸면 "자막이 바뀐 화면"이 된다
    static func block(at x: Int, width: Int = 96, height: Int = 24, blockWidth: Int = 16) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(gray: 0.2, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: blockWidth, height: height))
        }
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        body(context)
        return context.makeImage()!
    }
}
