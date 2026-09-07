import Foundation

/// 설정에서 선택 가능한 번역 엔진.
/// rawValue는 UserDefaults에 저장되는 값이자 프로바이더의 표시 이름이다
/// (기존 저장값과의 호환을 위해 표시 문자열을 그대로 쓴다).
enum TranslationEngine: String, CaseIterable, Sendable {
    case apple = "Apple Translation"
    case deepl = "DeepL"
    case google = "Google Cloud"
    case azure = "Microsoft Azure"
}

/// 선택된 엔진에 맞는 TranslationProvider 인스턴스를 생성한다.
/// BYOK 엔진의 API 키가 없으면 AppleTranslationProvider로 fallback한다.
enum TranslationProviderFactory {
    /// Keychain 키 이름 상수
    static let deepLKeychainKey = "com.screentranslate.api.deepl"
    static let googleKeychainKey = "com.screentranslate.api.google"
    static let azureKeychainKey = "com.screentranslate.api.azure"

    static func make(_ engine: TranslationEngine) -> TranslationProvider {
        switch engine {
        case .apple:
            return AppleTranslationProvider()

        case .deepl:
            guard let apiKey = KeychainHelper.load(key: deepLKeychainKey) else {
                return AppleTranslationProvider()
            }
            return DeepLTranslationProvider(apiKey: apiKey)

        case .google:
            guard let apiKey = KeychainHelper.load(key: googleKeychainKey) else {
                return AppleTranslationProvider()
            }
            return GoogleTranslationProvider(apiKey: apiKey)

        case .azure:
            guard let apiKey = KeychainHelper.load(key: azureKeychainKey) else {
                return AppleTranslationProvider()
            }
            let region = AppSettings.shared.azureRegion
            return AzureTranslationProvider(apiKey: apiKey, region: region)
        }
    }
}
