import Foundation

/// 실시간 번역 시작 전 점검 — 언어팩이 없으면 보이지 않는 브리지 창에 다운로드 창이 걸려 30초간 멈추므로 먼저 막는다.
enum LiveTranslatePreflight {
    /// 설치되지 않은 언어의 표시 이름 (원문이 "auto"면 목표 언어만 본다)
    static func missingLanguageNames(
        statuses: [String: LanguagePackManager.LanguageStatus],
        sourceCode: String,
        targetCode: String
    ) -> [String] {
        let codes = (sourceCode == "auto" ? [] : [sourceCode]) + [targetCode]
        return codes
            .filter { statuses[$0] != .installed }
            .map { code in AppSettings.supportedLanguages.first { $0.code == code }?.name ?? code }
    }
}
