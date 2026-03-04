import CoreGraphics
import XCTest
@testable import ScreenTranslate

enum TestHelpers {

    /// 10x10 빈 CGImage를 생성한다. OCR 테스트용.
    static func makeBlankImage() -> CGImage {
        guard let context = CGContext(
            data: nil, width: 10, height: 10,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            fatalError("테스트용 CGImage 생성 실패 — 그래픽 컨텍스트 환경 문제")
        }
        return image
    }

    /// TranslationCoordinator가 터미널 상태(completed/failed/idle)에 도달할 때까지
    /// 최대 timeout 동안 10ms 간격으로 폴링한다. 타임아웃 시 XCTFail을 호출한다.
    @MainActor
    static func waitForTerminalState(
        _ coordinator: TranslationCoordinator,
        timeout: Duration = .seconds(2),
        file: StaticString = #file,
        line: UInt = #line
    ) async -> TranslationCoordinator.State {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let state = coordinator.state
            switch state {
            case .completed, .failed, .idle:
                return state
            case .recognizing, .translating:
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        XCTFail("waitForTerminalState 타임아웃 (\(timeout)) — 현재 상태: \(coordinator.state)", file: file, line: line)
        return coordinator.state
    }
}
