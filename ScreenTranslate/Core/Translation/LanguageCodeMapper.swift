import Foundation

/// Locale.Language ↔ 외부 API 언어 코드 변환.
/// DeepL은 대문자 2자리(+변형), Google은 소문자 ISO 639.
enum LanguageCodeMapper {
    /// Locale.Language → DeepL 코드
    /// "ko" → "KO", "zh-Hans" → "ZH-HANS"
    static func toDeepLCode(_ lang: Locale.Language) -> String {
        let id = lang.minimalIdentifier
        switch id {
        case "zh-Hans": return "ZH-HANS"
        case "zh-Hant": return "ZH-HANT"
        case "pt-BR":   return "PT-BR"
        case "en-US":   return "EN-US"
        case "en-GB":   return "EN-GB"
        default:         return String(id.prefix(2)).uppercased()
        }
    }

    /// Locale.Language → Google Cloud 코드
    /// "ko" → "ko", "zh-Hans" → "zh-CN"
    static func toGoogleCode(_ lang: Locale.Language) -> String {
        let id = lang.minimalIdentifier
        switch id {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default:         return String(id.prefix(2)).lowercased()
        }
    }
}
