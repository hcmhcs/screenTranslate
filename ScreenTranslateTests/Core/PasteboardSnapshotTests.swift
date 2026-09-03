import AppKit
import XCTest
@testable import ScreenTranslate

final class PasteboardSnapshotTests: XCTestCase {

    /// 시스템 클립보드를 건드리지 않도록 이름 있는 임시 보드를 쓴다.
    private func makeBoard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.screentranslate.tests.\(UUID().uuidString)"))
    }

    func test_restore_bringsBackMultipleTypes() {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .tiff)
        board.writeObjects([item])

        let snapshot = PasteboardSnapshot(of: board)

        board.clearContents()
        board.setString("overwritten", forType: .string)
        XCTAssertNil(board.data(forType: .tiff))

        snapshot.restore(to: board)

        XCTAssertEqual(board.string(forType: .string), "hello")
        XCTAssertEqual(board.data(forType: .tiff), Data([1, 2, 3]))
    }

    func test_restore_preservesTypeOrder() {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(Data([9]), forType: .tiff)
        item.setString("text", forType: .string)
        item.setData(Data([1]), forType: .rtf)
        board.writeObjects([item])
        let originalTypes = board.pasteboardItems?.first?.types

        let snapshot = PasteboardSnapshot(of: board)
        board.clearContents()
        snapshot.restore(to: board)

        XCTAssertEqual(board.pasteboardItems?.first?.types, originalTypes, "타입 순서는 붙여넣기 우선순위라 보존해야 한다")
    }

    func test_snapshot_skipsFilePromises() {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("text", forType: .string)
        let promiseType = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type")
        item.setData(Data("public.png".utf8), forType: promiseType)
        board.writeObjects([item])

        let snapshot = PasteboardSnapshot(of: board)
        board.clearContents()
        snapshot.restore(to: board)

        XCTAssertEqual(board.string(forType: .string), "text")
        XCTAssertNil(board.data(forType: promiseType), "복원할 수 없는 프로미스는 스냅샷에서 제외한다")
    }

    func test_restore_emptyBoard_leavesBoardEmpty() {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        board.clearContents()

        let snapshot = PasteboardSnapshot(of: board)
        board.setString("temp", forType: .string)

        snapshot.restore(to: board)

        XCTAssertNil(board.string(forType: .string))
        XCTAssertTrue((board.pasteboardItems ?? []).isEmpty)
    }

    func test_restore_preservesMultipleItems() {
        let board = makeBoard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let first = NSPasteboardItem()
        first.setString("one", forType: .string)
        let second = NSPasteboardItem()
        second.setString("two", forType: .string)
        board.writeObjects([first, second])

        let snapshot = PasteboardSnapshot(of: board)
        board.clearContents()
        snapshot.restore(to: board)

        let strings = (board.pasteboardItems ?? []).compactMap { $0.string(forType: .string) }
        XCTAssertEqual(strings, ["one", "two"])
    }
}
