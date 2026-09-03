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

    func test_cancel_returnsToIdle() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.translatedText = "안녕"
        sut.startProcessing(image: makeBlankImage())
        _ = await waitForTerminalState(sut)

        sut.cancel()

        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - C1: 취소된 이전 실행이 새 실행의 상태를 덮어쓰면 안 된다

    func test_cancelledPreviousRun_doesNotOverwriteNewRunState() async {
        let gated = GatedTranslationProvider()
        sut.updateProvider(gated)

        sut.startProcessing(text: "first")
        await waitUntil { gated.pendingCount == 1 }

        // 두 번째 실행 시작 → 첫 실행의 Task는 cancel()되지만 translate()에 매달려 있다
        sut.startProcessing(text: "second")
        await waitUntil { gated.pendingCount == 2 }
        XCTAssertEqual(sut.state, .translating)

        // 첫 실행이 뒤늦게 "밀려남"으로 깨어난다 (실제 TranslationBridge 동작)
        gated.resumeFirst(with: .failure(TranslationError.superseded))
        await waitUntil { gated.completedCalls == 1 }  // 첫 실행의 catch가 처리된 뒤

        // 새 실행의 상태(.translating)가 .idle/.failed로 덮어써지면 안 된다
        XCTAssertEqual(sut.state, .translating)

        gated.resumeFirst(with: .success("두 번째"))
        let state = await waitForTerminalState(sut)
        if case .completed(let result) = state {
            XCTAssertEqual(result.translatedText, "두 번째")
        } else {
            XCTFail("completed 상태여야 한다: \(state)")
        }
    }

    func test_cancel_thenLateFailure_staysIdle() async {
        let gated = GatedTranslationProvider()
        sut.updateProvider(gated)

        sut.startProcessing(text: "first")
        await waitUntil { gated.pendingCount == 1 }

        sut.cancel()
        XCTAssertEqual(sut.state, .idle)

        // 취소 후 뒤늦게 실패로 깨어나도 .failed로 바뀌면 안 된다
        gated.resumeFirst(with: .failure(TranslationError.translationFailed("late")))
        await waitUntil { gated.completedCalls == 1 }
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - M11: URLError.cancelled는 취소로 처리

    func test_urlErrorCancelled_isTreatedAsCancellation() async {
        mockTranslation.errorToThrow = URLError(.cancelled)

        sut.startProcessing(text: "Hello")
        let state = await waitForTerminalState(sut)

        XCTAssertEqual(state, .idle, "URLError.cancelled는 실패가 아니라 취소로 처리해야 한다")
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        file: StaticString = #file, line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("waitUntil 타임아웃", file: file, line: line)
    }

    func test_process_passesDetectedLanguageToTranslation() async {
        mockOCR.recognizedText = "Hello"
        mockOCR.detectedLanguage = Locale.Language(identifier: "en")
        mockTranslation.translatedText = "안녕"

        sut.startProcessing(image: makeBlankImage())
        _ = await waitForTerminalState(sut)

        XCTAssertEqual(mockTranslation.lastReceivedText, "Hello")
    }

    // MARK: - startProcessing(text:) 드래그 번역

    func test_processText_success_reachesCompletedState() async {
        mockTranslation.translatedText = "안녕하세요"

        sut.startProcessing(text: "Hello")
        let state = await waitForTerminalState(sut)

        if case .completed(let result) = state {
            XCTAssertEqual(result.translatedText, "안녕하세요")
            XCTAssertEqual(result.sourceText, "Hello")
            XCTAssertFalse(result.lowConfidence)
        } else {
            XCTFail("completed 상태여야 한다: \(state)")
        }
    }

    func test_processText_skipsRecognizingState() async {
        mockTranslation.translatedText = "번역됨"

        sut.startProcessing(text: "Test")

        // 즉시 .translating이어야 함 (.recognizing 스킵)
        XCTAssertEqual(sut.state, .translating)

        _ = await waitForTerminalState(sut)
    }

    func test_processText_translationFails_reachesFailedState() async {
        mockTranslation.shouldFail = true

        sut.startProcessing(text: "Hello")
        let state = await waitForTerminalState(sut)

        if case .failed = state {
            // Expected
        } else {
            XCTFail("실패 상태여야 한다: \(state)")
        }
    }

    func test_processText_emptyText_reachesFailedState() async {
        sut.startProcessing(text: "")
        let state = await waitForTerminalState(sut)

        if case .failed(let msg) = state {
            XCTAssertEqual(msg, L10n.noSelectedText)
        } else {
            XCTFail("실패 상태여야 한다: \(state)")
        }
    }

    func test_processText_passesSourceLanguageToTranslation() async {
        mockTranslation.translatedText = "번역됨"
        sut.sourceLanguage = Locale.Language(identifier: "en")

        sut.startProcessing(text: "Hello world")
        _ = await waitForTerminalState(sut)

        XCTAssertEqual(mockTranslation.lastReceivedText, "Hello world")
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

    // MARK: - 자동 감지 실패

    func test_process_autoDetectFailed_showsUserFriendlyMessage() async {
        mockOCR.recognizedText = "Hi"
        mockOCR.detectedLanguage = nil
        mockTranslation.shouldFailAutoDetect = true
        sut.sourceLanguage = nil

        sut.startProcessing(image: makeBlankImage())
        let state = await waitForTerminalState(sut)

        if case .failed(let msg) = state {
            XCTAssertEqual(msg, L10n.autoDetectFailedMessage)
        } else {
            XCTFail("자동 감지 실패 상태여야 한다: \(state)")
        }
    }

    func test_processText_autoDetectFailed_showsUserFriendlyMessage() async {
        mockTranslation.shouldFailAutoDetect = true
        sut.sourceLanguage = nil

        sut.startProcessing(text: "Hi")
        let state = await waitForTerminalState(sut)

        if case .failed(let msg) = state {
            XCTAssertEqual(msg, L10n.autoDetectFailedMessage)
        } else {
            XCTFail("자동 감지 실패 상태여야 한다: \(state)")
        }
    }

    func test_processText_manualLanguage_doesNotTriggerAutoDetectError() async {
        mockTranslation.shouldFailAutoDetect = true
        sut.sourceLanguage = Locale.Language(identifier: "en")

        sut.startProcessing(text: "Hello")
        let state = await waitForTerminalState(sut)

        if case .completed = state {
            // source가 nil이 아니므로 shouldFailAutoDetect 조건 불일치 → 성공
        } else {
            XCTFail("수동 언어 지정 시 정상 번역되어야 한다: \(state)")
        }
    }

    // MARK: - AsyncStream

    func test_stateStream_yieldsStateChanges() async {
        mockTranslation.translatedText = "번역됨"

        var receivedStates: [TranslationCoordinator.State] = []
        let expectation = XCTestExpectation(description: "stateStream completes")

        let task = Task {
            for await state in sut.makeStateStream() {
                receivedStates.append(state)
                if case .completed = state { break }
            }
            expectation.fulfill()
        }

        // 약간의 지연 후 번역 시작 (스트림 구독 완료 대기)
        try? await Task.sleep(for: .milliseconds(10))
        sut.startProcessing(text: "Hello")

        await fulfillment(of: [expectation], timeout: 5)
        task.cancel()

        // idle(초기) → translating → completed 순서
        XCTAssertTrue(receivedStates.contains(where: { $0 == .translating }))
        XCTAssertTrue(receivedStates.contains(where: {
            if case .completed = $0 { return true }
            return false
        }))
    }

    // MARK: - Helpers

    private func waitForTerminalState(_ coordinator: TranslationCoordinator) async -> TranslationCoordinator.State {
        await TestHelpers.waitForTerminalState(coordinator)
    }

    private func makeBlankImage() -> CGImage {
        TestHelpers.makeBlankImage()
    }
}
