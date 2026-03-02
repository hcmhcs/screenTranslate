import CoreGraphics
import Foundation

/// OCR 인식 결과.
nonisolated struct OCRResult: Sendable {
    /// 인식된 텍스트
    let text: String
    /// 감지된 소스 언어 (번역 Provider에 전달)
    let detectedLanguage: Locale.Language?
    /// 인식 신뢰도 (0.0 ~ 1.0)
    let confidence: Float
}

/// OCR 처리를 담당하는 Provider 프로토콜.
/// 새로운 OCR 엔진(Tesseract, 커스텀 ML 등)은 이 프로토콜을 채택하면 된다.
protocol OCRProvider: Sendable {
    func recognize(image: CGImage) async throws -> OCRResult
}

nonisolated enum OCRError: LocalizedError {
    case noTextFound
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "선택한 영역에서 텍스트를 찾을 수 없습니다."
        case .recognitionFailed(let reason):
            return "텍스트 인식 실패: \(reason)"
        }
    }
}
