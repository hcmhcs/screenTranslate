import Foundation

/// Apple Translation Framework를 활용하는 번역 Provider.
/// TranslationBridge를 통해 SwiftUI의 .translationTask에 접근한다.
///
/// NOTE: 프로젝트의 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor 설정으로
/// 프로토콜과 구현체 모두 MainActor이므로 MainActor.run 우회가 불필요하다.
final class AppleTranslationProvider: TranslationProvider {
    let name = "Apple Translation"
    let requiresAPIKey = false

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        try await TranslationBridge.shared.translate(text: text, from: source, to: target)
    }
}
