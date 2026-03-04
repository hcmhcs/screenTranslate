import XCTest
import CoreGraphics
@testable import ScreenTranslate

@MainActor
final class TranslationCoordinatorTests: XCTestCase {
    private var mockOCR: MockOCRProvider!
    private var mockTranslation: MockTranslationProvider!
    private var sut: TranslationCoordinator!

    override func setUp() {
        mockOCR = MockOCRProvider()
        mockTranslation = MockTranslationProvider()
        sut = TranslationCoordinator(
            ocrProvider: mockOCR,
            translationProvider: mockTranslation,
            targetLanguage: Locale.Language(identifier: "ko")
        )
    }

    func test_process_success_reachesCompletedState() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.translatedText = "안녕하세요"

        sut.startProcessing(image: makeBlankImage())
        let state = await waitForTerminalState(sut)

        if case .completed(let result) = state {
            XCTAssertEqual(result.translatedText, "안녕하세요")
            XCTAssertFalse(result.lowConfidence)
        } else {
            XCTFail("completed 상태여야 한다: \(state)")
        }
    }

    func test_process_lowConfidence_setsFlag() async {
        mockOCR.recognizedText = "Hello"
        mockOCR.confidence = 0.2  // < 0.3
        mockTranslation.translatedText = "안녕하세요"

        sut.startProcessing(image: makeBlankImage())
        let state = await waitForTerminalState(sut)

        if case .completed(let result) = state {
            XCTAssertTrue(result.lowConfidence)
        } else {
            XCTFail("completed 상태여야 한다: \(state)")
        }
    }

    func test_process_ocrFails_reachesFailedState() async {
        mockOCR.shouldFail = true

        sut.startProcessing(image: makeBlankImage())
        let state = await waitForTerminalState(sut)

        if case .failed(let msg) = state {
            XCTAssertEqual(msg, L10n.noTextFound)
        } else {
            XCTFail("실패 상태여야 한다: \(state)")
        }
    }

    func test_process_translationFails_reachesFailedState() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.shouldFail = true

        sut.startProcessing(image: makeBlankImage())
        let state = await waitForTerminalState(sut)

        if case .failed = state {
            // Expected
        } else {
            XCTFail("실패 상태여야 한다: \(state)")
        }
    }

    func test_reset_returnsToIdle() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.translatedText = "안녕"
        sut.startProcessing(image: makeBlankImage())
        _ = await waitForTerminalState(sut)

        sut.reset()

        XCTAssertEqual(sut.state, .idle)
    }

    func test_process_passesDetectedLanguageToTranslation() async {
        mockOCR.recognizedText = "Hello"
        mockOCR.detectedLanguage = Locale.Language(identifier: "en")
        mockTranslation.translatedText = "안녕"

        sut.startProcessing(image: makeBlankImage())
        _ = await waitForTerminalState(sut)

        XCTAssertEqual(mockTranslation.lastReceivedText, "Hello")
    }

    // MARK: - preprocessOCRText 단락 감지 테스트

    func test_preprocessOCRText_preservesParagraphBreaks() {
        // 짧은 줄 + 마침표 → 단락으로 감지
        let input = """
        This is a line that fills the full width of text.
        End of paragraph one.
        This is the start of a second paragraph that is long.
        """
        let result = TranslationCoordinator.preprocessOCRText(input)
        XCTAssertTrue(result.contains("\n\n"), "단락 구분이 보존되어야 한다")
    }

    func test_preprocessOCRText_mergesWordWrapLines() {
        // 비슷한 길이 + 종결부호 없음 → 줄바꿈 병합
        let input = "This is a long line that wraps at\nthe edge and continues here."
        let result = TranslationCoordinator.preprocessOCRText(input)
        XCTAssertFalse(result.contains("\n"), "줄바꿈이 공백으로 병합되어야 한다")
    }

    func test_preprocessOCRText_shortTextNoHeuristic() {
        // 2줄 이하 → 휴리스틱 미적용
        let input = "Short.\nNext."
        let result = TranslationCoordinator.preprocessOCRText(input)
        XCTAssertFalse(result.contains("\n"), "2줄 텍스트는 휴리스틱 미적용")
    }

    func test_preprocessOCRText_cjkParagraphBreaks() {
        // CJK 문장 종결 + 짧은 줄
        let input = "이것은 첫 번째 단락의 긴 문장입니다 테스트용으로 길게 작성합니다\n첫 번째 단락 끝。\n두 번째 단락이 여기서 시작됩니다 이것도 길게 작성합니다"
        let result = TranslationCoordinator.preprocessOCRText(input)
        XCTAssertTrue(result.contains("\n\n"), "CJK 단락 구분이 보존되어야 한다")
    }

    // MARK: - preprocessOCRText 리스트 감지 테스트

    func test_preprocessOCRText_preservesBulletListBreaks() {
        let input = """
        • Completely Private - On-device by default. No servers, no tracking
        • Instant Translation - One shortcut triggers area selection and OCR
        • 18 Languages - Korean, English, Japanese, Chinese, and 14 more
        """
        let result = TranslationCoordinator.preprocessOCRText(input)
        let lines = result.components(separatedBy: "\n\n")
        XCTAssertEqual(lines.count, 3, "불릿 항목 사이에 줄바꿈이 보존되어야 한다")
    }

    func test_preprocessOCRText_preservesNumberedListBreaks() {
        let input = """
        1. First item description here
        2. Second item description here
        3. Third item description here
        """
        let result = TranslationCoordinator.preprocessOCRText(input)
        let lines = result.components(separatedBy: "\n\n")
        XCTAssertEqual(lines.count, 3, "번호 리스트 항목 사이에 줄바꿈이 보존되어야 한다")
    }

    func test_preprocessOCRText_nonListDashNotDetected() {
        // 불릿이 아닌 하이픈 사용 (공백 없이 단어 시작)
        let input = "This is a normal line with\n-no bullet here just a dash"
        let result = TranslationCoordinator.preprocessOCRText(input)
        XCTAssertFalse(result.contains("\n\n"), "불릿이 아닌 하이픈은 리스트로 감지하면 안 된다")
    }

    // MARK: - Helpers

    private func waitForTerminalState(_ coordinator: TranslationCoordinator) async -> TranslationCoordinator.State {
        await TestHelpers.waitForTerminalState(coordinator)
    }

    private func makeBlankImage() -> CGImage {
        TestHelpers.makeBlankImage()
    }
}
