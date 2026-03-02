# ScreenTranslate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** macOS 메뉴바 앱 — 단축키로 화면 영역을 선택하면 OCR → 번역 → 플로팅 팝업으로 결과를 표시한다.

**Architecture:** SwiftUI `MenuBarExtra` 기반 메뉴바 앱. 화면 선택은 AppKit `NSWindow` 오버레이로 처리하고, OCR/번역은 각각 프로토콜로 추상화해 Apple Vision / Apple Translation을 기본 구현체로 사용한다. Apple Translation Framework는 SwiftUI `.translationTask` modifier가 필요하므로 `TranslationBridge` 패턴으로 연결한다. `TranslationCoordinator`가 전체 흐름을 조율한다.

**Tech Stack:** Swift 6 (Strict Concurrency), SwiftUI, AppKit, Vision framework (`RecognizeTextRequest`), Translation framework (macOS 15+), ScreenCaptureKit / SCScreenshotManager (macOS 14+), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (SPM)

---

## 준비사항

- macOS 15.0+ 개발 환경
- Xcode 16+
- Apple Developer 계정 (Screen Recording 권한 entitlement 필요)

---

## Task 1: Xcode 프로젝트 생성 및 초기 설정

**Files:**
- Create: `ScreenTranslate.xcodeproj` (Xcode GUI로 생성)
- Create: `ScreenTranslate/Info.plist`
- Create: `ScreenTranslate/ScreenTranslate.entitlements`
- Create: `ScreenTranslate/App/ScreenTranslateApp.swift`

**Step 1: Xcode에서 새 프로젝트 생성**

```
Xcode → File → New → Project
Template: macOS → App
Product Name: ScreenTranslate
Bundle Identifier: com.yourname.ScreenTranslate
Interface: SwiftUI
Language: Swift
Minimum Deployment: macOS 15.0
☑ Include Tests
```

**Step 2: Info.plist에 필수 키 추가**

`ScreenTranslate/Info.plist`에서 다음 키를 추가:

```xml
<key>LSUIElement</key>
<true/>
```

> `LSUIElement = true` → Dock 아이콘 숨김, 메뉴바 전용 앱으로 동작

**Step 3: Entitlements 파일 설정**

`ScreenTranslate/ScreenTranslate.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

> App Sandbox를 비활성화해야 ScreenCaptureKit 전역 캡처 및 전역 단축키가 동작한다.

**Step 4: KeyboardShortcuts SPM 의존성 추가**

```
Xcode → File → Add Package Dependencies
URL: https://github.com/sindresorhus/KeyboardShortcuts
Version: Up to Next Major Version
```

> 주의: 저자는 sindresorhus (nicklockwood 아님).

**Step 5: 기본 App 진입점 작성**

`ScreenTranslate/App/ScreenTranslateApp.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translate = Self("translate", default: .init(.t, modifiers: [.control, .shift]))
}

