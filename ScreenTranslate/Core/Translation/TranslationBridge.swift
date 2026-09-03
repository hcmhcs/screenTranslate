import SwiftUI
import Translation

/// Apple Translation Framework는 SwiftUI `.translationTask` modifier를 통해서만
/// TranslationSession을 획득할 수 있다. TranslationBridge는 크기 0의 투명 뷰로,
/// 앱 UI 계층에 항상 존재하며 번역 요청을 처리한다.
///
/// 동시성 규칙 (C1/C2):
/// - 한 번에 하나의 요청만 처리한다. 새 요청이 오면 이전 요청은 CancellationError로 끝난다.
///   (QuickTranslate와 OCR/드래그 번역이 동시에 요청하면 먼저 진행 중이던 쪽이 취소된다)
/// - 호출 Task가 취소되면 continuation을 즉시 CancellationError로 resume한다.
/// - `.translationTask` 콜백이 오지 않거나 세션이 응답하지 않으면 `timeout` 후 실패로 끝난다.
/// - 모든 완료 경로는 `finish(_:with:)` 하나로 모이며, 요청 ID가 일치할 때 한 번만 resume한다.
@MainActor @Observable
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

    /// 세션 응답 대기 상한
    let timeout: Duration

    @ObservationIgnored private var continuation: CheckedContinuation<String, Error>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var sessionRequestID: UUID?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    init(timeout: Duration = .seconds(30)) {
        self.timeout = timeout
    }

    /// async/await 인터페이스로 번역을 요청한다.
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        // 이전 요청이 남아 있으면 취소로 끝낸다
        finish(requestID, with: .failure(CancellationError()))

        let id = UUID()
        requestID = id

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.pendingText = text
                self.isTranslating = true
                self.translatedText = nil
                self.errorMessage = nil

                // C5: Apple 공식 패턴 — invalidate()로 재트리거
                if var config = self.configuration {
                    if config.source != source || config.target != target {
                        self.configuration = TranslationSession.Configuration(source: source, target: target)
                    } else {
                        config.invalidate()
                        self.configuration = config  // struct이므로 writeback 필수
                    }
                } else {
                    self.configuration = TranslationSession.Configuration(source: source, target: target)
                }

                self.timeoutTask = Task { [timeout] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self.finish(id, with: .failure(TranslationError.translationFailed(L10n.translationTimedOut)))
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(id, with: .failure(CancellationError()))
            }
        }
    }

    /// .translationTask의 콜백에서 호출된다.
    func handleSession(_ session: TranslationSession) {
        guard continuation != nil, let text = pendingText else { return }
        let id = requestID
        // 같은 요청에 대해 콜백이 두 번 오면(SwiftUI 재렌더) 두 번째는 무시
        guard sessionRequestID != id else { return }
        sessionRequestID = id

        sessionTask = Task {
            do {
                let response = try await session.translate(text)
                self.finish(id, with: .success(response.targetText))
            } catch {
                if self.configuration?.source == nil {
                    // 자동 감지 모드에서 실패 — 짧은 텍스트 등으로 언어 판별 불가
                    self.finish(id, with: .failure(TranslationError.autoDetectFailed(error.localizedDescription)))
                } else {
                    self.finish(id, with: .failure(TranslationError.translationFailed(error.localizedDescription)))
                }
            }
        }
    }

    /// 요청을 한 번만 끝낸다. 요청 ID가 현재 요청과 다르거나 이미 끝났으면 아무것도 하지 않는다.
    private func finish(_ id: UUID, with result: Result<String, Error>) {
        guard id == requestID, let active = continuation else { return }
        continuation = nil
        pendingText = nil
        isTranslating = false
        timeoutTask?.cancel()
        timeoutTask = nil
        if sessionRequestID == id {
            sessionTask?.cancel()
            sessionTask = nil
            sessionRequestID = nil
        }

        switch result {
        case .success(let text):
            translatedText = text
            active.resume(returning: text)
        case .failure(let error):
            errorMessage = error.localizedDescription
            active.resume(throwing: error)
        }
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
