# Phase 2: Core Providers

> [← Phase 1](./phase-1-project-setup.md) | [Overview](./00-overview.md) | [Phase 3 →](./phase-3-capture-pipeline.md)

---

## Task 2: OCR Provider 레이어

**Files:**
- Create: `ScreenTranslate/Core/OCR/OCRProvider.swift`
- Create: `ScreenTranslate/Core/OCR/VisionOCRProvider.swift`
- Create: `ScreenTranslateTests/Core/OCR/VisionOCRProviderTests.swift`

**Step 1: OCRProvider 프로토콜 및 OCRResult 작성**

`ScreenTranslate/Core/OCR/OCRProvider.swift`:

```swift
import CoreGraphics
import Foundation

/// OCR 인식 결과.
struct OCRResult: Sendable {
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

extension CGImage: @unchecked Sendable {}

enum OCRError: LocalizedError {
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
```

**Step 2: VisionOCRProvider 구현**

`ScreenTranslate/Core/OCR/VisionOCRProvider.swift`:

```swift
import Vision
import CoreGraphics
import Foundation

/// Swift-native Vision API (macOS 15+)의 RecognizeTextRequest를 사용한다.
/// 레거시 VNRecognizeTextRequest 대신 async/await 네이티브 API로 구현.
final class VisionOCRProvider: OCRProvider {
    func recognize(image: CGImage) async throws -> OCRResult {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
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
```

> **변경점**: macOS 15+의 Swift-native `RecognizeTextRequest` API를 사용하여 `async/await`으로 직접 호출한다. 레거시 `VNRecognizeTextRequest`의 completion handler 패턴과 `withCheckedThrowingContinuation` 래핑이 불필요해졌다.

**Step 3: 테스트 작성**

`ScreenTranslateTests/Core/OCR/VisionOCRProviderTests.swift`:

```swift
import XCTest
import CoreGraphics
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
        } catch OCRError.noTextFound {
            // Expected
        }
    }

    func test_recognize_returnsOCRResult_withConfidence() async throws {
        guard let image = loadTestImage(named: "test_text_image") else {
            XCTSkip("테스트 이미지 없음 — 수동으로 추가 필요")
            return
        }

        let result = try await sut.recognize(image: image)

        XCTAssertFalse(result.text.isEmpty)
        XCTAssertGreaterThan(result.confidence, 0)
        XCTAssertLessThanOrEqual(result.confidence, 1.0)
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
```

**Step 4: 테스트 실행**

```
Xcode → Product → Test (Cmd+U)
```

Expected: `test_recognize_withBlankImage_throwsNoTextFound` PASS, `test_recognize_returnsOCRResult_withConfidence` SKIP

**Step 5: Commit**

```bash
git add ScreenTranslate/Core/OCR/ ScreenTranslateTests/Core/OCR/
git commit -m "feat: add OCRProvider protocol with OCRResult and VisionOCRProvider"
```

---

## Task 3: Translation Provider 레이어 + TranslationBridge

**Files:**
- Create: `ScreenTranslate/Core/Translation/TranslationProvider.swift`
- Create: `ScreenTranslate/Core/Translation/AppleTranslationProvider.swift`
- Create: `ScreenTranslate/Core/Translation/TranslationBridge.swift`
- Create: `ScreenTranslateTests/Core/Translation/MockTranslationProvider.swift`
- Create: `ScreenTranslateTests/Core/Translation/TranslationProviderTests.swift`

**Step 1: TranslationProvider 프로토콜 작성**

`ScreenTranslate/Core/Translation/TranslationProvider.swift`:

```swift
import Foundation

/// 번역을 담당하는 Provider 프로토콜.
/// 새로운 번역 엔진(OpenAI, DeepL, Argos 등)은 이 프로토콜을 채택하면 된다.
protocol TranslationProvider: Sendable {
    /// 텍스트를 번역한다.
    /// - Parameters:
    ///   - text: 번역할 원문
    ///   - source: 소스 언어 (nil이면 자동 감지)
    ///   - target: 타겟 언어
    /// - Returns: 번역된 텍스트
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String

    /// Provider 이름 (설정 UI 표시용)
    var name: String { get }

    /// API Key가 필요한지 여부
    var requiresAPIKey: Bool { get }
}

enum TranslationError: LocalizedError {
    case translationFailed(String)
    case languageNotSupported
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .translationFailed(let reason):
            return "번역 실패: \(reason)"
        case .languageNotSupported:
            return "이 언어 조합은 지원되지 않습니다."
        case .apiKeyMissing:
            return "API Key가 설정되지 않았습니다."
        }
    }
}
```

**Step 2: TranslationBridge 작성 (핵심 — SwiftUI ↔ TranslationSession)**

`ScreenTranslate/Core/Translation/TranslationBridge.swift`:

