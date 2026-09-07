import Foundation
import Testing
@testable import ScreenTranslate

/// TranslationProviderFactory의 엔진 선택 로직 검증.
/// Keychain에 API 키가 없는 상태에서의 폴백 동작을 테스트한다.
struct TranslationProviderFactoryTests {

    // MARK: - Default

    @Test("Apple engine returns Apple provider")
    func appleEngine() {
        let provider = TranslationProviderFactory.make(.apple)
        #expect(provider.name == "Apple Translation")
        #expect(provider.requiresAPIKey == false)
    }

    // MARK: - BYOK without API key → Apple fallback

    @Test("DeepL without API key falls back to Apple")
    func deepLWithoutKey() {
        // Keychain에 키가 없으면 Apple로 폴백
        let saved = KeychainHelper.load(key: TranslationProviderFactory.deepLKeychainKey)
        defer {
            if let saved { try? KeychainHelper.save(key: TranslationProviderFactory.deepLKeychainKey, value: saved) }
        }
        try? KeychainHelper.delete(key: TranslationProviderFactory.deepLKeychainKey)

        let provider = TranslationProviderFactory.make(.deepl)
        #expect(provider.name == "Apple Translation")
    }

    @Test("Google Cloud without API key falls back to Apple")
    func googleWithoutKey() {
        let saved = KeychainHelper.load(key: TranslationProviderFactory.googleKeychainKey)
        defer {
            if let saved { try? KeychainHelper.save(key: TranslationProviderFactory.googleKeychainKey, value: saved) }
        }
        try? KeychainHelper.delete(key: TranslationProviderFactory.googleKeychainKey)

        let provider = TranslationProviderFactory.make(.google)
        #expect(provider.name == "Apple Translation")
    }

    @Test("Microsoft Azure without API key falls back to Apple")
    func azureWithoutKey() {
        let saved = KeychainHelper.load(key: TranslationProviderFactory.azureKeychainKey)
        defer {
            if let saved { try? KeychainHelper.save(key: TranslationProviderFactory.azureKeychainKey, value: saved) }
        }
        try? KeychainHelper.delete(key: TranslationProviderFactory.azureKeychainKey)

        let provider = TranslationProviderFactory.make(.azure)
        #expect(provider.name == "Apple Translation")
    }

    // MARK: - Engine enum ↔ 저장값 호환

    @Test("engine rawValues match provider display names")
    func rawValuesMatchDisplayNames() {
        // rawValue는 UserDefaults에 저장되는 값이므로 절대 바뀌면 안 된다
        #expect(TranslationEngine.apple.rawValue == "Apple Translation")
        #expect(TranslationEngine.deepl.rawValue == "DeepL")
        #expect(TranslationEngine.google.rawValue == "Google Cloud")
        #expect(TranslationEngine.azure.rawValue == "Microsoft Azure")
    }

    @Test("unknown stored value parses to nil (AppSettings getter falls back to Apple)")
    func unknownValueParsesToNil() {
        #expect(TranslationEngine(rawValue: "unknown") == nil)
        #expect(TranslationEngine(rawValue: "") == nil)
    }

    // MARK: - Keychain key constants

    @Test("keychain key constants are unique")
    func keychainKeysUnique() {
        let keys = [
            TranslationProviderFactory.deepLKeychainKey,
            TranslationProviderFactory.googleKeychainKey,
            TranslationProviderFactory.azureKeychainKey,
        ]
        #expect(keys.count == Set(keys).count, "Keychain 키가 중복되면 안 된다")
    }
}
