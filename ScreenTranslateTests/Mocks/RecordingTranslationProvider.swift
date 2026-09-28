import Foundation
@testable import ScreenTranslate

/// 요청을 기록하고 정해진 결과를 순서대로 돌려주는 가짜 번역 (다 쓰면 마지막 결과 반복, 없으면 "번역:원문")
@MainActor
final class RecordingTranslationProvider: TranslationProvider {
    let name = "Recording"
    let requiresAPIKey = false
    var outcomes: [Result<String, Error>] = []
    private(set) var requests: [String] = []

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        requests.append(text)
        guard !outcomes.isEmpty else { return "번역:\(text)" }
        return try outcomes[min(requests.count - 1, outcomes.count - 1)].get()
    }
}