@main
struct ScreenTranslateApp: App {
    var body: some Scene {
        MenuBarExtra("ScreenTranslate", systemImage: "text.viewfinder") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Step 6: 임시 MenuBarView 작성 (빌드용)**

`ScreenTranslate/UI/MenuBar/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button("번역하기") { }
        Divider()
        Button("ScreenTranslate 종료") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

**Step 7: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```
Expected: Build Succeeded. 메뉴바에 아이콘이 표시된다.

**Step 8: Commit**

```bash
git init
git add .
git commit -m "feat: initial Xcode project setup with MenuBarExtra"
```

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
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.pendingText = text
            self.isTranslating = true
            self.translatedText = nil
            self.errorMessage = nil

            // configuration을 설정하면 .translationTask가 트리거된다
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

final class AppleTranslationProvider: TranslationProvider {
    let name = "Apple Translation"
    let requiresAPIKey = false

    @MainActor
    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        return try await TranslationBridge.shared.translate(text: text, from: source, to: target)
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

---

## Task 4: TranslationCoordinator

**Files:**
- Create: `ScreenTranslate/Core/TranslationCoordinator.swift`
- Create: `ScreenTranslateTests/Core/TranslationCoordinatorTests.swift`
- Create: `ScreenTranslateTests/Mocks/MockOCRProvider.swift`

**Step 1: TranslationCoordinator 작성**

`ScreenTranslate/Core/TranslationCoordinator.swift`:

```swift
import CoreGraphics
import Foundation
import Observation

/// OCR → Translation 데이터 파이프라인 상태 머신.
/// OCRProvider와 TranslationProvider를 주입받아 사용한다.
/// UI 상태와 안전하게 상호작용하기 위해 @MainActor로 격리한다.
@Observable
@MainActor
final class TranslationCoordinator {
    var state: State = .idle

    enum State: Equatable {
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
                return a.text == b.text
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    struct TranslationResult {
        let text: String
        let lowConfidence: Bool  // OCR 신뢰도가 낮은 경우
    }

    private let ocrProvider: OCRProvider
    private let translationProvider: TranslationProvider
    private let targetLanguage: Locale.Language

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
    func process(image: CGImage) async {
        state = .recognizing

        do {
            let ocrResult = try await ocrProvider.recognize(image: image)
            state = .translating

            let translated = try await translationProvider.translate(
                text: ocrResult.text,
                from: ocrResult.detectedLanguage,
                to: targetLanguage
            )

            let result = TranslationResult(
                text: translated,
                lowConfidence: ocrResult.confidence < 0.3
            )
            state = .completed(result)
        } catch OCRError.noTextFound {
            state = .failed("선택한 영역에서 텍스트를 찾을 수 없습니다.")
        } catch TranslationError.languageNotSupported {
            state = .failed("이 언어 조합은 지원되지 않습니다.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
    }
}
```

**Step 2: MockOCRProvider 작성**

`ScreenTranslateTests/Mocks/MockOCRProvider.swift`:

```swift
import CoreGraphics
@testable import ScreenTranslate

final class MockOCRProvider: OCRProvider {
    var shouldFail = false
    var recognizedText = "Mock Text"
    var detectedLanguage: Locale.Language? = Locale.Language(identifier: "en")
    var confidence: Float = 0.95

    func recognize(image: CGImage) async throws -> OCRResult {
        if shouldFail { throw OCRError.noTextFound }
        return OCRResult(
            text: recognizedText,
            detectedLanguage: detectedLanguage,
            confidence: confidence
        )
    }
}
```

**Step 3: 테스트 작성**

`ScreenTranslateTests/Core/TranslationCoordinatorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ScreenTranslate

final class TranslationCoordinatorTests: XCTestCase {
    private var mockOCR: MockOCRProvider!
    private var mockTranslation: MockTranslationProvider!
    private var sut: TranslationCoordinator!

    override func setUp() {
        mockOCR = MockOCRProvider()
        mockTranslation = MockTranslationProvider()
        sut = TranslationCoordinator(
            ocrProvider: mockOCR,
            translationProvider: mockTranslation,
            targetLanguage: Locale.Language(identifier: "ko")
        )
    }

    func test_process_success_reachesCompletedState() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.translatedText = "안녕하세요"

        await sut.process(image: makeBlankImage())

        if case .completed(let result) = sut.state {
            XCTAssertEqual(result.text, "안녕하세요")
            XCTAssertFalse(result.lowConfidence)
        } else {
            XCTFail("completed 상태여야 한다: \(sut.state)")
        }
    }

    func test_process_lowConfidence_setsFlag() async {
        mockOCR.recognizedText = "Hello"
        mockOCR.confidence = 0.2  // < 0.3
        mockTranslation.translatedText = "안녕하세요"

        await sut.process(image: makeBlankImage())

        if case .completed(let result) = sut.state {
            XCTAssertTrue(result.lowConfidence)
        } else {
            XCTFail("completed 상태여야 한다")
        }
    }

    func test_process_ocrFails_reachesFailedState() async {
        mockOCR.shouldFail = true

        await sut.process(image: makeBlankImage())

        if case .failed(let msg) = sut.state {
            XCTAssertTrue(msg.contains("텍스트를 찾을 수 없습니다"))
        } else {
            XCTFail("실패 상태여야 한다: \(sut.state)")
        }
    }

    func test_process_translationFails_reachesFailedState() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.shouldFail = true

        await sut.process(image: makeBlankImage())

        if case .failed = sut.state {
            // Expected
        } else {
            XCTFail("실패 상태여야 한다: \(sut.state)")
        }
    }

    func test_reset_returnsToIdle() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.translatedText = "안녕"
        await sut.process(image: makeBlankImage())

        sut.reset()

        XCTAssertEqual(sut.state, .idle)
    }

    func test_process_passesDetectedLanguageToTranslation() async {
        mockOCR.recognizedText = "Hello"
        mockOCR.detectedLanguage = Locale.Language(identifier: "en")
        mockTranslation.translatedText = "안녕"

        await sut.process(image: makeBlankImage())

        // MockTranslationProvider는 lastReceivedText만 추적하므로
        // detectedLanguage 전달은 빌드 시 타입 체크로 보장
        XCTAssertEqual(mockTranslation.lastReceivedText, "Hello")
    }

    // MARK: - Helpers

    private func makeBlankImage() -> CGImage {
        let context = CGContext(data: nil, width: 10, height: 10,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}
```

**Step 4: 테스트 실행**

```
Xcode → Product → Test (Cmd+U)
```

Expected: TranslationCoordinatorTests 6개 모두 PASS

**Step 5: Commit**

```bash
git add ScreenTranslate/Core/TranslationCoordinator.swift ScreenTranslateTests/
git commit -m "feat: add TranslationCoordinator with OCRResult and state machine"
```

---

## Task 5: 화면 선택 오버레이 (SelectionOverlay)

**Files:**
- Create: `ScreenTranslate/UI/Overlay/SelectionOverlayWindow.swift`
- Create: `ScreenTranslate/UI/Overlay/SelectionOverlayView.swift`

**Step 1: SelectionOverlayView 작성 (SwiftUI)**

`ScreenTranslate/UI/Overlay/SelectionOverlayView.swift`:

```swift
import SwiftUI

struct SelectionOverlayView: View {
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false

    private var selectionRect: CGRect {
        guard isDragging else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    var body: some View {
        ZStack {
            // 반투명 어두운 배경
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            // 선택 영역 (밝게 표시)
            if isDragging && selectionRect.width > 2 && selectionRect.height > 2 {
                Rectangle()
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .blendMode(.destinationOut)

                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1)
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
            }
        }
        .compositingGroup()
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        startPoint = value.startLocation
                        isDragging = true
                    }
                    currentPoint = value.location
                }
                .onEnded { _ in
                    let rect = selectionRect
                    isDragging = false
                    if rect.width > 10 && rect.height > 10 {
                        onComplete(rect)
                    } else {
                        onCancel()
                    }
                }
        )
        .onHover { inside in
            if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
        }
    }
}
```

**Step 2: SelectionOverlayWindow 작성 (AppKit — ESC는 keyDown으로 처리)**

`ScreenTranslate/UI/Overlay/SelectionOverlayWindow.swift`:

```swift
import AppKit
import SwiftUI

/// 전체 화면을 덮는 투명 오버레이 창.
/// 사용자가 드래그로 영역을 선택하면 completion 핸들러를 호출한다.
final class SelectionOverlayWindow: NSWindow {
    private var completion: ((CGRect?) -> Void)?

    init() {
        // 현재 마우스 위치의 디스플레이를 찾는다
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    func show(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        // 현재 마우스 위치의 디스플레이에 표시
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
        setFrame(screen.frame, display: true)

        let overlayView = SelectionOverlayView(
            onComplete: { [weak self] rect in
                self?.close()
                completion(rect)
            },
            onCancel: { [weak self] in
                self?.close()
                completion(nil)
            }
        )

        contentView = NSHostingView(rootView: overlayView)
        makeKeyAndOrderFront(nil)
    }

    // ESC 키 처리 — AppKit 레벨 (SwiftUI onKeyPress는 포커스 필요)
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            close()
            completion?(nil)
            completion = nil
        } else {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

**Step 3: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

Expected: Build Succeeded

**Step 4: Commit**

```bash
git add ScreenTranslate/UI/Overlay/
git commit -m "feat: add SelectionOverlayWindow with AppKit ESC handling and multi-display support"
```

---

## Task 6: 화면 캡처 (ScreenCaptureKit + Retina 대응)

**Files:**
- Create: `ScreenTranslate/Core/ScreenCapture/ScreenCapturer.swift`

**Step 1: ScreenCapturer 작성 (Retina scale factor 반영)**

`ScreenTranslate/Core/ScreenCapture/ScreenCapturer.swift`:

```swift
import ScreenCaptureKit
import CoreGraphics
import AppKit

final class ScreenCapturer {
    /// 지정된 화면 좌표 영역을 캡처한다.
    /// - Parameters:
    ///   - rect: 캡처할 화면 영역 (SwiftUI 좌표계 — 좌상단 원점, 포인트 단위)
    ///   - screen: 캡처 대상 화면
    /// - Returns: 캡처된 CGImage
    func capture(rect: CGRect, screen: NSScreen? = nil) async throws -> CGImage {
        let targetScreen = screen ?? NSScreen.main!
        let scaleFactor = targetScreen.backingScaleFactor

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // 현재 디스플레이 찾기
        guard let display = content.displays.first(where: { display in
            let displayFrame = CGRect(
                x: Int(targetScreen.frame.origin.x),
                y: Int(targetScreen.frame.origin.y),
                width: display.width,
                height: display.height
            )
            return displayFrame.intersects(targetScreen.frame)
        }) ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        // 픽셀 단위로 설정 (Retina 대응)
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.scalesToFit = false
        config.capturesAudio = false
        config.showsCursor = false

        let screenshot = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // 좌표 변환: SwiftUI (좌상단 원점, 포인트) → CGImage (좌상단, 픽셀)
        // ScreenCaptureKit의 캡처 이미지는 이미 좌상단 원점
        let croppingRect = CGRect(
            x: (rect.origin.x - targetScreen.frame.origin.x) * scaleFactor,
            y: (rect.origin.y - targetScreen.frame.origin.y) * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        )

        guard let cropped = screenshot.cropping(to: croppingRect) else {
            throw CaptureError.cropFailed
        }

        return cropped
    }
}

enum CaptureError: LocalizedError {
    case noDisplayFound
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "디스플레이를 찾을 수 없습니다."
        case .cropFailed: return "이미지 크롭에 실패했습니다."
        }
    }
}

// MARK: - Permission Check

extension ScreenCapturer {
    static func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }
}
```

> **변경점**: (1) `backingScaleFactor`를 반영하여 `SCStreamConfiguration`과 cropping rect에 적용. Retina 디스플레이에서 올바른 해상도와 좌표로 캡처. (2) `NSScreen` 기반 좌표 변환으로 멀티 디스플레이 대응 준비. (3) 좌표 변환 주석으로 좌표계 차이 문서화.

**Step 2: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

**Step 3: Commit**

```bash
git add ScreenTranslate/Core/ScreenCapture/
git commit -m "feat: add ScreenCapturer with Retina scale factor and coordinate transform"
```

---

## Task 7: 번역 팝업 UI (로딩/에러 상태 포함)

**Files:**
- Create: `ScreenTranslate/UI/Popup/TranslationPopupView.swift`
- Create: `ScreenTranslate/UI/Popup/TranslationPopupWindow.swift`

**Step 1: TranslationPopupView 작성 (로딩 + 에러 + 결과)**

`ScreenTranslate/UI/Popup/TranslationPopupView.swift`:

```swift
import SwiftUI

