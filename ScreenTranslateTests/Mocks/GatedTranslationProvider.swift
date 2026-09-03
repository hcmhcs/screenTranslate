import Foundation
@testable import ScreenTranslate

/// translate()를 외부에서 resume할 때까지 매달아 두는 모의 프로바이더.
/// 취소된 이전 실행이 나중에 깨어나는 상황(C1)을 재현한다.
/// 테스트 타깃은 기본 MainActor 격리가 아니므로 명시한다 (가변 상태 + Sendable).
@MainActor
final class GatedTranslationProvider: TranslationProvider {
    let name = "Gated"
    let requiresAPIKey = false

    private var waiters: [CheckedContinuation<String, Error>] = []

    /// 현재 매달려 있는 translate() 호출 수
    var pendingCount: Int { waiters.count }

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// 가장 먼저 매달린 호출을 결과로 깨운다.
    func resumeFirst(with result: Result<String, Error>) {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume(with: result)
    }
}
