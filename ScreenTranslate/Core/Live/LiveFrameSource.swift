import CoreGraphics

/// 실시간 번역이 지켜보는 영역 — 기존 영역 선택 오버레이와 같은 좌표(화면 로컬, 좌상단 원점, 포인트)
nonisolated struct LiveRegion: Equatable, Sendable {
    var rect: CGRect
    var displayID: CGDirectDisplayID
    var scale: CGFloat
}

/// 영역 한 장을 캡처하는 쪽 — 운영은 ScreenCaptureKit, 테스트는 가짜.
/// 캡처 방식을 바꿀 때(예: SCStream) 이 경계만 교체한다.
protocol LiveFrameSource: AnyObject {
    func captureFrame(of region: LiveRegion) async throws -> CGImage
}