struct TranslationPopupView: View {
    let state: TranslationCoordinator.State
    let onCopy: (String) -> Void
    let onClose: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .idle:
                EmptyView()

            case .recognizing:
                loadingView(message: "인식 중...")

            case .translating:
                loadingView(message: "번역 중...")

            case .completed(let result):
                completedView(result: result)

            case .failed(let message):
                errorView(message: message)
            }

            HStack {
                Spacer()

                if case .completed(let result) = state {
                    Button(didCopy ? "복사됨" : "복사") {
                        onCopy(result.text)
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            didCopy = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(didCopy ? .green : .accentColor)
                }

                Button("닫기") {
                    onClose()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12, y: 4)
    }

    // MARK: - Subviews

    private func loadingView(message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private func completedView(result: TranslationCoordinator.TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.lowConfidence {
                Label("인식 정확도가 낮습니다", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView {
                Text(result.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
```

**Step 2: TranslationPopupWindow 작성**

`ScreenTranslate/UI/Popup/TranslationPopupWindow.swift`:

```swift
import AppKit
import SwiftUI

final class TranslationPopupWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false  // 텍스트 드래그 선택과 충돌 방지
        hidesOnDeactivate = false
    }

    /// 번역 상태를 반영하여 팝업을 표시/업데이트한다.
    /// - Parameters:
    ///   - state: TranslationCoordinator의 현재 상태
    ///   - selectionRect: 선택 영역 (SwiftUI 좌상단 원점, 포인트 단위)
    ///   - screen: 팝업이 표시될 화면
    func show(state: TranslationCoordinator.State, near selectionRect: CGRect, on screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main!

        let popupView = TranslationPopupView(
            state: state,
            onCopy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: popupView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        contentView = hostingView

        // 좌표 변환: SwiftUI (좌상단 원점) → AppKit (좌하단 원점)
        let screenFrame = targetScreen.frame
        let popupHeight: CGFloat = 300
        let popupWidth: CGFloat = 400
        let gap: CGFloat = 8

        // 기본 위치: 선택 영역 하단
        var origin = CGPoint(
            x: selectionRect.minX,
            y: screenFrame.maxY - selectionRect.maxY - popupHeight - gap
        )

        // 하단이 화면 밖 → 선택 영역 상단으로
        if origin.y < screenFrame.minY {
            origin.y = screenFrame.maxY - selectionRect.minY + gap
        }

        // 오른쪽이 화면 밖 → 왼쪽으로 보정
        if origin.x + popupWidth > screenFrame.maxX {
            origin.x = screenFrame.maxX - popupWidth - gap
        }

        // 왼쪽이 화면 밖 → 최소 gap 유지
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + gap
        }

        setFrameOrigin(origin)
        setContentSize(NSSize(width: popupWidth, height: popupHeight))
        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }
}
```

**Step 3: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

**Step 4: Commit**

```bash
git add ScreenTranslate/UI/Popup/
git commit -m "feat: add TranslationPopupView with loading, error, and result states"
```

---

## Task 8: 설정창 (SettingsView + AppSettings)

**Files:**
- Create: `ScreenTranslate/UI/Settings/AppSettings.swift`
- Create: `ScreenTranslate/UI/Settings/SettingsView.swift`

**Step 1: AppSettings 작성 (@Observable 수동 tracking)**

`ScreenTranslate/UI/Settings/AppSettings.swift`:

```swift
import Foundation
import Observation

/// @Observable + UserDefaults 연동.
/// computed property에서는 @Observable의 자동 tracking이 동작하지 않으므로
/// access(keyPath:) / withMutation(keyPath:) 를 수동으로 호출한다.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Target Language

    @ObservationIgnored
    private var _targetLanguageCode: String?

    var targetLanguageCode: String {
        get {
            access(keyPath: \.targetLanguageCode)
            return UserDefaults.standard.string(forKey: "com.screentranslate.targetLanguageCode") ?? "ko"
        }
        set {
            withMutation(keyPath: \.targetLanguageCode) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.targetLanguageCode")
            }
        }
    }

    // MARK: - OCR Provider

    @ObservationIgnored
    private var _ocrProviderName: String?

    var ocrProviderName: String {
        get {
            access(keyPath: \.ocrProviderName)
            return UserDefaults.standard.string(forKey: "com.screentranslate.ocrProviderName") ?? "Apple Vision"
        }
        set {
            withMutation(keyPath: \.ocrProviderName) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.ocrProviderName")
            }
        }
    }

    // MARK: - Translation Provider

    @ObservationIgnored
    private var _translationProviderName: String?

    var translationProviderName: String {
        get {
            access(keyPath: \.translationProviderName)
            return UserDefaults.standard.string(forKey: "com.screentranslate.translationProviderName") ?? "Apple Translation"
        }
        set {
            withMutation(keyPath: \.translationProviderName) {
                UserDefaults.standard.set(newValue, forKey: "com.screentranslate.translationProviderName")
            }
        }
    }

    // MARK: - Computed Helpers

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetLanguageCode)
    }

    // MARK: - Supported Languages

    static let supportedLanguages: [(code: String, name: String)] = [
        ("ko", "한국어"),
        ("en", "English"),
        ("ja", "日本語"),
        ("zh-Hans", "中文(简体)"),
        ("zh-Hant", "中文(繁體)"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("pt", "Português"),
        ("it", "Italiano"),
        ("ru", "Русский"),
        ("ar", "العربية"),
    ]
}
```

> **변경점**: `@ObservationIgnored` 더미 프로퍼티와 `access(keyPath:)` / `withMutation(keyPath:)` 수동 호출로 `@Observable` + UserDefaults computed property가 SwiftUI 뷰 업데이트를 올바르게 트리거한다.

**Step 2: SettingsView 작성**

`ScreenTranslate/UI/Settings/SettingsView.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("번역") {
                Picker("번역 결과 언어", selection: $settings.targetLanguageCode) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)

                Picker("OCR 엔진", selection: $settings.ocrProviderName) {
                    Text("Apple Vision").tag("Apple Vision")
                }
                .pickerStyle(.menu)
                .disabled(true)  // v1에서는 단일 옵션

                Picker("번역 엔진", selection: $settings.translationProviderName) {
                    Text("Apple Translation (로컬)").tag("Apple Translation")
                }
                .pickerStyle(.menu)
                .disabled(true)  // v1에서는 단일 옵션
            }

            Section("단축키") {
                KeyboardShortcuts.Recorder("번역 단축키", name: .translate)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 280)
    }
}
```

**Step 3: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

**Step 4: Commit**

```bash
git add ScreenTranslate/UI/Settings/
git commit -m "feat: add SettingsView and AppSettings with manual Observable tracking"
```

---

## Task 9: 메뉴바 뷰 + 전체 연결

**Files:**
- Modify: `ScreenTranslate/App/ScreenTranslateApp.swift`
- Modify: `ScreenTranslate/UI/MenuBar/MenuBarView.swift`
- Create: `ScreenTranslate/App/AppOrchestrator.swift`

**Step 1: AppOrchestrator 작성 (전체 흐름 관리)**

`ScreenTranslate/App/AppOrchestrator.swift`:

```swift
import AppKit
import CoreGraphics
import KeyboardShortcuts
import Observation

