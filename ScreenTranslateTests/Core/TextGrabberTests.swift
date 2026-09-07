import CoreGraphics
import Testing
@testable import ScreenTranslate

/// TextGrabber의 순수 로직 검증.
/// 합성 Cmd+C 전송·보조키 폴링 자체는 실기 확인 대상 (수동 체크리스트).
@MainActor
struct TextGrabberTests {

    // MARK: - copyBlockingModifiers (이슈 #1)

    @Test("⌘·fn·capsLock만 눌린 상태는 Cmd+C를 방해하지 않는다")
    func harmlessFlagsDoNotBlock() {
        #expect(TextGrabber.copyBlockingModifiers([.maskCommand, .maskSecondaryFn, .maskAlphaShift]).isEmpty)
    }

    @Test("⌥가 눌려 있으면 대기 대상이다")
    func optionBlocks() {
        #expect(TextGrabber.copyBlockingModifiers([.maskCommand, .maskAlternate]) == [.maskAlternate])
    }

    @Test("⇧·⌃ 조합도 대기 대상이다")
    func shiftControlBlock() {
        #expect(
            TextGrabber.copyBlockingModifiers([.maskShift, .maskControl, .maskCommand])
                == [.maskShift, .maskControl]
        )
    }

    @Test("아무 보조키도 없으면 대기하지 않는다")
    func noFlagsDoNotBlock() {
        #expect(TextGrabber.copyBlockingModifiers([]).isEmpty)
    }
}
