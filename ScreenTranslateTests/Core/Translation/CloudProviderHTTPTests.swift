import Foundation
import XCTest
@testable import ScreenTranslate

/// Google·DeepL·Azure 프로바이더의 요청 구성, 상태 코드 분기, 네트워크 오류 매핑 (실제 네트워크 없음).
@MainActor
final class CloudProviderHTTPTests: XCTestCase {

    private let ko = Locale.Language(identifier: "ko")
    private let en = Locale.Language(identifier: "en")
    private let zhHans = Locale.Language(identifier: "zh-Hans")

    // MARK: - DeepL

    func test_deepL_success_parsesTextAndBuildsRequest() async throws {
        let client = MockHTTPClient.responding(
            status: 200,
            body: #"{"translations":[{"detected_source_language":"ZH","text":"Hello"}]}"#
        )
        let provider = DeepLTranslationProvider(apiKey: "key:fx", client: client)

        let result = try await provider.translate(text: "你好", from: zhHans, to: en)

        XCTAssertEqual(result, "Hello")
        XCTAssertEqual(client.lastRequest?.url?.host, "api-free.deepl.com")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key key:fx")
        XCTAssertEqual(client.lastBodyJSON?["target_lang"] as? String, "EN")
        XCTAssertEqual(client.lastBodyJSON?["source_lang"] as? String, "ZH", "source_lang은 변형 없는 코드여야 한다")
    }

    func test_deepL_403_isAPIKeyError() async {
        let provider = DeepLTranslationProvider(apiKey: "k", client: MockHTTPClient.responding(status: 403, body: ""))
        await assertThrows(provider, expecting: .apiKeyMissing)
    }

    func test_deepL_456_isQuotaError() async {
        let provider = DeepLTranslationProvider(apiKey: "k", client: MockHTTPClient.responding(status: 456, body: ""))
        await assertThrows(provider, expecting: .translationFailed(L10n.quotaExceeded))
    }

    func test_deepL_malformedBody_isInvalidResponse() async {
        let provider = DeepLTranslationProvider(apiKey: "k", client: MockHTTPClient.responding(status: 200, body: "not json"))
        await assertThrows(provider, expecting: .translationFailed(L10n.invalidServerResponse))
    }

    // MARK: - Google

    func test_google_success_parsesTextAndBuildsRequest() async throws {
        let client = MockHTTPClient.responding(
            status: 200,
            body: #"{"data":{"translations":[{"translatedText":"안녕"}]}}"#
        )
        let provider = GoogleTranslationProvider(apiKey: "gkey", client: client)

        let result = try await provider.translate(text: "Hi", from: nil, to: zhHans)

        XCTAssertEqual(result, "안녕")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "x-goog-api-key"), "gkey")
        XCTAssertNil(client.lastRequest?.url?.query, "API 키는 URL 쿼리에 실리면 안 된다")
        XCTAssertEqual(client.lastBodyJSON?["target"] as? String, "zh-CN")
        XCTAssertNil(client.lastBodyJSON?["source"], "자동 감지면 source를 보내지 않는다")
    }

    func test_google_403_isAPIKeyError() async {
        let provider = GoogleTranslationProvider(apiKey: "k", client: MockHTTPClient.responding(status: 403, body: ""))
        await assertThrows(provider, expecting: .apiKeyMissing)
    }

    // MARK: - Azure

    func test_azure_success_parsesTextAndBuildsRequest() async throws {
        let client = MockHTTPClient.responding(
            status: 200,
            body: #"[{"translations":[{"text":"Hola","to":"es"}]}]"#
        )
        let provider = AzureTranslationProvider(apiKey: "akey", region: "koreacentral", client: client)

        let result = try await provider.translate(text: "Hello", from: en, to: Locale.Language(identifier: "es"))

        XCTAssertEqual(result, "Hola")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key"), "akey")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region"), "koreacentral")
        let query = client.lastRequest?.url?.query ?? ""
        XCTAssertTrue(query.contains("to=es"), query)
        XCTAssertTrue(query.contains("from=en"), query)
    }

    func test_azure_401_isAPIKeyError() async {
        let provider = AzureTranslationProvider(apiKey: "k", client: MockHTTPClient.responding(status: 401, body: ""))
        await assertThrows(provider, expecting: .apiKeyMissing)
    }

    func test_azure_403001_isQuotaError() async {
        let client = MockHTTPClient.responding(status: 403, body: #"{"error":{"code":403001,"message":"quota"}}"#)
        let provider = AzureTranslationProvider(apiKey: "k", client: client)
        await assertThrows(provider, expecting: .translationFailed(L10n.quotaExceeded))
    }

    // MARK: - 공통 네트워크 오류 매핑

    func test_offline_mapsToNetworkUnavailable() async {
        let provider = DeepLTranslationProvider(apiKey: "k", client: MockHTTPClient.failing(URLError(.notConnectedToInternet)))
        await assertThrows(provider, expecting: .translationFailed(L10n.networkUnavailable))
    }

    func test_timeout_mapsToNetworkTimedOut() async {
        let provider = GoogleTranslationProvider(apiKey: "k", client: MockHTTPClient.failing(URLError(.timedOut)))
        await assertThrows(provider, expecting: .translationFailed(L10n.networkTimedOut))
    }

    func test_cancelled_isPassedThroughAsURLError() async {
        let provider = AzureTranslationProvider(apiKey: "k", client: MockHTTPClient.failing(URLError(.cancelled)))
        do {
            _ = try await provider.translate(text: "x", from: nil, to: ko)
            XCTFail("throw해야 한다")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled, "취소는 코디네이터가 .idle로 처리하도록 URLError 그대로 전파한다")
        } catch {
            XCTFail("URLError.cancelled여야 한다: \(error)")
        }
    }

    // MARK: - Helper

    private func assertThrows(
        _ provider: TranslationProvider,
        expecting expected: TranslationError,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await provider.translate(text: "x", from: nil, to: ko)
            XCTFail("throw해야 한다", file: file, line: line)
        } catch let error as TranslationError {
            XCTAssertEqual(error.errorDescription, expected.errorDescription, file: file, line: line)
        } catch {
            XCTFail("TranslationError여야 한다: \(error)", file: file, line: line)
        }
    }
}
