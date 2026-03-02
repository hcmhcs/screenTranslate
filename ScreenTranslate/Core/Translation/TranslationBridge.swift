import SwiftUI
import Translation

/// Apple Translation Framework는 SwiftUI `.translationTask` modifier를 통해서만
/// TranslationSession을 획득할 수 있다. TranslationBridge는 크기 0의 투명 뷰로,
/// 앱 UI 계층에 항상 존재하며 번역 요청을 처리한다.
@Observable
final class TranslationBridge {
    static let shared = TranslationBridge()

    /// 번역할 텍스트 (외부에서 설정)
    var pendingText: String?

    /// 번역 결과
    var translatedText: String?

    /// 에러 메시지
    var errorMessage: String?

    /// 현재 번역 중인지 여부
    var isTranslating = false

    /// 번역 설정 (변경 시 .translationTask가 재트리거됨)
    var configuration: TranslationSession.Configuration?

    /// continuation을 저장하여 async/await 패턴으로 사용
    private var continuation: CheckedContinuation<String, Error>?

    /// async/await 인터페이스로 번역을 요청한다.
    /// ⚠️ C1: 이전 continuation이 남아있으면 에러로 resume한 후 교체한다.
    /// 그렇지 않으면 resume 없이 덮어써져 크래시가 발생한다.
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        // C1: 기존 continuation이 있으면 취소 처리
        if let existing = continuation {
            existing.resume(throwing: TranslationError.translationFailed("새 번역 요청으로 취소됨"))
            continuation = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.pendingText = text
            self.isTranslating = true
            self.translatedText = nil
            self.errorMessage = nil

            // C5: configuration을 nil로 리셋한 후 새 값을 설정하여
            // 같은 언어쌍이라도 .translationTask가 재트리거되도록 한다.
            self.configuration = nil
            self.configuration = TranslationSession.Configuration(
                source: source,
                target: target
            )
        }
    }

    /// .translationTask의 콜백에서 호출된다.
    /// continuation을 원자적으로 소비하여 이중 resume을 방지한다.
    func handleSession(_ session: TranslationSession) {
        guard let text = pendingText else {
            completionWithError("번역할 텍스트가 없습니다.")
            return
        }

        // continuation을 원자적으로 소비 — 동시 handleSession 호출 시 이중 resume 방지
        let activeContinuation = self.continuation
        self.continuation = nil

        guard let activeContinuation else { return }

        Task {
            do {
                let response = try await session.translate(text)
                self.translatedText = response.targetText
                self.isTranslating = false
                activeContinuation.resume(returning: response.targetText)
            } catch {
                self.errorMessage = error.localizedDescription
                self.isTranslating = false
                activeContinuation.resume(throwing: TranslationError.translationFailed(error.localizedDescription))
            }
        }
    }

    private func completionWithError(_ message: String) {
        self.errorMessage = message
        self.isTranslating = false
        self.continuation?.resume(throwing: TranslationError.translationFailed(message))
        self.continuation = nil
    }
}

/// 앱 UI 계층에 삽입하는 투명 뷰.
/// ScreenTranslateApp의 body에 overlay로 추가한다.
struct TranslationBridgeView: View {
    @State private var bridge = TranslationBridge.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(bridge.configuration) { session in
                bridge.handleSession(session)
            }
    }
}
