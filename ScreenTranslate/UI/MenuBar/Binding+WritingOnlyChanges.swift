import SwiftUI

extension Binding where Value: Equatable {
    /// 현재 값과 같은 쓰기는 버리는 바인딩.
    ///
    /// MenuBarExtra(isInserted:)는 갱신 때마다 현재 표시 상태를 바인딩에 되써넣는다.
    /// @AppStorage는 같은 값도 UserDefaults에 다시 쓰고 그 변경으로 Scene을 다시 갱신하므로,
    /// 그대로 연결하면 메인 스레드가 CPU 100%로 도는 무한 루프가 된다 (2026-09-29 실측, XCTest 호스트도 멈춤).
    func writingOnlyChanges() -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                guard newValue != wrappedValue else { return }
                wrappedValue = newValue
            }
        )
    }
}
