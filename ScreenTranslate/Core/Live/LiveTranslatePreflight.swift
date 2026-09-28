import Foundation
import Translation

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

    /// 자동 감지일 때 자막 글자의 언어가 목표 언어로 바로 번역되는지 (언어팩 설치 여부)
    static func readiness(for text: String, to target: Locale.Language) async -> LiveTranslationSession.Readiness {
        do {
            switch try await LanguageAvailability().status(for: text, to: target) {
            case .installed: return .ready
            case .supported: return .needsDownload
            case .unsupported: return .unsupported
            @unknown default: return .ready
            }
        } catch {
            return .ready  // 언어를 알아내지 못하면 번역을 시도하고, 실패 이유는 번역 쪽이 보여준다
        }
    }
}
