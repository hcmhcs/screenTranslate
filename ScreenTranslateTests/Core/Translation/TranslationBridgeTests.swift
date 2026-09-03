import Translation
import XCTest
@testable import ScreenTranslate

/// TranslationBridge의 취소·타임아웃·요청 교체 동작 (C2).
/// `.translationTask` 콜백은 SwiftUI 없이는 오지 않으므로, 콜백이 오지 않는 상황을 그대로 이용한다.
@MainActor
final class TranslationBridgeTests: XCTestCase {

    func test_taskCancellation_throwsCancellationError() async {
        let bridge = TranslationBridge(timeout: .seconds(10))
        let task = Task {
            try await bridge.translate(text: "Hello", from: nil, to: Locale.Language(identifier: "ko"))
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소되면 throw해야 한다")
        } catch is CancellationError {
            // 기대 동작
        } catch {
            XCTFail("CancellationError여야 한다: \(error)")
        }
        XCTAssertFalse(bridge.isTranslating)
        XCTAssertNil(bridge.pendingText)
    }

    func test_timeout_throwsTranslationFailed() async {
        let bridge = TranslationBridge(timeout: .milliseconds(100))
        do {
            _ = try await bridge.translate(text: "Hello", from: nil, to: Locale.Language(identifier: "ko"))
            XCTFail("타임아웃이면 throw해야 한다")
        } catch ScreenTranslate.TranslationError.translationFailed(let reason) {
            // Translation 프레임워크에도 TranslationError가 있어 모듈을 명시한다
            XCTAssertEqual(reason, L10n.translationTimedOut)
        } catch {
            XCTFail("translationFailed여야 한다: \(error)")
        }
        XCTAssertFalse(bridge.isTranslating)
    }

    func test_newRequest_cancelsPreviousRequest() async {
        let bridge = TranslationBridge(timeout: .seconds(10))
        let first = Task {
            try await bridge.translate(text: "one", from: nil, to: Locale.Language(identifier: "ko"))
        }
        try? await Task.sleep(for: .milliseconds(20))
        let second = Task {
            try await bridge.translate(text: "two", from: nil, to: Locale.Language(identifier: "ko"))
        }

        do {
            _ = try await first.value
            XCTFail("이전 요청은 취소되어야 한다")
        } catch is CancellationError {
            // 기대 동작
        } catch {
            XCTFail("CancellationError여야 한다: \(error)")
        }
        XCTAssertEqual(bridge.pendingText, "two")
        XCTAssertTrue(bridge.isTranslating)

        second.cancel()
        _ = try? await second.value
        XCTAssertFalse(bridge.isTranslating)
    }

    func test_configuration_isCreatedForLanguagePair() async {
        let bridge = TranslationBridge(timeout: .milliseconds(50))
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "ko")
        _ = try? await bridge.translate(text: "Hello", from: source, to: target)

        XCTAssertEqual(bridge.configuration?.source, source)
        XCTAssertEqual(bridge.configuration?.target, target)
    }
}
