import Foundation
import Observation
import OSLog
import Translation

private let logger = Logger(subsystem: "com.app.screentranslate", category: "languagepack")

/// 언어 쌍 상태 조회 — 테스트에서 대체한다.
nonisolated protocol LanguageStatusChecking: Sendable {
    func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status
}

/// Apple Translation의 LanguageAvailability를 그대로 쓰는 기본 구현.
/// LanguageAvailability는 클래스이고 Sendable 선언이 없지만 async API로 어느 컨텍스트에서든
/// 호출하도록 설계된 객체라, 인스턴스 하나를 재사용한다 (호출마다 생성하지 않는다).
nonisolated struct AppleLanguageStatusChecker: LanguageStatusChecking {
    nonisolated(unsafe) private let availability = LanguageAvailability()

    func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        await availability.status(from: source, to: target)
    }
}

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

    @ObservationIgnored private let checker: LanguageStatusChecking
    @ObservationIgnored private let languageCodes: [String]

    init(
        checker: LanguageStatusChecking = AppleLanguageStatusChecker(),
        languageCodes: [String] = AppSettings.supportedLanguages.map(\.code)
    ) {
        self.checker = checker
        self.languageCodes = languageCodes
    }

    /// 모든 언어의 개별 설치 상태를 교차 확인으로 판별한다.
    ///
    /// `LanguageAvailability.status(from:to:)`는 **언어 쌍** 상태를 반환하므로,
    /// 개별 언어 설치 여부를 알기 위해 여러 쌍을 교차 확인한다.
    /// 어떤 쌍이든 `.installed`이면 해당 쌍의 양쪽 언어 모두 개별 설치된 것으로 판단한다.
    ///
    /// 조회는 TaskGroup으로 병렬 수행하고, 결과는 한 번에 대입해 SwiftUI 무효화를 한 번만 일으킨다.
    func refreshAllStatuses() async {
        let codes = languageCodes
        let checker = self.checker
        var installedSet: Set<String> = []

        // Phase 1: 영어를 기준으로 각 언어의 설치 여부를 확인 (O(n), 병렬)
        let englishPairs = codes.filter { $0 != "en" }.map { ("en", $0) }
        for (pair, status) in await Self.check(pairs: englishPairs, using: checker) where status == .installed {
            installedSet.insert(pair.0)
            installedSet.insert(pair.1)
        }

        // Phase 1b: 영어가 설치되지 않은 경우에만 교차 확인 폴백
        // (언어별로 병렬, 각 언어 안에서는 설치된 쌍을 찾는 즉시 중단)
        if !installedSet.contains("en") {
            let found = await withTaskGroup(of: (String, String)?.self) { group in
                for code in codes {
                    group.addTask {
                        for other in codes where other != code {
                            let status = await checker.status(
                                from: Locale.Language(identifier: code),
                                to: Locale.Language(identifier: other)
                            )
                            if status == .installed { return (code, other) }
                        }
                        return nil
                    }
                }
                var pairs: [(String, String)] = []
                for await pair in group {
                    if let pair { pairs.append(pair) }
                }
                return pairs
            }
            for (a, b) in found {
                installedSet.insert(a)
                installedSet.insert(b)
            }
        }

        // Phase 2: 개별 상태 설정
        var statuses: [String: LanguageStatus] = [:]
        for code in codes where installedSet.contains(code) {
            statuses[code] = .installed
        }
        let pending = codes.filter { !installedSet.contains($0) }
        // 기준 언어는 정렬해 결정적으로 고른다 (Set 순회 순서는 실행마다 다르다)
        if let reference = installedSet.sorted().first {
            let results = await Self.check(pairs: pending.map { ($0, reference) }, using: checker)
            for (pair, status) in results {
                statuses[pair.0] = (status == .unsupported) ? .unsupported : .available
            }
        } else {
            // 어떤 언어도 설치되지 않은 경우
            for code in pending { statuses[code] = .available }
        }

        languageStatuses = statuses
        logger.debug("개별 언어 상태: \(statuses.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
    }

    /// 이미 설치된 언어 중 하나를 반환한다 (다운로드 트리거 시 쌍 구성용). 결정적으로 정렬 첫 항목.
    func findInstalledLanguage(excluding code: String) -> String? {
        languageStatuses
            .filter { $0.key != code && $0.value == .installed }
            .keys
            .sorted()
            .first
    }

    /// 여러 언어 쌍의 상태를 병렬로 조회한다.
    private static func check(
        pairs: [(String, String)],
        using checker: LanguageStatusChecking
    ) async -> [((String, String), LanguageAvailability.Status)] {
        await withTaskGroup(of: ((String, String), LanguageAvailability.Status).self) { group in
            for pair in pairs {
                group.addTask {
                    let status = await checker.status(
                        from: Locale.Language(identifier: pair.0),
                        to: Locale.Language(identifier: pair.1)
                    )
                    return (pair, status)
                }
            }
            var results: [((String, String), LanguageAvailability.Status)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
}
