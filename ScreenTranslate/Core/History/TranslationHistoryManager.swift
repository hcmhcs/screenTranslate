import Foundation
import Observation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.app.screentranslate", category: "history")

@MainActor
@Observable
final class TranslationHistoryManager {
    private let modelContext: ModelContext

    /// 최근 기록 (UI 바인딩용)
    var recentRecords: [TranslationRecord] = []

    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
        fetchRecent()
    }

    // MARK: - 기록

    /// 번역 성공 기록
    func recordSuccess(
        sourceText: String,
        translatedText: String,
        sourceLanguageCode: String?,
        targetLanguageCode: String
    ) {
        let record = TranslationRecord(
            sourceText: sourceText,
            translatedText: translatedText,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode
        )
        modelContext.insert(record)
        save()
        trimOldRecords()
        fetchRecent()
        logger.debug("히스토리 기록 (성공): \"\(sourceText.prefix(30))...\"")
    }

    /// 번역 실패 기록
    func recordFailure(
        sourceText: String?,
        errorMessage: String,
        targetLanguageCode: String
    ) {
        let record = TranslationRecord(
            sourceText: sourceText ?? "",
            errorMessage: errorMessage,
            targetLanguageCode: targetLanguageCode
        )
        modelContext.insert(record)
        save()
        trimOldRecords()
        fetchRecent()
        logger.debug("히스토리 기록 (실패): \(errorMessage)")
    }

    // MARK: - 조회

    func fetchRecent(limit: Int = 50) {
        var descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        recentRecords = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - 삭제

    func delete(_ record: TranslationRecord) {
        modelContext.delete(record)
        save()
        fetchRecent()
    }

    func deleteAll() {
        do {
            try modelContext.delete(model: TranslationRecord.self)
            save()
            recentRecords = []
            logger.debug("히스토리 전체 삭제")
        } catch {
            logger.error("히스토리 전체 삭제 실패: \(error)")
        }
    }

    // MARK: - Private

    private func save() {
        do {
            try modelContext.save()
        } catch {
            logger.error("히스토리 저장 실패: \(error)")
        }
    }

    /// 최근 N개만 유지하고 나머지를 삭제한다.
    /// UI에서 접근할 수 없는 오래된 기록이 무한히 쌓이는 것을 방지.
    private func trimOldRecords(keep: Int = 50) {
        var descriptor = FetchDescriptor<TranslationRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchOffset = keep
        guard let old = try? modelContext.fetch(descriptor), !old.isEmpty else { return }
        for record in old {
            modelContext.delete(record)
        }
        save()
        logger.debug("히스토리 자동 정리: \(old.count)건 삭제")
    }
}
