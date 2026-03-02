import Foundation
import Observation
import OSLog
import Translation

private let logger = Logger(subsystem: "com.app.screentranslate", category: "languagepack")

@MainActor
@Observable
final class LanguagePackManager {
    /// 각 언어 코드별 상태 (타겟 언어 기준)
    var statuses: [String: LanguageStatus] = [:]

    /// 각 언어 코드별 상태 (원문 언어 기준 — 현재 타겟 → 각 원문 방향)
    var sourceStatuses: [String: LanguageStatus] = [:]

    enum LanguageStatus: Equatable {
        case installed
        case available   // 다운로드 가능 (미설치)
        case unsupported
        case checking
    }

    private let availability = LanguageAvailability()

    /// 현재 원문 언어 기준으로 모든 타겟 언어 상태를 확인한다.
    /// 원문이 "auto"이면 "en"을 기준으로 확인 (대부분의 쌍 커버).
    func refreshStatuses(sourceCode: String) async {
        let baseLang: Locale.Language
        if sourceCode == "auto" {
            baseLang = Locale.Language(identifier: "en")
        } else {
            baseLang = Locale.Language(identifier: sourceCode)
        }

        for lang in AppSettings.supportedLanguages {
            statuses[lang.code] = .checking
        }

        for lang in AppSettings.supportedLanguages {
            let target = Locale.Language(identifier: lang.code)
            let status = await availability.status(from: baseLang, to: target)
            switch status {
            case .installed:
                statuses[lang.code] = .installed
            case .supported:
                statuses[lang.code] = .available
            case .unsupported:
                statuses[lang.code] = .unsupported
            @unknown default:
                statuses[lang.code] = .unsupported
            }
        }
    }

    /// 현재 타겟 언어 기준으로 모든 원문 언어 상태를 확인한다.
    func refreshSourceStatuses(targetCode: String) async {
        let targetLang = Locale.Language(identifier: targetCode)

        for lang in AppSettings.supportedLanguages {
            sourceStatuses[lang.code] = .checking
        }

        for lang in AppSettings.supportedLanguages {
            let source = Locale.Language(identifier: lang.code)
            let status = await availability.status(from: source, to: targetLang)
            switch status {
            case .installed:
                sourceStatuses[lang.code] = .installed
            case .supported:
                sourceStatuses[lang.code] = .available
            case .unsupported:
                sourceStatuses[lang.code] = .unsupported
            @unknown default:
                sourceStatuses[lang.code] = .unsupported
            }
        }
    }

    /// 다운로드는 `.translationTask` 뷰 모디파이어를 통해 자동 트리거된다.
    /// 미설치 언어로 번역 시도 시 시스템이 다운로드 프롬프트를 자동 표시한다.
}
