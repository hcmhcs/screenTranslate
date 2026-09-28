import CoreGraphics
@testable import ScreenTranslate

/// 세션의 틱을 한 단계씩 진행시키는 가짜 캡처 — 테스트가 화면을 넘겨줄 때까지 캡처가 멈춰 있다.
@MainActor
final class GatedFrameSource: LiveFrameSource {
    private var pending: CheckedContinuation<CGImage, Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedRegions: [LiveRegion] = []

    func captureFrame(of region: LiveRegion) async throws -> CGImage {
        requestedRegions.append(region)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                let waiters = requestWaiters
                requestWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            Task { @MainActor in
                self.pending?.resume(throwing: CancellationError())
                self.pending = nil
            }
        }
    }

    /// 세션이 캡처를 요청할 때까지 기다린다 (= 이전 틱이 끝났다)
    func nextRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func deliver(_ image: CGImage) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: image)
    }

    func fail(_ error: Error) {
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: error)
    }
}
