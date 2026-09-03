import SwiftData
import XCTest
@testable import ScreenTranslate

@MainActor
final class QuickTranslateModelTests: XCTestCase {
    private var provider: MockTranslationProvider!
    private var coordinator: TranslationCoordinator!
    private var container: ModelContainer!
    private var history: TranslationHistoryManager!
    private var copied: [String] = []
    private var telemetryEvents: [String] = []
    private var autoCopy = true

    override func setUp() async throws {
        provider = MockTranslationProvider()
        coordinator = TranslationCoordinator(
            ocrProvider: MockOCRProvider(),
            translationProvider: provider,
            targetLanguage: Locale.Language(identifier: "ko")
        )
        container = try ModelContainer(
            for: TranslationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        history = TranslationHistoryManager(modelContainer: container)
        copied = []
        telemetryEvents = []
        autoCopy = true
    }

    private func makeModel(source: String = "en", target: String = "ko") -> QuickTranslateModel {
        QuickTranslateModel(
            coordinator: coordinator,
            historyManager: history,
            sourceLanguageCode: source,
            targetLanguageCode: target,
            autoCopyEnabled: { [unowned self] in self.autoCopy },
            copyToClipboard: { [unowned self] in self.copied.append($0) },
            telemetry: { [unowned self] in self.telemetryEvents.append($0) }
        )
    }

    func test_translate_emptyInput_doesNothing() async {
        let model = makeModel()
        model.inputText = "   \n"

        model.translate()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(provider.lastReceivedText)
    }

    func test_translate_success_recordsHistoryAndAutoCopies() async {
        provider.translatedText = "안녕"
        let model = makeModel()
        model.inputText = "Hello"

        model.translate()
        _ = await TestHelpers.waitForTerminalState(coordinator)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(provider.lastReceivedText, "Hello")
        XCTAssertEqual(history.recentRecords.count, 1)
        XCTAssertEqual(history.recentRecords.first?.translatedText, "안녕")
        XCTAssertEqual(copied, ["안녕"])
        XCTAssertTrue(model.didCopyResult)
        XCTAssertEqual(telemetryEvents, ["Mock"])
    }

    func test_translate_autoCopyOff_doesNotCopy() async {
        autoCopy = false
        provider.translatedText = "안녕"
        let model = makeModel()
        model.inputText = "Hello"

        model.translate()
        _ = await TestHelpers.waitForTerminalState(coordinator)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(copied.isEmpty)
        XCTAssertFalse(model.didCopyResult)
        XCTAssertEqual(history.recentRecords.count, 1)
    }

    func test_translate_failure_recordsFailure() async {
        provider.shouldFail = true
        let model = makeModel()
        model.inputText = "Hello"

        model.translate()
        _ = await TestHelpers.waitForTerminalState(coordinator)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(history.recentRecords.count, 1)
        XCTAssertFalse(history.recentRecords.first?.isSuccess ?? true)
        XCTAssertTrue(copied.isEmpty)
    }

    func test_translate_usesSelectedLanguages() async {
        let model = makeModel(source: "auto", target: "ja")
        model.inputText = "Hello"

        model.translate()
        _ = await TestHelpers.waitForTerminalState(coordinator)

        XCTAssertNil(coordinator.sourceLanguage, "auto는 nil(자동 감지)로 전달")
        XCTAssertEqual(coordinator.targetLanguage.minimalIdentifier, "ja")
    }

    func test_swapLanguages_autoSource_isIgnored() {
        let model = makeModel(source: "auto", target: "ko")

        model.swapLanguages()

        XCTAssertEqual(model.sourceLanguageCode, "auto")
        XCTAssertEqual(model.targetLanguageCode, "ko")
    }

    func test_swapLanguages_afterCompletion_movesResultToInput() async {
        provider.translatedText = "안녕"
        let model = makeModel(source: "en", target: "ko")
        model.inputText = "Hello"
        model.translate()
        _ = await TestHelpers.waitForTerminalState(coordinator)

        model.swapLanguages()

        XCTAssertEqual(model.sourceLanguageCode, "ko")
        XCTAssertEqual(model.targetLanguageCode, "en")
        XCTAssertEqual(model.inputText, "안녕")
        XCTAssertEqual(coordinator.state, .idle)
    }

    func test_copyResult_onlyWhenCompleted() async {
        provider.translatedText = "안녕"
        let model = makeModel()

        model.copyResult()
        XCTAssertTrue(copied.isEmpty, "결과가 없으면 복사하지 않는다")

        autoCopy = false
        model.inputText = "Hello"
        model.translate()
        _ = await TestHelpers.waitForTerminalState(coordinator)
        try? await Task.sleep(for: .milliseconds(30))

        model.copyResult()
        XCTAssertEqual(copied, ["안녕"])
        XCTAssertTrue(model.didCopyResult)
    }

    func test_resetForNewSession_clearsTextButKeepsLanguages() async {
        provider.translatedText = "안녕"
        let model = makeModel(source: "en", target: "ko")
        model.inputText = "Hello"
        model.translate()
        _ = await TestHelpers.waitForTerminalState(coordinator)

        model.resetForNewSession()

        XCTAssertEqual(model.inputText, "")
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(model.didCopyResult)
        XCTAssertEqual(model.sourceLanguageCode, "en")
        XCTAssertEqual(model.targetLanguageCode, "ko")
    }
}
