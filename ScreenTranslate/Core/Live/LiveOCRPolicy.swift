import Foundation

/// 실시간 번역의 글자 인식 수준 선택.
/// 빠른 모드는 CPU를 절반 가까이 줄이지만(측정 48% → 27%) 라틴 문자 6개 언어만 읽는다 —
/// 일본어·중국어는 아예 못 읽고, 한국어·러시아어는 엉뚱한 글자로 읽어 틀린 번역이 확정된다 (2026-09-29 확인).
nonisolated enum LiveOCRPolicy {
    /// 원문 언어를 빠른 모드가 읽을 수 있을 때만 true. 자동 감지는 어떤 언어일지 모르므로 정확 모드.
    static func usesFastRecognition(sourceCode: String, fastLanguages: [Locale.Language]) -> Bool {
        guard sourceCode != "auto", let code = Locale.Language(identifier: sourceCode).languageCode else {
            return false
        }
        return fastLanguages.contains { $0.languageCode == code }
    }
}
