import CoreGraphics
@testable import ScreenTranslate

/// 호출마다 정해진 글자를 돌려주는 가짜 인식 ("" = 글자 없음). 다 쓰면 마지막 값을 반복한다.
@MainActor
final class ScriptedOCRProvider: OCRProvider {
    var results: [String]
    private(set) var callCount = 0

    init(_ results: [String]) {
        self.results = results
    }

    func recognize(image: CGImage) async throws -> OCRResult {
        let text = results[min(callCount, results.count - 1)]
        callCount += 1
        if text.isEmpty { throw OCRError.noTextFound }
        return OCRResult(text: text, detectedLanguage: nil, confidence: 1)
    }
}
