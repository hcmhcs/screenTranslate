import Testing
@testable import ScreenTranslate

/// 실시간 번역 시작 전 언어팩 점검.
@MainActor
@Suite struct LiveTranslatePreflightTests {
    private func name(_ code: String) -> String {
        AppSettings.supportedLanguages.first { $0.code == code }!.name
    }

    @Test("nothing is missing when the target is installed and the source is auto")
    func autoSourceInstalledTarget() {
        #expect(LiveTranslatePreflight.missingLanguageNames(
            statuses: ["ko": .installed], sourceCode: "auto", targetCode: "ko").isEmpty)
    }

    @Test("a target that is not installed is reported")
    func missingTarget() {
        #expect(LiveTranslatePreflight.missingLanguageNames(
            statuses: ["ko": .available], sourceCode: "auto", targetCode: "ko") == [name("ko")])
    }

    @Test("an explicit source is checked too, source first")
    func missingSourceAndTarget() {
        #expect(LiveTranslatePreflight.missingLanguageNames(
            statuses: [:], sourceCode: "ja", targetCode: "ko") == [name("ja"), name("ko")])
    }
}
