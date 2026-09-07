import Foundation
@testable import ScreenTranslate

final class MockTranslationProvider: TranslationProvider {
    let name = "Mock"
    let requiresAPIKey = false

    nonisolated(unsafe) var shouldFail = false
    nonisolated(unsafe) var shouldFailAutoDetect = false
    nonisolated(unsafe) var translatedText = "번역된 텍스트"
    nonisolated(unsafe) var lastReceivedText: String?
    /// 설정되면 다른 조건보다 먼저 이 에러를 던진다 (URLError 등 임의 에러 재현용)
    nonisolated(unsafe) var errorToThrow: Error?

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        lastReceivedText = text
        if let errorToThrow { throw errorToThrow }
        if shouldFailAutoDetect && source == nil {
            throw TranslationError.autoDetectFailed("Mock auto-detect failed")
        }
        if shouldFail { throw TranslationError.translationFailed("Mock 실패") }
        return translatedText
    }
}
