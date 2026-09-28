import Vision
import CoreGraphics
import Foundation

/// Swift-native Vision API (macOS 15+)의 RecognizeTextRequest를 사용한다.
/// 레거시 VNRecognizeTextRequest 대신 async/await 네이티브 API로 구현.
final class VisionOCRProvider: OCRProvider {
    private let recognitionLevel: RecognizeTextRequest.RecognitionLevel

    /// 실시간 번역은 반복 호출 비용 때문에 수준을 바꿔 쓸 수 있다 (측정 결과에 따름)
    init(recognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate) {
        self.recognitionLevel = recognitionLevel
    }

    func recognize(image: CGImage) async throws -> OCRResult {
        var request = RecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: image)

        let textsWithConfidence: [(String, Float)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, candidate.confidence)
        }

        if textsWithConfidence.isEmpty {
            throw OCRError.noTextFound
        }

        let text = textsWithConfidence.map(\.0).joined(separator: "\n")
        let avgConfidence = textsWithConfidence.map(\.1).reduce(0, +) / Float(textsWithConfidence.count)

        // 감지된 언어 추출 — v2에서 NLLanguageRecognizer로 보강
        let detectedLanguage: Locale.Language? = nil

        return OCRResult(
            text: text,
            detectedLanguage: detectedLanguage,
            confidence: avgConfidence
        )
    }
}

extension VisionOCRProvider {
    /// 실시간 번역용 — 초당 여러 번 부르므로 빠른 인식을 쓴다.
    /// 2026-09-29 자막 시뮬레이터 측정: 정확 모드 CPU 48%·반응 1.25초 → 빠른 모드 27%·0.73초, 자막 9/9 같은 번역
    /// (정확 모드는 호출마다 Neural Engine 모델 준비 비용이 커서 반복 호출에 맞지 않는다)
    static func liveTranslation() -> VisionOCRProvider {
        VisionOCRProvider(recognitionLevel: .fast)
    }
}
