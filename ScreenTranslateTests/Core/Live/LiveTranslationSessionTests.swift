import CoreGraphics
import Foundation
import Testing
@testable import ScreenTranslate

/// 실시간 번역 감시 세션 — 가짜 캡처·인식·번역으로 틱을 한 단계씩 진행한다.
@MainActor
@Suite struct LiveTranslationSessionTests {

    /// 세션과 가짜 의존성 묶음
    @MainActor
    final class Harness {
        let source = GatedFrameSource()
        let ocr: ScriptedOCRProvider
        let translator: TranslationProvider
        var busy = false
        var region = LiveRegion(rect: CGRect(x: 0, y: 0, width: 96, height: 24), displayID: 1, scale: 1)
        private(set) var stopReasons: [LiveTranslationSession.StopReason] = []
        private(set) var session: LiveTranslationSession!

        /// 기본 인자는 격리되지 않은 문맥에서 평가되므로 MainActor 가짜는 안에서 만든다
        init(ocr results: [String], translator: TranslationProvider? = nil) {
            ocr = ScriptedOCRProvider(results)
            self.translator = translator ?? RecordingTranslationProvider()
            session = LiveTranslationSession(
                dependencies: .init(
                    frameSource: source,
                    ocr: ocr,
                    translator: self.translator,
                    isTranslatorBusy: { [unowned self] in self.busy },
                    sleep: { _ in }
                ),
                region: { [unowned self] in self.region },
                languages: { (nil, Locale.Language(identifier: "ko")) },
                preprocess: { false }
            )
            session.onStop = { [unowned self] in self.stopReasons.append($0) }
        }

        var recorder: RecordingTranslationProvider {
            translator as! RecordingTranslationProvider
        }

        /// 한 틱: 캡처 요청을 기다렸다 화면을 주고, 틱이 끝나 다음 요청이 올 때까지 기다린다
        func feed(_ image: CGImage) async {
            await source.nextRequest()
            source.deliver(image)
            await source.nextRequest()
        }

        /// 비동기 번역이 끝나기를 잠깐 기다린다
        func settle(until condition: () -> Bool) async {
            for _ in 0..<200 where !condition() {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test("a stable subtitle is translated and shown")
    func showsStableSubtitle() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        await h.settle { h.session.display == .subtitle("번역:Hello") }
        #expect(h.session.display == .subtitle("번역:Hello"))
        #expect(h.recorder.requests == ["Hello"])
        #expect(h.session.translationCount == 1)
        h.session.stop(.user)
    }

    @Test("an unchanged screen skips text recognition")
    func unchangedFrameSkipsOCR() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        let frame = TestImages.block(at: 0)
        for _ in 0..<3 {
            await h.feed(frame)
        }
        #expect(h.ocr.callCount == 1)
        h.session.stop(.user)
    }

    @Test("the same subtitle is not translated again")
    func doesNotRetranslate() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        for x in [0, 20, 40, 60] {
            await h.feed(TestImages.block(at: x))
        }
        await h.settle { !h.recorder.requests.isEmpty }
        #expect(h.recorder.requests == ["Hello"])
        h.session.stop(.user)
    }

    @Test("waits while another feature uses Apple Translation, then sends")
    func yieldsToOtherTranslations() async {
        let h = Harness(ocr: ["Hello"])
        h.busy = true
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        #expect(h.recorder.requests.isEmpty)
        h.busy = false
        await h.feed(TestImages.block(at: 60))
        await h.settle { h.recorder.requests == ["Hello"] }
        #expect(h.recorder.requests == ["Hello"])
        h.session.stop(.user)
    }

    @Test("a request pushed out by another feature is retried")
    func retriesWhenSuperseded() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.failure(TranslationError.superseded), .success("안녕")]
        let h = Harness(ocr: ["Hello"], translator: recorder)
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        await h.settle { recorder.requests.count == 1 }
        await h.feed(TestImages.block(at: 60))
        await h.settle { h.session.display == .subtitle("안녕") }
        #expect(recorder.requests == ["Hello", "Hello"])
        #expect(h.session.display == .subtitle("안녕"))
        h.session.stop(.user)
    }

    @Test("a late translation of an old subtitle is discarded")
    func dropsStaleTranslation() async {
        let gated = GatedTranslationProvider()
        let h = Harness(ocr: ["A", "A", "B", "B"], translator: gated)
        h.session.start()
        for x in [0, 20, 40, 60] {
            await h.feed(TestImages.block(at: x))
        }
        await h.settle { gated.pendingCount == 2 }
        gated.resumeFirst(with: .success("A번역"))
        await h.settle { gated.completedCalls == 1 }
        #expect(h.session.display != .subtitle("A번역"))
        gated.resumeFirst(with: .success("B번역"))
        await h.settle { h.session.display == .subtitle("B번역") }
        #expect(h.session.display == .subtitle("B번역"))
        h.session.stop(.user)
    }

    @Test("a failed translation shows the reason and is not retried")
    func failureIsNotRetried() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.failure(TranslationError.languageNotSupported)]
        let h = Harness(ocr: ["Hello"], translator: recorder)
        let reason = TranslationError.languageNotSupported.localizedDescription
        h.session.start()
        for x in [0, 20, 40, 60] {
            await h.feed(TestImages.block(at: x))
        }
        await h.settle { h.session.display == .message(reason) }
        #expect(h.session.display == .message(reason))
        #expect(recorder.requests == ["Hello"])
        h.session.stop(.user)
    }

    @Test("the subtitle bar hides when the subtitle disappears")
    func hidesWhenCleared() async {
        let h = Harness(ocr: ["Hello", "Hello", "", ""])
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 20))
        await h.settle { h.session.display == .subtitle("번역:Hello") }
        await h.feed(TestImages.block(at: 40))
        await h.feed(TestImages.block(at: 60))
        #expect(h.session.display == .hidden)
        h.session.stop(.user)
    }

    @Test("an empty area at the start keeps the waiting message")
    func keepsWaitingMessage() async {
        let h = Harness(ocr: [""])
        h.session.start()
        #expect(h.session.display == .message(L10n.liveWaitingForText))
        for x in [0, 20, 40] {
            await h.feed(TestImages.block(at: x))
        }
        #expect(h.session.display == .message(L10n.liveWaitingForText))
        h.session.stop(.user)
    }

    @Test("a capture failure stops the session with the reason")
    func captureFailureStops() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.source.nextRequest()
        h.source.fail(CaptureError.noDisplayFound)
        await h.settle { !h.session.isRunning }
        #expect(!h.session.isRunning)
        #expect(h.stopReasons == [.captureFailed(CaptureError.noDisplayFound.localizedDescription)])
        #expect(h.session.display == .hidden)
    }

    @Test("stopping twice reports once and clears the display")
    func stopIsIdempotent() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.source.nextRequest()
        h.session.stop(.user)
        h.session.stop(.user)
        #expect(h.stopReasons == [.user])
        #expect(!h.session.isRunning)
        #expect(h.session.display == .hidden)
    }

    @Test("each tick captures the region where it is now")
    func followsRegionChanges() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        let moved = LiveRegion(rect: CGRect(x: 50, y: 50, width: 96, height: 24), displayID: 1, scale: 1)
        h.region = moved
        await h.feed(TestImages.block(at: 20))
        #expect(h.source.requestedRegions.last == moved)
        h.session.stop(.user)
    }
}
