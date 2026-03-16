import Foundation
import Observation
import OSLog
import Translation

private let logger = Logger(subsystem: "com.app.screentranslate", category: "languagepack")

@MainActor
@Observable
final class LanguagePackManager {
    /// 개별 언어의 설치 상태 (쌍 기반이 아닌 개별 언어 기준)
    var languageStatuses: [String: LanguageStatus] = [:]

    enum LanguageStatus: Equatable {
        case installed
        case available   // 다운로드 가능 (미설치)
        case unsupported
    }

    private let availability = LanguageAvailability()

    /// 모든 언어의 개별 설치 상태를 교차 확인으로 판별한다.
    ///
    /// `LanguageAvailability.status(from:to:)`는 **언어 쌍** 상태를 반환하므로,
    /// 개별 언어 설치 여부를 알기 위해 여러 쌍을 교차 확인한다.
    /// 어떤 쌍이든 `.installed`이면 해당 쌍의 양쪽 언어 모두 개별 설치된 것으로 판단한다.
    func refreshAllStatuses() async {
        let langs = AppSettings.supportedLanguages
        var installedSet: Set<String> = []

        // Phase 1: 영어를 기준으로 각 언어의 설치 여부를 확인 (O(n) 최적 경로)
        let enLang = Locale.Language(identifier: "en")
        for lang in langs where lang.code != "en" {
            let target = Locale.Language(identifier: lang.code)
            let status = await availability.status(from: enLang, to: target)
            if status == .installed {
                installedSet.insert("en")
                installedSet.insert(lang.code)
            }
        }

        // Phase 1b: 영어가 설치되지 않은 경우에만 기존 교차 확인 폴백
        if !installedSet.contains("en") {
            for i in 0..<langs.count {
                guard !installedSet.contains(langs[i].code) else { continue }
                let from = Locale.Language(identifier: langs[i].code)
                for j in 0..<langs.count where i != j {
                    let to = Locale.Language(identifier: langs[j].code)
                    let status = await availability.status(from: from, to: to)
                    if status == .installed {
                        installedSet.insert(langs[i].code)
                        installedSet.insert(langs[j].code)
                        break
                    }
                }
            }
        }

        // Phase 2: 개별 상태 설정
        for lang in langs {
            if installedSet.contains(lang.code) {
                languageStatuses[lang.code] = .installed
            } else {
                // 미설치 언어: 설치된 언어와 쌍으로 지원 여부 확인
                if let ref = installedSet.first {
                    let from = Locale.Language(identifier: lang.code)
                    let to = Locale.Language(identifier: ref)
                    let status = await availability.status(from: from, to: to)
                    languageStatuses[lang.code] = (status == .unsupported) ? .unsupported : .available
                } else {
                    // 어떤 언어도 설치되지 않은 경우
                    languageStatuses[lang.code] = .available
                }
            }
        }

        logger.debug("개별 언어 상태: \(self.languageStatuses.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
    }

    /// 이미 설치된 언어 중 하나를 반환한다 (다운로드 트리거 시 쌍 구성용).
    func findInstalledLanguage(excluding code: String) -> String? {
        languageStatuses.first(where: { $0.key != code && $0.value == .installed })?.key
    }
}
