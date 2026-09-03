import Foundation
@testable import ScreenTranslate

/// 미리 정한 응답이나 에러를 돌려주는 HTTPClient. 보낸 요청을 기록한다.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var result: Result<(Data, URLResponse), Error>
    private(set) var requests: [URLRequest] = []

    init(result: Result<(Data, URLResponse), Error>) {
        self.result = result
    }

    static func responding(status: Int, body: String, url: String = "https://example.test") -> MockHTTPClient {
        let response = HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return MockHTTPClient(result: .success((Data(body.utf8), response)))
    }

    static func failing(_ error: Error) -> MockHTTPClient {
        MockHTTPClient(result: .failure(error))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try result.get()
    }

    var lastRequest: URLRequest? { requests.last }

    var lastBodyJSON: [String: Any]? {
        guard let body = requests.last?.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}
