import XCTest
@testable import ScreenTranslate

/// 실제 번역 API를 호출하는 통합 테스트.
/// API 키가 환경변수에 없으면 자동으로 스킵된다 (CI 안전).
///
/// 로컬 실행 방법:
///   export DEEPL_API_KEY="your-key"
///   export GOOGLE_CLOUD_API_KEY="your-key"
///   export AZURE_API_KEY="your-key"
final class TranslationEngineIntegrationTests: XCTestCase {

    // MARK: - DeepL

    func test_deepL_translatesKoreanToEnglish() async throws {
        let apiKey = ProcessInfo.processInfo.environment["DEEPL_API_KEY"]
        try XCTSkipIf(apiKey == nil, "DEEPL_API_KEY 환경변수 없음 — 통합 테스트 스킵")

        let provider = DeepLTranslationProvider(apiKey: apiKey!)
        let result = try await provider.translate(
            text: "안녕하세요",
            from: Locale.Language(identifier: "ko"),
            to: Locale.Language(identifier: "en")
        )
        XCTAssertFalse(result.isEmpty, "번역 결과가 비어있으면 안 된다")
    }

    func test_deepL_translatesEnglishToKorean() async throws {
        let apiKey = ProcessInfo.processInfo.environment["DEEPL_API_KEY"]
        try XCTSkipIf(apiKey == nil, "DEEPL_API_KEY 환경변수 없음 — 통합 테스트 스킵")

        let provider = DeepLTranslationProvider(apiKey: apiKey!)
        let result = try await provider.translate(
            text: "Hello",
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "ko")
        )
        XCTAssertFalse(result.isEmpty, "번역 결과가 비어있으면 안 된다")
    }

    // MARK: - Google Cloud

    func test_google_translatesKoreanToEnglish() async throws {
        let apiKey = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_API_KEY"]
        try XCTSkipIf(apiKey == nil, "GOOGLE_CLOUD_API_KEY 환경변수 없음 — 통합 테스트 스킵")

        let provider = GoogleTranslationProvider(apiKey: apiKey!)
        let result = try await provider.translate(
            text: "안녕하세요",
            from: Locale.Language(identifier: "ko"),
            to: Locale.Language(identifier: "en")
        )
        XCTAssertFalse(result.isEmpty, "번역 결과가 비어있으면 안 된다")
    }

    func test_google_translatesEnglishToKorean() async throws {
        let apiKey = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_API_KEY"]
        try XCTSkipIf(apiKey == nil, "GOOGLE_CLOUD_API_KEY 환경변수 없음 — 통합 테스트 스킵")

        let provider = GoogleTranslationProvider(apiKey: apiKey!)
        let result = try await provider.translate(
            text: "Hello",
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "ko")
        )
        XCTAssertFalse(result.isEmpty, "번역 결과가 비어있으면 안 된다")
    }

    // MARK: - Microsoft Azure

    func test_azure_translatesKoreanToEnglish() async throws {
        let apiKey = ProcessInfo.processInfo.environment["AZURE_API_KEY"]
        try XCTSkipIf(apiKey == nil, "AZURE_API_KEY 환경변수 없음 — 통합 테스트 스킵")

        let provider = AzureTranslationProvider(apiKey: apiKey!)
        let result = try await provider.translate(
            text: "안녕하세요",
            from: Locale.Language(identifier: "ko"),
            to: Locale.Language(identifier: "en")
        )
        XCTAssertFalse(result.isEmpty, "번역 결과가 비어있으면 안 된다")
    }

    func test_azure_translatesEnglishToKorean() async throws {
        let apiKey = ProcessInfo.processInfo.environment["AZURE_API_KEY"]
        try XCTSkipIf(apiKey == nil, "AZURE_API_KEY 환경변수 없음 — 통합 테스트 스킵")

        let provider = AzureTranslationProvider(apiKey: apiKey!)
        let result = try await provider.translate(
            text: "Hello",
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "ko")
        )
        XCTAssertFalse(result.isEmpty, "번역 결과가 비어있으면 안 된다")
    }
}
