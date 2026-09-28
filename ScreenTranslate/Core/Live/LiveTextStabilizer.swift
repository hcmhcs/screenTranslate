import Foundation

/// 실시간 번역에서 글자 인식 결과의 흔들림을 걸러 "새로 확정된 자막"만 내보낸다.
/// 영상 위 자막은 프레임마다 인식이 조금씩 달라질 수 있어, 같은 결과가 연속으로 나올 때만 믿는다.
nonisolated struct LiveTextStabilizer {
    enum Event: Equatable, Sendable {
        case show(String)
        case clear
    }

    private let requiredRepeats: Int
    private var candidate: String?
    private var repeats = 0
    /// 마지막으로 내보낸 값 — ""은 지운 상태, nil은 아직 아무것도 내보내지 않음
    private var lastEmitted: String?

    init(requiredRepeats: Int = 2) {
        self.requiredRepeats = max(1, requiredRepeats)
    }

    mutating func ingest(_ recognized: String) -> Event? {
        let text = Self.normalize(recognized)
        if text == candidate {
            repeats += 1
        } else {
            candidate = text
            repeats = 1
        }
        guard repeats >= requiredRepeats, text != lastEmitted else { return nil }
        if text.isEmpty, lastEmitted == nil {
            // 처음부터 빈 화면이면 지울 것이 없다
            lastEmitted = ""
            return nil
        }
        lastEmitted = text
        return text.isEmpty ? .clear : .show(text)
    }

    /// 앞뒤 공백을 없애고 연속 공백·줄바꿈을 한 칸으로 합친다 (두 줄 자막을 한 문장으로)
    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
