import Foundation
import SwiftData
import XCTest
@testable import ScreenTranslate

final class HistoryStoreTests: XCTestCase {

    /// 경로에 공백을 넣어 `URL.path()` 퍼센트 인코딩 회귀(H2)를 잡는다.
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "HistoryStoreTests \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func sibling(_ url: URL, _ suffix: String) -> URL {
        URL(filePath: url.path(percentEncoded: false) + suffix)
    }

    func test_migrate_copiesLegacyFilesWhenNewStoreMissing() throws {
        let dir = try tempDir()
        let legacy = dir.appending(path: "default.store")
        let new = dir.appending(path: "app/history.store")
        for suffix in ["", "-shm", "-wal"] {
            try Data("legacy\(suffix)".utf8).write(to: sibling(legacy, suffix))
        }

        let migrated = HistoryStore.migrateLegacyStoreIfNeeded(from: legacy, to: new)

        XCTAssertTrue(migrated)
        for suffix in ["", "-wal"] {
            XCTAssertEqual(try String(contentsOf: sibling(new, suffix), encoding: .utf8), "legacy\(suffix)")
        }
        // -shm은 SQLite가 다시 만드는 파일이라 복사하지 않는다
        XCTAssertFalse(FileManager.default.fileExists(atPath: sibling(new, "-shm").path(percentEncoded: false)))
        // 원본은 남겨 둔다
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
    }

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    func test_migrate_neverTouchesExistingStore_evenIfLegacyIsNewer() throws {
        let dir = try tempDir()
        let legacy = dir.appending(path: "default.store")
        let new = dir.appending(path: "history.store")
        try Data("existing".utf8).write(to: new)
        try setModificationDate(Date(timeIntervalSinceNow: -3600), of: new)
        try Data("legacy updated".utf8).write(to: legacy)
        try setModificationDate(Date(), of: legacy)

        let migrated = HistoryStore.migrateLegacyStoreIfNeeded(from: legacy, to: new)

        XCTAssertFalse(migrated, "기존 경로는 다른 앱과 공유될 수 있어 목적지가 있으면 절대 덮어쓰지 않는다")
        XCTAssertEqual(try String(contentsOf: new, encoding: .utf8), "existing")
    }

    func test_migrate_doesNothingWhenLegacyMissing() throws {
        let dir = try tempDir()
        let migrated = HistoryStore.migrateLegacyStoreIfNeeded(
            from: dir.appending(path: "missing.store"),
            to: dir.appending(path: "history.store")
        )
        XCTAssertFalse(migrated)
    }

    @MainActor
    func test_makeContainer_recoversFromCorruptedStore() throws {
        let dir = try tempDir()
        let storeURL = dir.appending(path: "history.store")
        // 손상된 파일: SQLite 헤더가 아닌 쓰레기 데이터
        try Data(repeating: 0x41, count: 512).write(to: storeURL)

        let result = HistoryStore.makeContainer(at: storeURL)

        XCTAssertFalse(result.isInMemory, "손상된 스토어는 삭제 후 재생성되어야 한다")
        let context = ModelContext(result.container)
        context.insert(TranslationRecord(sourceText: "a", translatedText: "b", targetLanguageCode: "ko"))
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<TranslationRecord>())
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func test_makeContainer_persistsAcrossReopen() throws {
        let dir = try tempDir()
        let storeURL = dir.appending(path: "history.store")

        let first = HistoryStore.makeContainer(at: storeURL)
        XCTAssertFalse(first.isInMemory)
        let context = ModelContext(first.container)
        context.insert(TranslationRecord(sourceText: "persist", translatedText: "유지", targetLanguageCode: "ko"))
        try context.save()

        let second = HistoryStore.makeContainer(at: storeURL)
        let count = try ModelContext(second.container).fetchCount(FetchDescriptor<TranslationRecord>())
        XCTAssertEqual(count, 1, "같은 경로를 다시 열면 기록이 남아 있어야 한다")
    }
}
