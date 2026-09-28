import Testing
@testable import ScreenTranslate

/// 실시간 번역의 자막 안정화 — 인식 흔들림을 걸러 새로 확정된 자막만 내보낸다.
@Suite struct LiveTextStabilizerTests {

    @Test("a subtitle is confirmed after two identical readings")
    func confirmsAfterTwoReadings() {
        var stabilizer = LiveTextStabilizer()
        #expect(stabilizer.ingest("Hello") == nil)
        #expect(stabilizer.ingest("Hello") == .show("Hello"))
    }

    @Test("a one-off misread does not replace the subtitle")
    func ignoresOneOffFlicker() {
        var stabilizer = LiveTextStabilizer()
        _ = stabilizer.ingest("Hello")
        _ = stabilizer.ingest("Hello")
        #expect(stabilizer.ingest("Hel1o") == nil)
        #expect(stabilizer.ingest("Hello") == nil)
        #expect(stabilizer.ingest("Hello") == nil)
    }

    @Test("the same subtitle is never emitted twice in a row")
    func doesNotReemit() {
        var stabilizer = LiveTextStabilizer()
        _ = stabilizer.ingest("Hello")
        _ = stabilizer.ingest("Hello")
        for _ in 0..<3 {
            #expect(stabilizer.ingest("Hello") == nil)
        }
    }

    @Test("whitespace and line breaks are normalized before comparing")
    func normalizesWhitespace() {
        var stabilizer = LiveTextStabilizer()
        #expect(stabilizer.ingest("Hello\nworld") == nil)
        #expect(stabilizer.ingest("  Hello   world ") == .show("Hello world"))
    }

    @Test("clear is emitted once after a subtitle disappears")
    func clearsOnce() {
        var stabilizer = LiveTextStabilizer()
        _ = stabilizer.ingest("Hello")
        _ = stabilizer.ingest("Hello")
        #expect(stabilizer.ingest("") == nil)
        #expect(stabilizer.ingest("") == .clear)
        #expect(stabilizer.ingest("") == nil)
    }

    @Test("an empty screen at the start emits nothing")
    func silentWhenStartingEmpty() {
        var stabilizer = LiveTextStabilizer()
        #expect(stabilizer.ingest("") == nil)
        #expect(stabilizer.ingest("") == nil)
        #expect(stabilizer.ingest("") == nil)
    }
}
