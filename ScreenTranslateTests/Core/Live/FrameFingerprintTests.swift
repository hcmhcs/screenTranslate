import Testing
@testable import ScreenTranslate

/// 화면 지문 — 직전 프레임과 거의 같으면 글자 인식을 건너뛴다.
@Suite struct FrameFingerprintTests {

    @Test("the same frame is identical")
    func sameFrame() throws {
        let a = try #require(FrameFingerprint(image: TestImages.block(at: 10)))
        let b = try #require(FrameFingerprint(image: TestImages.block(at: 10)))
        #expect(a.isNearlyIdentical(to: b))
    }

    @Test("tiny brightness noise counts as the same frame")
    func toleratesNoise() throws {
        let a = try #require(FrameFingerprint(image: TestImages.gray(100)))
        let b = try #require(FrameFingerprint(image: TestImages.gray(104)))
        #expect(a.isNearlyIdentical(to: b))
    }

    @Test("text moving to another place is a different frame")
    func detectsLocalChange() throws {
        let a = try #require(FrameFingerprint(image: TestImages.block(at: 10)))
        let b = try #require(FrameFingerprint(image: TestImages.block(at: 60)))
        #expect(!a.isNearlyIdentical(to: b))
    }

    @Test("a large brightness change is a different frame")
    func detectsGlobalChange() throws {
        let a = try #require(FrameFingerprint(image: TestImages.gray(50)))
        let b = try #require(FrameFingerprint(image: TestImages.gray(200)))
        #expect(!a.isNearlyIdentical(to: b))
    }
}
