import Foundation
import Testing
@testable import ScreenTranslate

/// 실시간 번역의 글자 인식 수준 — 빠른 모드는 라틴 문자 6개 언어만 읽는다 (2026-09-29 macOS 26.5 확인).
@Suite struct LiveOCRPolicyTests {
    private let fast = ["de-DE", "en-US", "es-ES", "fr-FR", "it-IT", "pt-BR"].map { Locale.Language(identifier: $0) }

    @Test("fast recognition is used for a source language it can read")
    func fastForSupportedSource() {
        #expect(LiveOCRPolicy.usesFastRecognition(sourceCode: "en", fastLanguages: fast))
        #expect(LiveOCRPolicy.usesFastRecognition(sourceCode: "pt", fastLanguages: fast))
    }

    @Test("accurate recognition is used for languages fast mode cannot read",
          arguments: ["ja", "zh-Hans", "zh-Hant", "ko", "ru", "th", "ar"])
    func accurateForOtherScripts(code: String) {
        #expect(!LiveOCRPolicy.usesFastRecognition(sourceCode: code, fastLanguages: fast))
    }

    @Test("auto-detect uses accurate recognition — the subtitle could be in any language")
    func accurateForAuto() {
        #expect(!LiveOCRPolicy.usesFastRecognition(sourceCode: "auto", fastLanguages: fast))
    }
}
