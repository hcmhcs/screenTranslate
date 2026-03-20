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
            return UserDefaults.standard.string(forKey: "com.screentranslate.targetLanguageCode") ?? AppSettings.defaultTargetLanguage
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
    private var _hasAzureKey = KeychainHelper.load(key: TranslationProviderFactory.azureKeychainKey) != nil

    var hasDeepLKey: Bool {
        access(keyPath: \._hasDeepLKey)
        return _hasDeepLKey
    }

    var hasGoogleKey: Bool {
        access(keyPath: \._hasGoogleKey)
        return _hasGoogleKey
    }

    var hasAzureKey: Bool {
        access(keyPath: \._hasAzureKey)
        return _hasAzureKey
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

    func saveAzureKey(_ key: String) throws {
        try KeychainHelper.save(key: TranslationProviderFactory.azureKeychainKey, value: key)
        withMutation(keyPath: \._hasAzureKey) { _hasAzureKey = true }
    }

    func deleteAzureKey() {
        try? KeychainHelper.delete(key: TranslationProviderFactory.azureKeychainKey)
        withMutation(keyPath: \._hasAzureKey) { _hasAzureKey = false }
    }

    // MARK: - Azure Region

    var azureRegion: String? {
        get {
            access(keyPath: \.azureRegion)
            let value = UserDefaults.standard.string(forKey: "com.screentranslate.azureRegion")
            return (value?.isEmpty == true) ? nil : value
        }
        set {
            withMutation(keyPath: \.azureRegion) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.azureRegion")
            }
        }
    }

    // MARK: - Auto Copy

    var autoCopyToClipboard: Bool {
        get {
            access(keyPath: \.autoCopyToClipboard)
            return UserDefaults.standard.object(forKey: "com.screentranslate.autoCopyToClipboard") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.autoCopyToClipboard) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.autoCopyToClipboard")
            }
        }
    }

    // MARK: - Popup Font Size

    var popupFontSize: CGFloat {
        get {
            access(keyPath: \.popupFontSize)
            let value = UserDefaults.standard.double(forKey: "com.screentranslate.popupFontSize")
            return value > 0 ? value : 13.0
        }
        set {
            withMutation(keyPath: \.popupFontSize) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.popupFontSize")
            }
        }
    }

    // MARK: - Popup Font Name

    var popupFontName: String {
        get {
            access(keyPath: \.popupFontName)
            return UserDefaults.standard.string(forKey: "com.screentranslate.popupFontName") ?? "system"
        }
        set {
            withMutation(keyPath: \.popupFontName) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.popupFontName")
            }
        }
    }

    // MARK: - Popup Width Matching

    var matchPopupWidthToSelection: Bool {
        get {
            access(keyPath: \.matchPopupWidthToSelection)
            return UserDefaults.standard.object(forKey: "com.screentranslate.matchPopupWidthToSelection") as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.matchPopupWidthToSelection) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.matchPopupWidthToSelection")
            }
        }
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        get {
            access(keyPath: \.hasCompletedOnboarding)
            return UserDefaults.standard.bool(forKey: "com.screentranslate.hasCompletedOnboarding")
        }
        set {
            withMutation(keyPath: \.hasCompletedOnboarding) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.hasCompletedOnboarding")
            }
        }
    }

    // MARK: - Drag Translate Mode

    var dragTranslateMode: String {
        get {
            access(keyPath: \.dragTranslateMode)
            return UserDefaults.standard.string(forKey: "com.screentranslate.dragTranslateMode") ?? "custom"
        }
        set {
            withMutation(keyPath: \.dragTranslateMode) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.dragTranslateMode")
            }
        }
    }

    // MARK: - Advanced

    var ocrTextPreprocessing: Bool {
        get {
            access(keyPath: \.ocrTextPreprocessing)
            return UserDefaults.standard.object(forKey: "com.screentranslate.ocrTextPreprocessing") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.ocrTextPreprocessing) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.ocrTextPreprocessing")
            }
        }
    }

    // MARK: - Computed Helpers

    var sourceLanguage: Locale.Language? {
        sourceLanguageCode == "auto" ? nil : Locale.Language(identifier: sourceLanguageCode)
    }

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetLanguageCode)
    }

    // MARK: - System Language Detection

    /// 시스템 언어를 기반으로 기본 타겟 언어를 결정한다.
    /// 시스템 언어가 지원 목록에 있으면 해당 언어, 없으면 "ko" (가장 많은 사용자).
    static let defaultTargetLanguage: String = {
        let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
        // 시스템 언어가 영어면 타겟을 자동 결정할 수 없으므로 "ko" 기본값 유지
        if systemLang == "en" { return "ko" }
        // 시스템 언어가 지원 목록에 있으면 그 언어를 타겟으로
        let supported = supportedLanguages.map(\.code)
        if supported.contains(systemLang) { return systemLang }
        // zh → zh-Hans 매핑
        if systemLang == "zh" {
            let script = Locale.current.language.script?.identifier ?? "Hans"
            return script == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        return "ko"
    }()

    /// 시스템 언어가 지원 목록에 있는지 (영어 제외). 온보딩에서 자동 설정 vs 선택 UI 분기에 사용.
    static var systemLanguageIsSupported: Bool {
        let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
        if systemLang == "en" { return false }
        if systemLang == "zh" { return true }
        return supportedLanguages.map(\.code).contains(systemLang)
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
        ("nl", "Nederlands"),
        ("hi", "हिन्दी"),
        ("id", "Bahasa Indonesia"),
        ("pl", "Polski"),
        ("th", "ไทย"),
        ("tr", "Türkçe"),
        ("uk", "Українська"),
        ("vi", "Tiếng Việt"),
    ]
}