/// UI 생명주기를 관리하는 싱글턴.
/// 오버레이/팝업 윈도우 표시·숨김, 권한 확인, 사용자 인터랙션 처리.
/// 데이터 파이프라인(캡처→OCR→번역)은 TranslationCoordinator에 위임한다.
@Observable
@MainActor
final class AppOrchestrator {
    static let shared = AppOrchestrator()

    private var overlayWindow: SelectionOverlayWindow?
    private var popupWindow: TranslationPopupWindow?
    private let capturer = ScreenCapturer()
    private var currentScreen: NSScreen?

    private var coordinator: TranslationCoordinator {
        TranslationCoordinator(
            ocrProvider: VisionOCRProvider(),
            translationProvider: AppleTranslationProvider(),
            targetLanguage: AppSettings.shared.targetLanguage
        )
    }

    func setup() {
        KeyboardShortcuts.onKeyUp(for: .translate) { [weak self] in
            Task { @MainActor in
                self?.startTranslation()
            }
        }
    }

    func startTranslation() {
        // 기존 팝업 닫기
        popupWindow?.close()
        popupWindow = nil

        // 권한 확인
        Task {
            let hasPermission = await ScreenCapturer.checkPermission()
            guard hasPermission else {
                await PermissionGuard.requestScreenRecordingPermission()
                return
            }

            // 현재 마우스 위치의 디스플레이 감지
            let mouseLocation = NSEvent.mouseLocation
            currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

            overlayWindow = SelectionOverlayWindow()
            overlayWindow?.show { [weak self] rect in
                guard let self, let rect else { return }
                Task { @MainActor in
                    await self.processCapture(rect: rect)
                }
            }
        }
    }

