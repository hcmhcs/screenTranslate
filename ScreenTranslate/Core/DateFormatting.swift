import Foundation

enum DateFormatting {
    /// 경과 시간을 "m:ss" 형식으로 반환한다.
    static func elapsedText(from start: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(start))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
