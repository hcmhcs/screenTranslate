import Foundation
import Observation

/// @Observable + UserDefaults 연동.
/// computed property에서는 @Observable의 자동 tracking이 동작하지 않으므로
/// access(keyPath:) / withMutation(keyPath:) 를 수동으로 호출한다.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - App Language

    var appLanguage: String {
        get {
            access(keyPath: \.appLanguage)
            return UserDefaults.standard.string(forKey: "com.screentranslate.appLanguage") ?? "en"
        }
        set {
            withMutation(keyPath: \.appLanguage) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.appLanguage")
            }
        }
    }

    // MARK: - Source Language

    /// "auto"이면 자동 감지, 그 외에는 언어 코드
    var sourceLanguageCode: String {
        get {
            access(keyPath: \.sourceLanguageCode)
            return UserDefaults.standard.string(forKey: "com.screentranslate.sourceLanguageCode") ?? "auto"
        }
        set {
            withMutation(keyPath: \.sourceLanguageCode) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.sourceLanguageCode")
            }
        }
    }

    // MARK: - Target Language

    var targetLanguageCode: String {
        get {
            access(keyPath: \.targetLanguageCode)
            return UserDefaults.standard.string(forKey: "com.screentranslate.targetLanguageCode") ?? "ko"
        }
        set {
            withMutation(keyPath: \.targetLanguageCode) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.targetLanguageCode")
            }
        }
    }

    // MARK: - OCR Provider

    var ocrProviderName: String {
        get {
            access(keyPath: \.ocrProviderName)
            return UserDefaults.standard.string(forKey: "com.screentranslate.ocrProviderName") ?? "Apple Vision"
        }
        set {
            withMutation(keyPath: \.ocrProviderName) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.ocrProviderName")
            }
        }
    }

    // MARK: - Translation Provider

    var translationProviderName: String {
        get {
            access(keyPath: \.translationProviderName)
            return UserDefaults.standard.string(forKey: "com.screentranslate.translationProviderName") ?? "Apple Translation"
        }
        set {
            withMutation(keyPath: \.translationProviderName) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.translationProviderName")
            }
        }
    }

    // MARK: - API Key Status (캐싱하여 매 렌더 시 Keychain 호출 방지)

    private var _hasDeepLKey = KeychainHelper.load(key: TranslationProviderFactory.deepLKeychainKey) != nil
    private var _hasGoogleKey = KeychainHelper.load(key: TranslationProviderFactory.googleKeychainKey) != nil

    var hasDeepLKey: Bool {
        access(keyPath: \._hasDeepLKey)
        return _hasDeepLKey
    }

    var hasGoogleKey: Bool {
        access(keyPath: \._hasGoogleKey)
        return _hasGoogleKey
    }

    // MARK: - API Key Operations

    func saveDeepLKey(_ key: String) throws {
        try KeychainHelper.save(key: TranslationProviderFactory.deepLKeychainKey, value: key)
        withMutation(keyPath: \._hasDeepLKey) { _hasDeepLKey = true }
    }

    func deleteDeepLKey() {
        try? KeychainHelper.delete(key: TranslationProviderFactory.deepLKeychainKey)
        withMutation(keyPath: \._hasDeepLKey) { _hasDeepLKey = false }
    }

    func saveGoogleKey(_ key: String) throws {
        try KeychainHelper.save(key: TranslationProviderFactory.googleKeychainKey, value: key)
        withMutation(keyPath: \._hasGoogleKey) { _hasGoogleKey = true }
    }

    func deleteGoogleKey() {
        try? KeychainHelper.delete(key: TranslationProviderFactory.googleKeychainKey)
        withMutation(keyPath: \._hasGoogleKey) { _hasGoogleKey = false }
    }

    // MARK: - Computed Helpers

    var sourceLanguage: Locale.Language? {
        sourceLanguageCode == "auto" ? nil : Locale.Language(identifier: sourceLanguageCode)
    }

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetLanguageCode)
    }

    // MARK: - Supported Languages

    static let supportedLanguages: [(code: String, name: String)] = [
        ("ko", "한국어"),
        ("en", "English"),
        ("ja", "日本語"),
        ("zh-Hans", "中文(简体)"),
        ("zh-Hant", "中文(繁體)"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("pt", "Português"),
        ("it", "Italiano"),
        ("ru", "Русский"),
        ("ar", "العربية"),
    ]
}
