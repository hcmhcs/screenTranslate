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

                // OCR 텍스트 전처리: 줄바꿈을 공백으로 치환하여 번역 품질 향상
                let textForTranslation: String
                if AppSettings.shared.ocrTextPreprocessing {
                    textForTranslation = Self.preprocessOCRText(ocrResult.text)
                } else {
                    textForTranslation = ocrResult.text
                }

                // OCR이 언어를 감지했으면 그 값 사용, 아니면 설정의 소스 언어 사용
                let effectiveSource = ocrResult.detectedLanguage ?? sourceLanguage
                let translated = try await translationProvider.translate(
                    text: textForTranslation,
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

    /// OCR 텍스트 전처리: 줄바꿈 병합, CJK 처리, 하이픈 제거, 특수 공백 정리, Unicode 정규화.
    static func preprocessOCRText(_ text: String) -> String {
        // 0. Unicode 정규화: OCR이 인식하는 특수 유니코드 문자를 표준 ASCII로 변환
        var result = text
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // " → "
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // " → "
            .replacingOccurrences(of: "\u{2018}", with: "'")   // ' → '
            .replacingOccurrences(of: "\u{2019}", with: "'")   // ' → '
            .replacingOccurrences(of: "\u{2014}", with: "-")   // — (em dash) → -
            .replacingOccurrences(of: "\u{2013}", with: "-")   // – (en dash) → -
            .replacingOccurrences(of: "\u{2026}", with: "...")  // … → ...

        // 1. 특수 공백(탭, non-breaking space 등)을 일반 공백으로 치환
        result = result.replacingOccurrences(
            of: "[\\t\\u{00A0}\\u{2003}\\u{2002}]",
            with: " ",
            options: .regularExpression
        )
        // 2. 하이픈 줄바꿈 제거 (영문 단어 분리: "transla-\ntion" → "translation")
        result = result.replacingOccurrences(
            of: "-\\s*\\n",
            with: "",
            options: .regularExpression
        )
        // 2.5 단락 경계 감지: 문장 종결 + 짧은 줄 → \n을 \n\n으로 업그레이드
        result = Self.detectParagraphBreaks(result)
        // 3. 이중 줄바꿈(단락 구분)을 임시 플레이스홀더로 보존
        let placeholder = "\u{FFFC}"
        result = result.replacingOccurrences(of: "\n\n", with: placeholder)
        // 4. CJK 줄바꿈 처리: 양쪽이 CJK 문자이면 공백 없이 연결
        result = result.replacingOccurrences(
            of: "([\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}])\\n([\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}])",
            with: "$1$2",
            options: .regularExpression
        )
        // 5. 나머지 단일 줄바꿈을 공백으로 치환 (라틴 등)
        result = result.replacingOccurrences(of: "\n", with: " ")
        // 6. 플레이스홀더를 이중 줄바꿈으로 복원
        result = result.replacingOccurrences(of: placeholder, with: "\n\n")
        // 7. 다중 공백을 단일 공백으로 정리
        result = result.replacingOccurrences(
            of: " +",
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 단락 경계 감지: 문장 종결 부호 + 짧은 줄 → \n을 \n\n으로 업그레이드.
    /// 줄 수가 3 미만이거나 유효 줄(5자 이상)이 3 미만이면 휴리스틱을 적용하지 않는다.
    private static func detectParagraphBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 3 else { return text }

        // 유효 줄(5자 이상)의 길이 배열 → 중앙값 계산
        let lengths = lines.compactMap { line -> Int? in
            let len = line.trimmingCharacters(in: .whitespaces).count
            return len >= 5 ? len : nil
        }
        guard lengths.count >= 3 else { return text }
        let median = lengths.sorted()[lengths.count / 2]
        let threshold = Double(median) * 0.75

        let sentenceEndPattern = "[.!?:;。！？；][\"')）」』]*\\s*$"

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            result.append(line)

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 빈 줄, 마지막 줄, 다음 줄이 이미 빈 줄이면 건너뛴다
            guard !trimmed.isEmpty,
                  i < lines.count - 1,
                  !lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }

            let endsWithPunctuation = trimmed.range(
                of: sentenceEndPattern, options: .regularExpression) != nil
            let isShort = Double(trimmed.count) < threshold

            if endsWithPunctuation && isShort {
                result.append("")  // 빈 줄 삽입 → joined 시 \n\n 생성
            }
        }

        return result.joined(separator: "\n")
    }
}
