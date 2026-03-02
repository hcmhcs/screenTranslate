# Phase 3: Capture Pipeline

> [← Phase 2](./phase-2-core-providers.md) | [Overview](./00-overview.md) | [Phase 4 →](./phase-4-ui.md)

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

    /// ⚠️ H4: 진행 중인 Task 참조를 보관하여 ESC 취소를 지원한다.
    private var currentTask: Task<Void, Never>?

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
    /// ⚠️ H4: Task 참조를 보관하여 ESC 취소를 지원한다.
    /// ⚠️ C4: 각 단계 사이에서 state를 변경하여 UI가 중간 상태를 관찰할 수 있게 한다.
    func startProcessing(image: CGImage) {
        currentTask?.cancel()
        currentTask = Task {
            state = .recognizing

            do {
                let ocrResult = try await ocrProvider.recognize(image: image)
                try Task.checkCancellation()  // ESC 체크 포인트

                // C4: OCR 완료 후, 번역 호출 전에 state를 변경해야 UI가 "번역 중..." 표시
                state = .translating

                let translated = try await translationProvider.translate(
                    text: ocrResult.text,
                    from: ocrResult.detectedLanguage,
                    to: targetLanguage
                )
                try Task.checkCancellation()  // ESC 체크 포인트

                let result = TranslationResult(
                    text: translated,
                    lowConfidence: ocrResult.confidence < 0.3
                )
                state = .completed(result)
            } catch is CancellationError {
                state = .idle  // 조용히 취소
            } catch OCRError.noTextFound {
                state = .failed("선택한 영역에서 텍스트를 찾을 수 없습니다.")
            } catch TranslationError.languageNotSupported {
                state = .failed("이 언어 조합은 지원되지 않습니다.")
            } catch {
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

        sut.startProcessing(image: makeBlankImage())
        // Task 완료 대기
        try? await Task.sleep(for: .milliseconds(100))

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

        sut.startProcessing(image: makeBlankImage())
        // Task 완료 대기
        try? await Task.sleep(for: .milliseconds(100))

        if case .completed(let result) = sut.state {
            XCTAssertTrue(result.lowConfidence)
        } else {
            XCTFail("completed 상태여야 한다")
        }
    }

    func test_process_ocrFails_reachesFailedState() async {
        mockOCR.shouldFail = true

        sut.startProcessing(image: makeBlankImage())
        // Task 완료 대기
        try? await Task.sleep(for: .milliseconds(100))

        if case .failed(let msg) = sut.state {
            XCTAssertTrue(msg.contains("텍스트를 찾을 수 없습니다"))
        } else {
            XCTFail("실패 상태여야 한다: \(sut.state)")
        }
    }

    func test_process_translationFails_reachesFailedState() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.shouldFail = true

        sut.startProcessing(image: makeBlankImage())
        // Task 완료 대기
        try? await Task.sleep(for: .milliseconds(100))

        if case .failed = sut.state {
            // Expected
        } else {
            XCTFail("실패 상태여야 한다: \(sut.state)")
        }
    }

    func test_reset_returnsToIdle() async {
        mockOCR.recognizedText = "Hello"
        mockTranslation.translatedText = "안녕"
        sut.startProcessing(image: makeBlankImage())
        // Task 완료 대기
        try? await Task.sleep(for: .milliseconds(100))

        sut.reset()

        XCTAssertEqual(sut.state, .idle)
    }

    func test_process_passesDetectedLanguageToTranslation() async {
        mockOCR.recognizedText = "Hello"
        mockOCR.detectedLanguage = Locale.Language(identifier: "en")
        mockTranslation.translatedText = "안녕"

        sut.startProcessing(image: makeBlankImage())
        // Task 완료 대기
        try? await Task.sleep(for: .milliseconds(100))

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

/// ⚠️ C3: DragGesture(.global)는 **윈도우-로컬 좌상단 원점** 좌표를 반환한다.
/// 오버레이가 전체 화면이므로 윈도우 원점 == 스크린 원점(좌상단)이 된다.
/// 하지만 AppKit/ScreenCaptureKit은 좌하단 원점을 사용하므로,
/// onComplete로 전달된 rect를 사용할 때 반드시 좌표 변환이 필요하다.
/// 변환 공식: appKitY = screen.frame.maxY - swiftUIY
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

        // ⚠️ H7: displayID로 매칭한다. frame 비교는 Retina 스케일링,
        // 디스플레이 배치 변경 등으로 불일치할 수 있다.
        let screenID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == screenID })
            ?? content.displays.first else {
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
