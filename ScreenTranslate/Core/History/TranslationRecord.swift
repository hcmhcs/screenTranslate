import Foundation
import SwiftData

@Model
final class TranslationRecord {
    var id: UUID
    var timestamp: Date
    var sourceText: String
    var translatedText: String?
    var errorMessage: String?
    var sourceLanguageCode: String?
    var targetLanguageCode: String

    init(
        sourceText: String,
        translatedText: String? = nil,
        errorMessage: String? = nil,
        sourceLanguageCode: String? = nil,
        targetLanguageCode: String
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.errorMessage = errorMessage
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }

    var isSuccess: Bool { translatedText != nil }
}