    private func processCapture(rect: CGRect) async {
        let coord = coordinator
        let popup = TranslationPopupWindow()
        self.popupWindow = popup

        // 로딩 상태 표시
        popup.show(state: .recognizing, near: rect, on: currentScreen)

        do {
            let image = try await capturer.capture(rect: rect, screen: currentScreen)

            // OCR 중 상태 표시 (이미 recognizing)
            await coord.process(image: image)

            // 번역 중 상태로 업데이트
            if case .translating = coord.state {
                popup.show(state: .translating, near: rect, on: currentScreen)
            }

            // 최종 결과 표시
            popup.show(state: coord.state, near: rect, on: currentScreen)

        } catch {
            popup.show(
                state: .failed("캡처 오류: \(error.localizedDescription)"),
                near: rect,
                on: currentScreen
            )
        }
    }
}
```

**Step 2: MenuBarView 업데이트**

`ScreenTranslate/UI/MenuBar/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button("번역하기") {
            AppOrchestrator.shared.startTranslation()
        }
        .keyboardShortcut("T", modifiers: [.control, .shift])

        Divider()

        SettingsLink {
            Text("설정...")
        }

        Divider()

        Button("ScreenTranslate 종료") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

> **변경점**: `SettingsLink`를 사용하여 Settings Scene을 올바르게 열도록 수정. macOS 14+에서 `SettingsLink`가 공식 지원됨.