```swift
import SwiftUI
import Translation

/// Apple Translation Framework는 SwiftUI `.translationTask` modifier를 통해서만
/// TranslationSession을 획득할 수 있다. TranslationBridge는 크기 0의 투명 뷰로,
/// 앱 UI 계층에 항상 존재하며 번역 요청을 처리한다.
@Observable
@MainActor
final class TranslationBridge {
    static let shared = TranslationBridge()

    /// 번역할 텍스트 (외부에서 설정)
    var pendingText: String?

    /// 번역 결과
    var translatedText: String?

    /// 에러 메시지
    var errorMessage: String?

    /// 현재 번역 중인지 여부
    var isTranslating = false

    /// 번역 설정 (변경 시 .translationTask가 재트리거됨)
    var configuration: TranslationSession.Configuration?

    /// continuation을 저장하여 async/await 패턴으로 사용
    private var continuation: CheckedContinuation<String, Error>?

    /// async/await 인터페이스로 번역을 요청한다.
    /// ⚠️ C1: 이전 continuation이 남아있으면 에러로 resume한 후 교체한다.
    /// 그렇지 않으면 resume 없이 덮어써져 크래시가 발생한다.
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        // C1: 기존 continuation이 있으면 취소 처리
        if let existing = continuation {
            existing.resume(throwing: TranslationError.translationFailed("새 번역 요청으로 취소됨"))
            continuation = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.pendingText = text
            self.isTranslating = true
            self.translatedText = nil
            self.errorMessage = nil

            // C5: configuration을 nil로 리셋한 후 새 값을 설정하여
            // 같은 언어쌍이라도 .translationTask가 재트리거되도록 한다.
            self.configuration = nil
            self.configuration = TranslationSession.Configuration(
                source: source,
                target: target
            )
        }
    }

    /// .translationTask의 콜백에서 호출된다.
    func handleSession(_ session: TranslationSession) {
        guard let text = pendingText else {
            completionWithError("번역할 텍스트가 없습니다.")
            return
        }

        Task {
            do {
                let response = try await session.translate(text)
                self.translatedText = response.targetText
                self.isTranslating = false
                self.continuation?.resume(returning: response.targetText)
                self.continuation = nil
            } catch {
                completionWithError(error.localizedDescription)
            }
        }
    }

    private func completionWithError(_ message: String) {
        self.errorMessage = message
        self.isTranslating = false
        self.continuation?.resume(throwing: TranslationError.translationFailed(message))
        self.continuation = nil
    }
}

/// 앱 UI 계층에 삽입하는 투명 뷰.
/// ScreenTranslateApp의 body에 overlay로 추가한다.
struct TranslationBridgeView: View {
    @State private var bridge = TranslationBridge.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(bridge.configuration) { session in
                bridge.handleSession(session)
            }
    }
}
```

**Step 3: AppleTranslationProvider 구현 (TranslationBridge 활용)**

`ScreenTranslate/Core/Translation/AppleTranslationProvider.swift`:

```swift
import Foundation

/// ⚠️ H3: TranslationProvider 프로토콜의 translate()는 nonisolated이므로
/// 구현체 메서드에 직접 @MainActor를 붙이면 Swift 6에서 프로토콜 준수 위반이 된다.
/// 대신 메서드 내부에서 MainActor.run으로 호출한다.
final class AppleTranslationProvider: TranslationProvider {
    let name = "Apple Translation"
    let requiresAPIKey = false

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        return try await MainActor.run {
            try await TranslationBridge.shared.translate(text: text, from: source, to: target)
        }
    }
}
```

**Step 4: 테스트용 Mock 작성**

`ScreenTranslateTests/Core/Translation/MockTranslationProvider.swift`:

```swift
import Foundation
@testable import ScreenTranslate

final class MockTranslationProvider: TranslationProvider {
    let name = "Mock"
    let requiresAPIKey = false

    var shouldFail = false
    var translatedText = "번역된 텍스트"
    var lastReceivedText: String?

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        lastReceivedText = text
        if shouldFail { throw TranslationError.translationFailed("Mock 실패") }
        return translatedText
    }
}
```

**Step 5: Mock을 이용한 Provider 테스트 작성**

`ScreenTranslateTests/Core/Translation/TranslationProviderTests.swift`:

```swift
import XCTest
@testable import ScreenTranslate

final class MockTranslationProviderTests: XCTestCase {
    private var sut: MockTranslationProvider!

    override func setUp() {
        sut = MockTranslationProvider()
    }

    func test_translate_success_returnsTranslatedText() async throws {
        sut.translatedText = "Hello World"

        let result = try await sut.translate(
            text: "안녕하세요",
            from: Locale.Language(identifier: "ko"),
            to: Locale.Language(identifier: "en")
        )

        XCTAssertEqual(result, "Hello World")
        XCTAssertEqual(sut.lastReceivedText, "안녕하세요")
    }

    func test_translate_failure_throwsError() async {
        sut.shouldFail = true

        do {
            _ = try await sut.translate(text: "test", from: nil, to: Locale.Language(identifier: "ko"))
            XCTFail("실패해야 한다")
        } catch TranslationError.translationFailed {
            // Expected
        } catch {
            XCTFail("예상치 못한 에러: \(error)")
        }
    }
}
```

**Step 6: 테스트 실행**

```
Xcode → Product → Test (Cmd+U)
```

Expected: Mock 테스트 2개 모두 PASS

**Step 7: Commit**

```bash
git add ScreenTranslate/Core/Translation/ ScreenTranslateTests/Core/Translation/
git commit -m "feat: add TranslationProvider, TranslationBridge, and AppleTranslationProvider"
```
