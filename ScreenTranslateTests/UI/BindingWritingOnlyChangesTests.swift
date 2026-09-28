import SwiftUI
import Testing
@testable import ScreenTranslate

/// MenuBarExtra(isInserted:)는 갱신 때마다 현재 값을 바인딩에 되써넣는다.
/// @AppStorage는 같은 값도 UserDefaults에 다시 써서 갱신을 일으키므로 무한 루프(CPU 100%)가 된다.
/// 같은 값 쓰기를 걸러내는 바인딩이 이 루프를 끊는다.
@MainActor
@Suite struct BindingWritingOnlyChangesTests {

    private final class Store {
        var value = true
        var writes = 0
    }

    private func makeBinding(_ store: Store) -> Binding<Bool> {
        Binding(
            get: { store.value },
            set: { newValue in
                store.value = newValue
                store.writes += 1
            }
        )
    }

    @Test("writing the current value never reaches the underlying setter")
    func sameValueIsDropped() {
        let store = Store()
        let binding = makeBinding(store).writingOnlyChanges()

        binding.wrappedValue = true
        binding.wrappedValue = true

        #expect(store.writes == 0)
    }

    @Test("writing a different value reaches the underlying setter once")
    func changedValueIsWritten() {
        let store = Store()
        let binding = makeBinding(store).writingOnlyChanges()

        binding.wrappedValue = false

        #expect(store.writes == 1)
        #expect(store.value == false)
        #expect(binding.wrappedValue == false)
    }
}
