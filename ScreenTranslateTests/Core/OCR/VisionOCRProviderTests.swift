import XCTest
import CoreGraphics
import ImageIO
@testable import ScreenTranslate

final class VisionOCRProviderTests: XCTestCase {
    private var sut: VisionOCRProvider!

    override func setUp() {
        sut = VisionOCRProvider()
    }

    func test_recognize_withBlankImage_throwsNoTextFound() async throws {
        let image = makeBlankImage(width: 100, height: 100)

        do {
            _ = try await sut.recognize(image: image)
            XCTFail("빈 이미지에서는 에러가 발생해야 한다")
        } catch is OCRError {
            // Expected — noTextFound
        }
    }

    func test_recognize_returnsOCRResult_withConfidence() async throws {
        guard let image = loadTestImage(named: "test_text_image") else {
            throw XCTSkip("테스트 이미지 없음 — 수동으로 추가 필요")
        }

        let result = try await sut.recognize(image: image)
        let resultText = result.text
        let resultConfidence = result.confidence

        XCTAssertFalse(resultText.isEmpty)
        XCTAssertGreaterThan(resultConfidence, 0)
        XCTAssertLessThanOrEqual(resultConfidence, 1.0)
    }

    // MARK: - Helpers

    private func makeBlankImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func loadTestImage(named name: String) -> CGImage? {
        guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
