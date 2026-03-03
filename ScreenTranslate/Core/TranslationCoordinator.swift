import CoreGraphics
import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.app.screentranslate", category: "translation")

/// OCR → Translation 데이터 파이프라인 상태 머신.
/// OCRProvider와 TranslationProvider를 주입받아 사용한다.
@Observable
final class TranslationCoordinator {
    var state: State = .idle

    /// H4: 진행 중인 Task 참조를 보관하여 ESC 취소를 지원한다.
    private var currentTask: Task<Void, Never>?

    nonisolated enum State: Equatable {
        case idle
        case recognizing
        case translating
        case completed(TranslationResult)
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recognizing, .recognizing), (.translating, .translating):
                return true
            case (.completed(let a), .completed(let b)):
                return a.translatedText == b.translatedText
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    nonisolated struct TranslationResult: Sendable {
        let sourceText: String           // 원문 (OCR 결과)
        let translatedText: String       // 번역문
        let lowConfidence: Bool          // OCR 신뢰도가 낮은 경우
        let sourceLanguage: Locale.Language?  // 감지된 소스 언어
    }

    private let ocrProvider: OCRProvider
    private(set) var translationProvider: TranslationProvider
    var sourceLanguage: Locale.Language?  // nil이면 자동 감지
    var targetLanguage: Locale.Language

    init(
        ocrProvider: OCRProvider,
        translationProvider: TranslationProvider,
        targetLanguage: Locale.Language = Locale.Language(identifier: "ko")
    ) {
        self.ocrProvider = ocrProvider
        self.translationProvider = translationProvider
        self.targetLanguage = targetLanguage
    }

    /// 이미지에서 텍스트를 인식하고 번역한다.
    /// H4: Task 참조를 보관하여 ESC 취소를 지원한다.
    /// C4: 각 단계 사이에서 state를 변경하여 UI가 중간 상태를 관찰할 수 있게 한다.
    func startProcessing(image: CGImage) {
        currentTask?.cancel()
        // 동기적으로 state를 즉시 변경 — Task 내부에서 설정하면
        // 폴링 루프가 .idle을 먼저 감지하여 즉시 break되는 레이스 컨디션 발생
        state = .recognizing
        currentTask = Task {

            do {
                let ocrResult = try await ocrProvider.recognize(image: image)
                try Task.checkCancellation()  // ESC 체크 포인트

                logger.debug("OCR 결과: \"\(ocrResult.text)\" (신뢰도: \(ocrResult.confidence), 언어: \(ocrResult.detectedLanguage?.minimalIdentifier ?? "nil"))")
                logger.debug("타겟 언어: \(self.targetLanguage.minimalIdentifier)")

                // C4: OCR 완료 후, 번역 호출 전에 state를 변경해야 UI가 "번역 중..." 표시
                state = .translating

                // OCR이 언어를 감지했으면 그 값 사용, 아니면 설정의 소스 언어 사용
                let effectiveSource = ocrResult.detectedLanguage ?? sourceLanguage
                let translated = try await translationProvider.translate(
                    text: ocrResult.text,
                    from: effectiveSource,
                    to: targetLanguage
                )
                try Task.checkCancellation()  // ESC 체크 포인트
                logger.debug("번역 성공: \"\(translated)\"")

                let result = TranslationResult(
                    sourceText: ocrResult.text,
                    translatedText: translated,
                    lowConfidence: ocrResult.confidence < 0.3,
                    sourceLanguage: effectiveSource
                )
                state = .completed(result)
            } catch is CancellationError {
                state = .idle  // 조용히 취소
            } catch OCRError.noTextFound {
                state = .failed(L10n.noTextFound)
            } catch TranslationError.languageNotSupported {
                state = .failed(L10n.unsupportedLanguagePair)
            } catch {
                logger.error("번역 파이프라인 에러: \(error)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// ESC 등으로 진행 중인 작업을 취소한다.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    func reset() {
        cancel()
    }

    /// 런타임에 Provider를 교체한다 (설정 변경 시).
    func updateProvider(_ provider: TranslationProvider) {
        self.translationProvider = provider
    }
}
