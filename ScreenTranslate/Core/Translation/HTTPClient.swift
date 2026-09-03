import Foundation

/// URLSession을 감싸는 최소 인터페이스 — 테스트에서 응답을 주입한다.
nonisolated protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

/// 클라우드 번역 프로바이더 공통 HTTP 헬퍼.
enum TranslationHTTP {
    /// 요청을 보내고 HTTPURLResponse를 돌려준다. URLError는 사용자에게 보여줄 메시지로 바꾼다.
    /// 취소(URLError.cancelled)는 그대로 던진다 — TranslationCoordinator가 .idle로 처리한다.
    static func perform(_ request: URLRequest, using client: HTTPClient) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw error
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw TranslationError.translationFailed(L10n.networkUnavailable)
            case .timedOut:
                throw TranslationError.translationFailed(L10n.networkTimedOut)
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
                throw TranslationError.translationFailed(L10n.serverUnreachable)
            default:
                throw TranslationError.translationFailed(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.translationFailed(L10n.invalidServerResponse)
        }
        return (data, http)
    }
}
