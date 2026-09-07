import Foundation

/// Google Cloud Translation API v2 (Basic)를 사용하는 번역 Provider.
/// API 키는 URL 쿼리가 아니라 `x-goog-api-key` 헤더로 보낸다.
final class GoogleTranslationProvider: TranslationProvider {
    let name = "Google Cloud"
    let requiresAPIKey = true

    private let apiKey: String
    private let client: HTTPClient
    private let baseURL = "https://translation.googleapis.com/language/translate/v2"

    init(apiKey: String, client: HTTPClient = URLSession.shared) {
        self.apiKey = apiKey
        self.client = client
    }

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        var body: [String: Any] = [
            "q": text,
            "target": LanguageCodeMapper.toGoogleCode(target),
            "format": "text"
        ]
        if let source {
            body["source"] = LanguageCodeMapper.toGoogleCode(source)
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, http) = try await TranslationHTTP.perform(request, using: client)

        switch http.statusCode {
        case 200: break
        case 400: throw TranslationError.translationFailed(L10n.invalidRequest)
        case 403: throw TranslationError.apiKeyMissing
        default:  throw TranslationError.translationFailed(L10n.engineHttpError("Google", status: http.statusCode))
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let translatedText = response.data.translations.first?.translatedText else {
            throw TranslationError.translationFailed(L10n.invalidServerResponse)
        }
        return translatedText
    }
}

private extension GoogleTranslationProvider {
    struct Response: Decodable {
        struct DataBody: Decodable {
            struct Translation: Decodable {
                let translatedText: String
            }
            let translations: [Translation]
        }
        let data: DataBody
    }
}
