import Foundation
import Synchronization
import Translation
import XCTest
@testable import ScreenTranslate

/// 언어 쌍 테이블로 LanguageAvailability를 흉내 낸다.
final class MockLanguageStatusChecker: LanguageStatusChecking, @unchecked Sendable {
    private let installedPairs: Set<Set<String>>
    private let unsupported: Set<String>
    private let callCounter = Mutex(0)

    init(installedPairs: [Set<String>] = [], unsupported: Set<String> = []) {
        self.installedPairs = Set(installedPairs)
        self.unsupported = unsupported
    }

    var callCount: Int { callCounter.withLock { $0 } }

    func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        callCounter.withLock { $0 += 1 }
        let a = source.minimalIdentifier
        let b = target.minimalIdentifier
        if unsupported.contains(a) || unsupported.contains(b) { return .unsupported }
        if installedPairs.contains([a, b]) { return .installed }
        return .supported
    }
}

@MainActor
final class LanguagePackManagerTests: XCTestCase {

    func test_englishInstalled_classifiesEachLanguage() async {
        let checker = MockLanguageStatusChecker(installedPairs: [["en", "ko"]], unsupported: ["xx"])
        let manager = LanguagePackManager(checker: checker, languageCodes: ["en", "ko", "ja", "xx"])

        await manager.refreshAllStatuses()

        XCTAssertEqual(manager.languageStatuses["en"], .installed)
        XCTAssertEqual(manager.languageStatuses["ko"], .installed)
        XCTAssertEqual(manager.languageStatuses["ja"], .available)
        XCTAssertEqual(manager.languageStatuses["xx"], .unsupported)
        XCTAssertEqual(manager.languageStatuses.count, 4)
    }

    func test_noEnglish_fallsBackToCrossCheck() async {
        let checker = MockLanguageStatusChecker(installedPairs: [["ko", "ja"]])
        let manager = LanguagePackManager(checker: checker, languageCodes: ["en", "ko", "ja"])

        await manager.refreshAllStatuses()

        XCTAssertEqual(manager.languageStatuses["ko"], .installed)
        XCTAssertEqual(manager.languageStatuses["ja"], .installed)
        XCTAssertEqual(manager.languageStatuses["en"], .available)
    }

    func test_nothingInstalled_everythingAvailable() async {
        let checker = MockLanguageStatusChecker()
        let manager = LanguagePackManager(checker: checker, languageCodes: ["en", "ko", "ja"])

        await manager.refreshAllStatuses()

        XCTAssertEqual(manager.languageStatuses.values.filter { $0 == .available }.count, 3)
        XCTAssertNil(manager.findInstalledLanguage(excluding: "ko"))
    }

    func test_fastPath_callCountStaysLinear() async {
        // 실제 언어 코드를 써야 Locale.Language 정규화(minimalIdentifier)가 흔들리지 않는다
        let codes = ["en", "ko", "ja", "zh", "fr", "de", "es", "it", "pt", "ru", "ar",
                     "hi", "th", "vi", "id", "tr", "pl", "nl", "uk", "sv", "ro"]
        let checker = MockLanguageStatusChecker(installedPairs: [["en", "ko"]])
        let manager = LanguagePackManager(checker: checker, languageCodes: codes)

        await manager.refreshAllStatuses()

        // Phase 1: 20회, Phase 2: 미설치 19개 → 39회. 교차 확인(최대 420회)에 빠지면 안 된다.
        XCTAssertLessThanOrEqual(checker.callCount, 40, "호출 \(checker.callCount)회")
        XCTAssertEqual(manager.languageStatuses["ko"], .installed)
        XCTAssertEqual(manager.languageStatuses["fr"], .available)
        XCTAssertEqual(manager.languageStatuses.count, codes.count)
    }

    func test_findInstalledLanguage_isDeterministic() async {
        let checker = MockLanguageStatusChecker(installedPairs: [["en", "ko"], ["en", "ja"]])
        let manager = LanguagePackManager(checker: checker, languageCodes: ["ko", "ja", "en"])

        await manager.refreshAllStatuses()

        XCTAssertEqual(manager.findInstalledLanguage(excluding: "ko"), "en", "정렬 순서상 en < ja")
        XCTAssertEqual(manager.findInstalledLanguage(excluding: "en"), "ja")
    }
}
