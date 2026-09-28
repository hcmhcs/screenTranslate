import Foundation
import Testing
@testable import ScreenTranslate

/// 실시간 번역 텔레메트리 값 — 정확한 시간 대신 구간만 보낸다.
@MainActor
@Suite struct LiveTelemetryTests {

    @Test("durations are bucketed", arguments: [
        (30.0, "<1m"), (300.0, "1-10m"), (1200.0, "10-30m"), (7200.0, "30m+"),
    ])
    func buckets(seconds: Double, expected: String) {
        #expect(LiveTelemetry.durationBucket(seconds) == expected)
    }

    @Test("stop reasons have stable names")
    func reasonNames() {
        #expect(LiveTelemetry.reasonName(.user) == "user")
        #expect(LiveTelemetry.reasonName(.captureFailed("x")) == "captureFailed")
    }
}
