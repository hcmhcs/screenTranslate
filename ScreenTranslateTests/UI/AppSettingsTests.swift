import Foundation
import Testing
@testable import ScreenTranslate

/// AppSettings의 순수 데이터 및 기본값 검증.
/// UserDefaults를 수정하는 테스트는 상태 오염 방지를 위해 직렬 실행한다.
@Suite(.serialized)
struct AppSettingsTests {

    // MARK: - 지원 언어 목록 (순수 데이터)

    @Test("supportedLanguages contains 12 languages")
    func supportedLanguagesCount() {
        #expect(AppSettings.supportedLanguages.count == 12)
    }

    @Test("supportedLanguages codes are unique")
    func supportedLanguagesUnique() {
        let codes = AppSettings.supportedLanguages.map(\.code)
        #expect(codes.count == Set(codes).count, "중복 언어 코드가 있으면 안 된다")
    }

    @Test("supportedLanguages names are non-empty")
    func supportedLanguagesNames() {
        for lang in AppSettings.supportedLanguages {
            #expect(!lang.name.isEmpty, "\(lang.code) 언어 이름이 비어있다")
        }
    }

    // MARK: - UserDefaults 기본값

    @Test("default translationProviderName is Apple Translation")
    func defaultTranslationProviderName() {
        let key = "com.screentranslate.translationProviderName"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(AppSettings.shared.translationProviderName == "Apple Translation")
    }

    @Test("default ocrTextPreprocessing is true")
    func defaultOcrTextPreprocessing() {
        let key = "com.screentranslate.ocrTextPreprocessing"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(AppSettings.shared.ocrTextPreprocessing == true)
    }

    @Test("default autoCopyToClipboard is true")
    func defaultAutoCopyToClipboard() {
        let key = "com.screentranslate.autoCopyToClipboard"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(AppSettings.shared.autoCopyToClipboard == true)
    }

    @Test("default sourceLanguageCode is auto")
    func defaultSourceLanguageCode() {
        let key = "com.screentranslate.sourceLanguageCode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(AppSettings.shared.sourceLanguageCode == "auto")
    }

    // MARK: - Computed Properties

    @Test("sourceLanguage returns nil when code is auto")
    func sourceLanguageAuto() {
        let key = "com.screentranslate.sourceLanguageCode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("auto", forKey: key)
        #expect(AppSettings.shared.sourceLanguage == nil)
    }

    @Test("sourceLanguage returns Locale.Language when code is set")
    func sourceLanguageSpecific() {
        let key = "com.screentranslate.sourceLanguageCode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("en", forKey: key)
        let lang = AppSettings.shared.sourceLanguage
        #expect(lang != nil)
        #expect(lang?.minimalIdentifier == "en")
    }

    @Test("targetLanguage returns Locale.Language from targetLanguageCode")
    func targetLanguageComputed() {
        let key = "com.screentranslate.targetLanguageCode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("ja", forKey: key)
        #expect(AppSettings.shared.targetLanguage.minimalIdentifier == "ja")
    }
}
