import XCTest
@testable import ScreenTranslate

final class MockTranslationProviderTests: XCTestCase {
    private var sut: MockTranslationProvider!

    override func setUp() {
        sut = MockTranslationProvider()
    }

    func test_translate_success_returnsTranslatedText() async throws {
        sut.translatedText = "Hello World"

        let result = try await sut.translate(
            text: "안녕하세요",
            from: Locale.Language(identifier: "ko"),
            to: Locale.Language(identifier: "en")
        )

        XCTAssertEqual(result, "Hello World")
        XCTAssertEqual(sut.lastReceivedText, "안녕하세요")
    }

    func test_translate_failure_throwsError() async {
        sut.shouldFail = true

        do {
            _ = try await sut.translate(text: "test", from: nil, to: Locale.Language(identifier: "ko"))
            XCTFail("실패해야 한다")
        } catch TranslationError.translationFailed {
            // Expected
        } catch {
            XCTFail("예상치 못한 에러: \(error)")
        }
    }
}
