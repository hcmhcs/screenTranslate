import Foundation
@testable import ScreenTranslate

final class MockTranslationProvider: TranslationProvider {
    let name = "Mock"
    let requiresAPIKey = false

    nonisolated(unsafe) var shouldFail = false
    nonisolated(unsafe) var translatedText = "번역된 텍스트"
    nonisolated(unsafe) var lastReceivedText: String?

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        lastReceivedText = text
        if shouldFail { throw TranslationError.translationFailed("Mock 실패") }
        return translatedText
    }
}