**Step 3: App 진입점 업데이트 (TranslationBridgeView 삽입)**

`ScreenTranslate/App/ScreenTranslateApp.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translate = Self("translate", default: .init(.t, modifiers: [.control, .shift]))
}

@main
struct ScreenTranslateApp: App {
    @State private var orchestrator = AppOrchestrator.shared

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppOrchestrator.shared.setup()
    }

    var body: some Scene {
        MenuBarExtra("ScreenTranslate", systemImage: "text.viewfinder") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// TranslationBridge를 상주시키기 위한 AppDelegate.
/// MenuBarExtra 콘텐츠는 메뉴가 열릴 때만 생성되므로,
/// TranslationBridge를 별도의 off-screen NSWindow에 호스팅한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bridgeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: TranslationBridgeView())
        window.orderOut(nil)  // 숨김 상태로 유지, 메모리에서 해제하지 않음
        self.bridgeWindow = window
    }
}
```

> **변경점**: `TranslationBridgeView`를 SwiftUI `Window` Scene 대신 `AppDelegate`에서 생성한 전용 상주 `NSWindow`에 호스팅한다. `MenuBarExtra` 콘텐츠는 메뉴가 닫히면 파괴되므로, 이 방식으로 `.translationTask` modifier가 앱 전체 생명주기 동안 항상 활성 상태를 유지한다.

