import Foundation

/// 설정의 Provider 이름으로 적절한 TranslationProvider 인스턴스를 생성한다.
/// API 키가 없으면 AppleTranslationProvider로 fallback한다.
enum TranslationProviderFactory {
    /// Keychain 키 이름 상수
    static let deepLKeychainKey = "com.screentranslate.api.deepl"
    static let googleKeychainKey = "com.screentranslate.api.google"

    static func make(name: String) -> TranslationProvider {
        switch name {
        case "DeepL":
            guard let apiKey = KeychainHelper.load(key: deepLKeychainKey) else {
                return AppleTranslationProvider()
            }
            return DeepLTranslationProvider(apiKey: apiKey)

        case "Google Cloud":
            guard let apiKey = KeychainHelper.load(key: googleKeychainKey) else {
                return AppleTranslationProvider()
            }
            return GoogleTranslationProvider(apiKey: apiKey)

        default:
            return AppleTranslationProvider()
        }
    }
}
