import Foundation

/// DeepL API v2를 사용하는 번역 Provider.
/// Free 플랜(키가 ":fx"로 끝남)과 Pro 플랜을 자동 구분한다.
final class DeepLTranslationProvider: TranslationProvider {
    let name = "DeepL"
    let requiresAPIKey = true

    private let apiKey: String

    /// Free 플랜: api-free.deepl.com, Pro 플랜: api.deepl.com
    private var baseURL: String {
        apiKey.hasSuffix(":fx")
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"
    }

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        var body: [String: Any] = [
            "text": [text],
            "target_lang": LanguageCodeMapper.toDeepLCode(target)
        ]
        if let source {
            body["source_lang"] = LanguageCodeMapper.toDeepLCode(source)
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.translationFailed("Invalid response")
        }

        switch http.statusCode {
        case 200: break
        case 403: throw TranslationError.apiKeyMissing
        case 456: throw TranslationError.translationFailed(L10n.quotaExceeded)
        case 429: throw TranslationError.translationFailed(L10n.quotaExceeded)
        default:  throw TranslationError.translationFailed("DeepL HTTP \(http.statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let translations = json?["translations"] as? [[String: Any]]
        guard let translatedText = translations?.first?["text"] as? String else {
            throw TranslationError.translationFailed("Invalid response format")
        }

        return translatedText
    }
}
