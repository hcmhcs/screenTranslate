import Foundation

/// 실시간 번역 텔레메트리 값 — 정확한 시간 대신 구간만 보낸다
enum LiveTelemetry {
    static func durationBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "<1m"
        case ..<600: "1-10m"
        case ..<1800: "10-30m"
        default: "30m+"
        }
    }

    static func reasonName(_ reason: LiveTranslationSession.StopReason) -> String {
        switch reason {
        case .user: "user"
        case .screenLocked: "screenLocked"
        case .displayRemoved: "displayRemoved"
        case .betaDisabled: "betaDisabled"
        case .captureFailed: "captureFailed"
        }
    }
}
