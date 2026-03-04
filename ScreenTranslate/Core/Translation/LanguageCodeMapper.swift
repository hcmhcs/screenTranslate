import Foundation

/// Locale.Language ↔ 외부 API 언어 코드 변환.
/// DeepL은 대문자 2자리(+변형), Google은 소문자 ISO 639.
///
/// 주의: `Locale.Language.minimalIdentifier`는 "zh-Hans"→"zh", "pt-BR"→"pt" 등으로
/// 정규화하므로 switch 매칭에 사용하면 안 된다. `languageCode`, `script`, `region`
/// 컴포넌트를 직접 확인한다.
enum LanguageCodeMapper {
    /// Locale.Language → DeepL 코드
    /// "ko" → "KO", "zh-Hans" → "ZH-HANS"
    static func toDeepLCode(_ lang: Locale.Language) -> String {
        let langCode = lang.languageCode?.identifier ?? lang.minimalIdentifier

        // Chinese: script determines Simplified vs Traditional
        if langCode == "zh" {
            return lang.script?.identifier == "Hant" ? "ZH-HANT" : "ZH-HANS"
        }
        // Regional variants
        let region = lang.region?.identifier
        if langCode == "pt" && region == "BR" { return "PT-BR" }
        if langCode == "en" {
            if region == "US" { return "EN-US" }
            if region == "GB" { return "EN-GB" }
        }
        return langCode.uppercased()
    }

    /// Locale.Language → Google Cloud 코드
    /// "ko" → "ko", "zh-Hans" → "zh-CN"
    static func toGoogleCode(_ lang: Locale.Language) -> String {
        let langCode = lang.languageCode?.identifier ?? lang.minimalIdentifier

        if langCode == "zh" {
            return lang.script?.identifier == "Hant" ? "zh-TW" : "zh-CN"
        }
        return langCode.lowercased()
    }

    /// Locale.Language → Azure Translator 코드
    /// Azure는 BCP-47 기반으로 대부분 언어 코드와 동일.
    /// "pt-BR" → "pt" (Azure 기본값이 브라질 포르투갈어)
    static func toAzureCode(_ lang: Locale.Language) -> String {
        let langCode = lang.languageCode?.identifier ?? lang.minimalIdentifier
        let region = lang.region?.identifier

        if langCode == "zh" {
            return lang.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        if langCode == "pt" { return region == "PT" ? "pt-pt" : "pt" }
        if langCode == "fr" && region == "CA" { return "fr-ca" }
        return lang.minimalIdentifier
    }
}
