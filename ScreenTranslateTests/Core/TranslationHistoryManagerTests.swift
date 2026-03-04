import XCTest
import SwiftData
@testable import ScreenTranslate

@MainActor
final class TranslationHistoryManagerTests: XCTestCase {
    private var container: ModelContainer!
    private var sut: TranslationHistoryManager!

    override func setUp() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: TranslationRecord.self, configurations: config)
        sut = TranslationHistoryManager(modelContainer: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
    }

    // MARK: - 초기 상태

    func test_initialState_hasNoRecords() {
        XCTAssertTrue(sut.recentRecords.isEmpty)
    }

    // MARK: - recordSuccess

    func test_recordSuccess_addsRecord() {
        sut.recordSuccess(
            sourceText: "Hello",
            translatedText: "안녕하세요",
            sourceLanguageCode: "en",
            targetLanguageCode: "ko"
        )

        XCTAssertEqual(sut.recentRecords.count, 1)
        let record = sut.recentRecords[0]
        XCTAssertEqual(record.sourceText, "Hello")
        XCTAssertEqual(record.translatedText, "안녕하세요")
        XCTAssertEqual(record.sourceLanguageCode, "en")
        XCTAssertEqual(record.targetLanguageCode, "ko")
        XCTAssertTrue(record.isSuccess)
    }

    func test_recordSuccess_nilSourceLanguage() {
        sut.recordSuccess(
            sourceText: "Hello",
            translatedText: "안녕하세요",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )

        XCTAssertEqual(sut.recentRecords.count, 1)
        XCTAssertNil(sut.recentRecords[0].sourceLanguageCode)
    }

    // MARK: - recordFailure

    func test_recordFailure_addsRecord() {
        sut.recordFailure(
            sourceText: "Hello",
            errorMessage: "Translation failed",
            targetLanguageCode: "ko"
        )

        XCTAssertEqual(sut.recentRecords.count, 1)
        let record = sut.recentRecords[0]
        XCTAssertEqual(record.sourceText, "Hello")
        XCTAssertEqual(record.errorMessage, "Translation failed")
        XCTAssertFalse(record.isSuccess)
    }

    func test_recordFailure_nilSourceText_savesEmptyString() {
        sut.recordFailure(
            sourceText: nil,
            errorMessage: "OCR failed",
            targetLanguageCode: "ko"
        )

        XCTAssertEqual(sut.recentRecords.count, 1)
        XCTAssertEqual(sut.recentRecords[0].sourceText, "")
    }

    // MARK: - 정렬 (최신 우선)

    func test_multipleRecords_sortedByTimestampDescending() {
        sut.recordSuccess(
            sourceText: "First",
            translatedText: "첫째",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )
        sut.recordSuccess(
            sourceText: "Second",
            translatedText: "둘째",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )
        sut.recordSuccess(
            sourceText: "Third",
            translatedText: "셋째",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )

        XCTAssertEqual(sut.recentRecords.count, 3)
        // 최신 기록이 첫 번째
        XCTAssertEqual(sut.recentRecords[0].sourceText, "Third")
        XCTAssertEqual(sut.recentRecords[1].sourceText, "Second")
        XCTAssertEqual(sut.recentRecords[2].sourceText, "First")
    }

    // MARK: - delete

    func test_delete_removesSingleRecord() {
        sut.recordSuccess(
            sourceText: "A",
            translatedText: "가",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )
        sut.recordSuccess(
            sourceText: "B",
            translatedText: "나",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )

        let recordToDelete = sut.recentRecords.first { $0.sourceText == "A" }!
        sut.delete(recordToDelete)

        XCTAssertEqual(sut.recentRecords.count, 1)
        XCTAssertEqual(sut.recentRecords[0].sourceText, "B")
    }

    // MARK: - deleteAll

    func test_deleteAll_removesAllRecords() {
        sut.recordSuccess(
            sourceText: "A",
            translatedText: "가",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )
        sut.recordSuccess(
            sourceText: "B",
            translatedText: "나",
            sourceLanguageCode: nil,
            targetLanguageCode: "ko"
        )

        sut.deleteAll()

        XCTAssertTrue(sut.recentRecords.isEmpty)
    }

    // MARK: - fetchRecent(limit:)

    func test_fetchRecent_respectsLimit() {
        for i in 1...5 {
            sut.recordSuccess(
                sourceText: "Text \(i)",
                translatedText: "번역 \(i)",
                sourceLanguageCode: nil,
                targetLanguageCode: "ko"
            )
        }

        sut.fetchRecent(limit: 3)

        XCTAssertEqual(sut.recentRecords.count, 3)
    }
}
