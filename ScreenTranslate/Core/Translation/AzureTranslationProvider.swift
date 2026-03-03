import Foundation

/// Microsoft Azure Translator API v3.0을 사용하는 번역 Provider.
/// Global 리소스는 API 키만, Regional 리소스는 API 키 + 리전이 필요하다.
final class AzureTranslationProvider: TranslationProvider {
    let name = "Microsoft Azure"
    let requiresAPIKey = true

    private let apiKey: String
    private let region: String?
    private let baseURL = "https://api.cognitive.microsofttranslator.com/translate"

    init(apiKey: String, region: String? = nil) {
        self.apiKey = apiKey
        self.region = region
    }

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        var components = URLComponents(string: baseURL)!
        var queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: LanguageCodeMapper.toAzureCode(target)),
        ]
        if let source {
            queryItems.append(URLQueryItem(name: "from", value: LanguageCodeMapper.toAzureCode(source)))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        if let region, !region.isEmpty {
            request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([RequestBody(text: text)])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.translationFailed("Invalid response")
        }

        guard http.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            switch http.statusCode {
            case 401:
                throw TranslationError.apiKeyMissing
            case 403:
                if errorBody?.error.code == 403001 {
                    throw TranslationError.translationFailed(L10n.quotaExceeded)
                }
                throw TranslationError.apiKeyMissing
            case 429:
                throw TranslationError.translationFailed(L10n.quotaExceeded)
            default:
                let message = errorBody?.error.message ?? "Azure HTTP \(http.statusCode)"
                throw TranslationError.translationFailed(message)
            }
        }

        let results = try JSONDecoder().decode([TranslationResult].self, from: data)
        guard let translatedText = results.first?.translations.first?.text else {
            throw TranslationError.translationFailed("Invalid response format")
        }

        return translatedText
    }
}

// MARK: - Request / Response Models

private extension AzureTranslationProvider {
    struct RequestBody: Encodable {
        // Azure API는 "Text" (대문자 T)를 요구한다
        enum CodingKeys: String, CodingKey { case text = "Text" }
        let text: String
    }

    struct TranslationResult: Decodable {
        struct Translation: Decodable {
            let text: String
            let to: String
        }
        let translations: [Translation]
    }

    struct ErrorResponse: Decodable {
        struct ErrorBody: Decodable {
            let code: Int
            let message: String
        }
        let error: ErrorBody
    }
}
