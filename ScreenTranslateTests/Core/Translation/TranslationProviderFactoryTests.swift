import Foundation
import Testing
@testable import ScreenTranslate

/// TranslationProviderFactory의 엔진 선택 로직 검증.
/// Keychain에 API 키가 없는 상태에서의 폴백 동작을 테스트한다.
struct TranslationProviderFactoryTests {

    // MARK: - Default / Unknown

    @Test("default name returns Apple provider")
    func defaultName() {
        let provider = TranslationProviderFactory.make(name: "Apple Translation")
        #expect(provider.name == "Apple Translation")
        #expect(provider.requiresAPIKey == false)
    }

    @Test("unknown name falls back to Apple provider")
    func unknownName() {
        let provider = TranslationProviderFactory.make(name: "unknown")
        #expect(provider.name == "Apple Translation")
    }

    @Test("empty name falls back to Apple provider")
    func emptyName() {
        let provider = TranslationProviderFactory.make(name: "")
        #expect(provider.name == "Apple Translation")
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

        let provider = TranslationProviderFactory.make(name: "DeepL")
        #expect(provider.name == "Apple Translation")
    }

    @Test("Google Cloud without API key falls back to Apple")
    func googleWithoutKey() {
        let saved = KeychainHelper.load(key: TranslationProviderFactory.googleKeychainKey)
        defer {
            if let saved { try? KeychainHelper.save(key: TranslationProviderFactory.googleKeychainKey, value: saved) }
        }
        try? KeychainHelper.delete(key: TranslationProviderFactory.googleKeychainKey)

        let provider = TranslationProviderFactory.make(name: "Google Cloud")
        #expect(provider.name == "Apple Translation")
    }

    @Test("Microsoft Azure without API key falls back to Apple")
    func azureWithoutKey() {
        let saved = KeychainHelper.load(key: TranslationProviderFactory.azureKeychainKey)
        defer {
            if let saved { try? KeychainHelper.save(key: TranslationProviderFactory.azureKeychainKey, value: saved) }
        }
        try? KeychainHelper.delete(key: TranslationProviderFactory.azureKeychainKey)

        let provider = TranslationProviderFactory.make(name: "Microsoft Azure")
        #expect(provider.name == "Apple Translation")
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
