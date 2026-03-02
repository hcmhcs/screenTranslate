import Foundation

/// 번역을 담당하는 Provider 프로토콜.
/// 새로운 번역 엔진(OpenAI, DeepL, Argos 등)은 이 프로토콜을 채택하면 된다.
protocol TranslationProvider: Sendable {
    /// 텍스트를 번역한다.
    /// - Parameters:
    ///   - text: 번역할 원문
    ///   - source: 소스 언어 (nil이면 자동 감지)
    ///   - target: 타겟 언어
    /// - Returns: 번역된 텍스트
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String

    /// Provider 이름 (설정 UI 표시용)
    var name: String { get }

    /// API Key가 필요한지 여부
    var requiresAPIKey: Bool { get }
}

nonisolated enum TranslationError: LocalizedError {
    case translationFailed(String)
    case languageNotSupported
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .translationFailed(let reason):
            return "번역 실패: \(reason)"
        case .languageNotSupported:
            return "이 언어 조합은 지원되지 않습니다."
        case .apiKeyMissing:
            return "API Key가 설정되지 않았습니다."
        }
    }
}
