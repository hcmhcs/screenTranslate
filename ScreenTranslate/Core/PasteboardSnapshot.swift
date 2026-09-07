import AppKit

/// 클립보드의 모든 항목·타입·데이터를 스냅샷으로 보관했다가 그대로 복원한다.
/// TextGrabber의 Cmd+C 폴백이 사용자의 클립보드(이미지, 파일, 서식 텍스트 포함)를
/// 잃어버리지 않게 하기 위한 것이다 (C3).
struct PasteboardSnapshot {
    /// 항목마다 (타입, 데이터) 배열. `NSPasteboardItem.types`의 순서가 붙여넣는 쪽의 우선순위라 순서를 보존한다.
    private let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    /// 이보다 큰 타입은 건너뛴다 — 메인 스레드에서 거대한 페이로드를 실체화·복사하지 않기 위해
    static let maxBytesPerType = 32 * 1024 * 1024

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                // 파일 프로미스는 원래 소유자만 이행할 수 있어 복원해도 죽은 프로미스가 된다 → 제외
                guard !type.rawValue.localizedCaseInsensitiveContains("promise") else { return nil }
                guard let data = item.data(forType: type), data.count <= Self.maxBytesPerType else { return nil }
                return (type, data)
            }
        }
    }

    /// 스냅샷 시점의 내용으로 되돌린다. 비어 있었으면 빈 상태로 만든다.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.compactMap { entries -> NSPasteboardItem? in
            guard !entries.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for entry in entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        guard !restored.isEmpty else { return }
        pasteboard.writeObjects(restored)
    }
}
