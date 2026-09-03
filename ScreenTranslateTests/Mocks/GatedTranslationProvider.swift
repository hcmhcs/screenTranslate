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

    /// resume되어 호출자에게 돌아간 횟수. 증가 직후 같은 MainActor 홉에서 코디네이터의 catch까지 실행되므로,
    /// 테스트는 sleep 대신 이 값을 기다리면 "이전 실행이 에러를 처리했다"를 결정적으로 알 수 있다.
    private(set) var completedCalls = 0

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        do {
            let value = try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
            completedCalls += 1
            return value
        } catch {
            completedCalls += 1
            throw error
        }
    }

    /// 가장 먼저 매달린 호출을 결과로 깨운다.
    func resumeFirst(with result: Result<String, Error>) {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume(with: result)
    }
}
