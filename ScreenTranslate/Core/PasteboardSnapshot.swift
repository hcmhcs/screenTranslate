import AppKit

/// 클립보드의 모든 항목·타입·데이터를 스냅샷으로 보관했다가 그대로 복원한다.
/// TextGrabber의 Cmd+C 폴백이 사용자의 클립보드(이미지, 파일, 서식 텍스트 포함)를
/// 잃어버리지 않게 하기 위한 것이다 (C3).
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    /// 스냅샷 시점의 내용으로 되돌린다. 비어 있었으면 빈 상태로 만든다.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
