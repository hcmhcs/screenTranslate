import Foundation
import Testing
@testable import ScreenTranslate

struct LanguageCodeMapperTests {

    @Test("DeepL code mapping", arguments: [
        ("ko", "KO"),
        ("en", "EN"),
        ("ja", "JA"),
        ("zh-Hans", "ZH-HANS"),
        ("zh-Hant", "ZH-HANT"),
        ("pt", "PT"),
        ("pt-BR", "PT-BR"),
        ("en-US", "EN-US"),
        ("en-GB", "EN-GB"),
        ("en-AU", "EN"),
        ("xx", "XX"),
    ])
    func deeplCode(input: String, expected: String) {
        #expect(LanguageCodeMapper.toDeepLCode(.init(identifier: input)) == expected)
    }

    @Test("Google code mapping", arguments: [
        ("ko", "ko"),
        ("en", "en"),
        ("ja", "ja"),
        ("zh-Hans", "zh-CN"),
        ("zh-Hant", "zh-TW"),
        ("xx", "xx"),
    ])
    func googleCode(input: String, expected: String) {
        #expect(LanguageCodeMapper.toGoogleCode(.init(identifier: input)) == expected)
    }

    @Test("Azure code mapping", arguments: [
        ("ko", "ko"),
        ("en", "en"),
        ("ja", "ja"),
        ("zh-Hans", "zh-Hans"),
        ("zh-Hant", "zh-Hant"),
        ("pt", "pt"),
        ("pt-BR", "pt"),
        ("pt-PT", "pt-pt"),
        ("fr-CA", "fr-ca"),
        ("xx", "xx"),
    ])
    func azureCode(input: String, expected: String) {
        #expect(LanguageCodeMapper.toAzureCode(.init(identifier: input)) == expected)
    }
}
