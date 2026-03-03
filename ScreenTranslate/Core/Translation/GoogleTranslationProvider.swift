import Foundation

/// Google Cloud Translation API v2 (Basic)를 사용하는 번역 Provider.
/// API 키 인증 방식 (URL 쿼리 파라미터).
final class GoogleTranslationProvider: TranslationProvider {
    let name = "Google Cloud"
    let requiresAPIKey = true

    private let apiKey: String
    private let baseURL = "https://translation.googleapis.com/language/translate/v2"

    init(apiKey: String) {
        self.apiKey = apiKey
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.translationFailed("Invalid response")
        }

        switch http.statusCode {
        case 200: break
        case 400: throw TranslationError.translationFailed("Invalid request")
        case 403: throw TranslationError.apiKeyMissing
        default:  throw TranslationError.translationFailed("Google HTTP \(http.statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let translations = dataObj?["translations"] as? [[String: Any]]
        guard let translatedText = translations?.first?["translatedText"] as? String else {
            throw TranslationError.translationFailed("Invalid response format")
        }

        return translatedText
    }
}