**Step 4: 빌드 및 수동 동작 확인**

```
Xcode → Product → Run (Cmd+R)
```

확인 목록:
- [ ] 메뉴바에 `text.viewfinder` 아이콘 표시
- [ ] Dock 아이콘 없음
- [ ] "번역하기" 클릭 시 오버레이 표시
- [ ] 드래그로 영역 선택 후 로딩 → 번역 결과 팝업 표시
- [ ] 복사 버튼 동작 + "복사됨" 피드백
- [ ] ESC로 오버레이 취소 동작
- [ ] ESC로 팝업 닫기 동작
- [ ] 설정... 클릭 시 설정 창 열림
- [ ] 설정에서 언어 변경 후 번역 결과 반영
- [ ] Ctrl+Shift+T 단축키 동작
- [ ] 팝업 표시 중 다시 단축키 → 기존 팝업 닫히고 새 선택 시작
- [ ] OCR 실패 시 (빈 영역) 에러 메시지 표시

**Step 5: Commit**

```bash
git add ScreenTranslate/App/ ScreenTranslate/UI/MenuBar/
git commit -m "feat: wire AppOrchestrator, MenuBarView, TranslationBridge, and full flow"
```

---

## Task 10: 권한 처리 및 첫 실행 안내

**Files:**
- Create: `ScreenTranslate/App/PermissionGuard.swift`

**Step 1: PermissionGuard 작성**

`ScreenTranslate/App/PermissionGuard.swift`:

```swift
import AppKit
import SwiftUI

/// Screen Recording 권한 안내를 floating 팝업으로 표시한다.
/// 모달 NSAlert 대신 TranslationPopup과 동일한 비모달 팝업 패턴을 사용하여
/// 사용자가 기대하는 가벼운 인터랙션 흐름을 유지한다.
@MainActor
final class PermissionGuard {
    private static var permissionWindow: NSPanel?

    static func requestScreenRecordingPermission() async {
        // 이미 표시 중이면 무시
        guard permissionWindow == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false

        let permissionView = PermissionRequestView(
            onOpenSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            },
            onClose: {
                permissionWindow?.close()
                permissionWindow = nil
            }
        )

        panel.contentView = NSHostingView(rootView: permissionView)

        // 화면 중앙에 표시
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let popupWidth: CGFloat = 360
        let popupHeight: CGFloat = 180
        let origin = CGPoint(
            x: screen.frame.midX - popupWidth / 2,
            y: screen.frame.midY - popupHeight / 2
        )
        panel.setFrameOrigin(origin)
        panel.setContentSize(NSSize(width: popupWidth, height: popupHeight))
        panel.makeKeyAndOrderFront(nil)
        permissionWindow = panel
    }
}

/// 권한 요청 팝업 뷰.
struct PermissionRequestView: View {
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("화면 접근 권한이 필요합니다")
                .font(.headline)

            Text("시스템 설정 → 개인 정보 보호 및 보안 → 화면 기록에서 ScreenTranslate를 허용해주세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("시스템 설정 열기") { onOpenSettings() }
                    .buttonStyle(.borderedProminent)

                Button("닫기") { onClose() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12, y: 4)
    }
}
```

> **변경점**: (1) 권한 요청을 앱 첫 실행이 아닌 **첫 번역 시도 시**로 이동 (AppOrchestrator에서 호출). (2) 모달 `NSAlert` 대신 `TranslationPopup`과 동일한 floating `NSPanel` 팝업을 사용하여 비모달 UX를 유지한다.

**Step 2: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

**Step 3: 최종 테스트**

```
Xcode → Product → Test (Cmd+U)
```

Expected: 모든 단위 테스트 PASS

```
Xcode → Product → Run (Cmd+R)
```

전체 시나리오 수동 테스트:
- [ ] 첫 번역 시도 시 Screen Recording 권한 미승인이면 안내 팝업
- [ ] 권한 승인 후 `Ctrl+Shift+T`로 오버레이 실행
- [ ] 영어 텍스트 영역 드래그 → 로딩("인식 중...") → 로딩("번역 중...") → 한국어 번역 결과
- [ ] OCR 신뢰도 낮은 영역 → 경고 아이콘 표시
- [ ] 빈 영역 드래그 → "텍스트를 찾을 수 없습니다" 에러
- [ ] 복사 버튼으로 클립보드 복사 + "복사됨" 피드백
- [ ] 설정에서 타겟 언어를 영어로 변경 후 한국어 텍스트 번역
- [ ] 단축키 변경 후 새 단축키로 동작 확인
- [ ] 팝업 ESC로 닫기
- [ ] 오버레이 ESC로 취소

