import CoreGraphics

/// 영역 캡처의 축소 회색조 지문 — 직전 프레임과 거의 같으면(일시정지·게임 메뉴) 글자 인식을 건너뛴다.
/// 평균이 아니라 **칸마다** 비교한다: 자막은 영역의 일부만 바뀌어서 평균으로는 변화가 묻힌다.
nonisolated struct FrameFingerprint: Equatable, Sendable {
    static let width = 48
    static let height = 12
    let luma: [UInt8]

    init?(image: CGImage) {
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: Self.width, height: Self.height,
                bitsPerComponent: 8, bytesPerRow: Self.width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
            return true
        }
        guard drawn else { return nil }
        luma = pixels
    }

    /// 모든 칸의 밝기 차가 tolerance 이하이면 같은 화면으로 본다
    func isNearlyIdentical(to other: FrameFingerprint, tolerance: UInt8 = 8) -> Bool {
        guard luma.count == other.luma.count else { return false }
        for index in luma.indices where abs(Int(luma[index]) - Int(other.luma[index])) > Int(tolerance) {
            return false
        }
        return true
    }
}