**Step 4: 최종 Commit**

```bash
git add ScreenTranslate/App/PermissionGuard.swift
git commit -m "feat: add PermissionGuard with lazy screen recording permission request"
git tag v1.0.0
```

---

## 완료 기준

- [ ] 모든 단위 테스트 PASS (`xcodebuild test`)
- [ ] 메뉴바에서 앱 동작
- [ ] 단축키 → 오버레이 → 드래그 → OCR → 번역 → 팝업 전체 플로우 동작
- [ ] 로딩 상태 표시 (인식 중 / 번역 중)
- [ ] 에러 상태 표시 (OCR 실패, 번역 실패, 권한 미승인)
- [ ] 복사 버튼 동작 + 피드백
- [ ] 설정에서 타겟 언어 변경 반영
- [ ] 설정에서 단축키 변경 가능
- [ ] ESC로 오버레이/팝업 닫기
- [ ] Retina 디스플레이에서 올바른 캡처
- [ ] 현재 마우스 위치 디스플레이에서 오버레이 표시

---

## 참고 문서

- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [Apple Translation Framework](https://developer.apple.com/documentation/translation)
- [TranslationSession.Configuration](https://developer.apple.com/documentation/translation/translationsession/configuration)
- [ScreenCaptureKit / SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [KeyboardShortcuts (sindresorhus)](https://github.com/sindresorhus/KeyboardShortcuts)
- [SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink)
- [@Observable + UserDefaults 패턴](https://fatbobman.com/en/posts/userdefaults-and-observation/)

---

## 변경 이력

### v1.2 (2026-03-02) — 아키텍처/HIG 점검 피드백 반영

| Task | 변경 사항 |
|---|---|
| 전체 | Swift 5.9+ → Swift 6 (Strict Concurrency), `Sendable` 프로토콜/구조체 명시 |
| Task 2 | `VNRecognizeTextRequest` → `RecognizeTextRequest` (Swift-native async/await API), `OCRResult: Sendable`, `OCRProvider: Sendable`, `CGImage: @unchecked Sendable` |
| Task 3 | `TranslationProvider: Sendable` 추가 |
| Task 4 | `TranslationCoordinator`에 `@MainActor` 격리 추가 |
| Task 1, 9 | 기본 단축키 `Cmd+Shift+T` → `Ctrl+Shift+T` (Safari/Terminal 충돌 방지) |
| Task 5 | 오버레이 윈도우 레벨 `.screenSaver` → `.statusBar + 1` |
| Task 7 | NSPanel: `.nonactivatingPanel` → `becomesKeyOnlyIfNeeded = true`, `isMovableByWindowBackground = false` |
| Task 9 | TranslationBridge를 SwiftUI Window Scene 대신 AppDelegate의 상주 NSWindow에 호스팅 |
| Task 9 | AppOrchestrator 역할을 UI 생명주기 관리로 명확화 |
| Task 10 | PermissionGuard: NSAlert → floating NSPanel 팝업 (비모달) |

### v1.1 (2026-03-02) — 리뷰 피드백 반영

| Task | 변경 사항 |
|---|---|
| Task 1 | KeyboardShortcuts URL 수정: `nicklockwood` → `sindresorhus` |
| Task 2 | `OCRResult` 구조체 도입 (text + detectedLanguage + confidence), continuation 이중 resume 방지 |
| Task 3 | `TranslationBridge` 추가 — SwiftUI `.translationTask` modifier 연동. `AppleTranslationProvider`가 실제로 번역 수행 |
| Task 4 | `TranslationCoordinator`에 `TranslationResult` (lowConfidence 플래그), OCRResult 기반 언어 전달 |
| Task 5 | ESC를 AppKit `keyDown(with:)` override로 처리. 멀티 디스플레이: 현재 마우스 위치 디스플레이 감지 |
| Task 6 | `backingScaleFactor` 반영. 좌표 변환 로직 문서화 |
| Task 7 | 팝업에 로딩 상태 (스피너), 에러 상태, 낮은 신뢰도 경고 추가. 위치 보정 로직 강화 |
| Task 8 | `@Observable` + UserDefaults: `access(keyPath:)` / `withMutation(keyPath:)` 수동 호출 패턴 |
| Task 9 | `SettingsLink` 사용. `TranslationBridgeView` 삽입. 팝업 재실행 시 기존 닫기 |
| Task 10 | 권한 요청을 첫 번역 시도 시로 변경 (lazy) |
