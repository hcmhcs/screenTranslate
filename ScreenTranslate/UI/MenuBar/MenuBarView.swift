import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button("번역하기") {
            AppOrchestrator.shared.startTranslation()
        }
        .globalKeyboardShortcut(.translate)

        Divider()

        // 최근 번역 서브메뉴
        let records = AppOrchestrator.shared.historyManager.recentRecords
        Menu("최근 번역") {
            if records.isEmpty {
                Text("히스토리 없음")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(5), id: \.id) { record in
                    Button {
                        if let translated = record.translatedText {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(translated, forType: .string)
                        }
                    } label: {
                        Label {
                            Text(record.translatedText ?? record.errorMessage ?? "")
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: record.isSuccess
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                        }
                    }
                }

                Divider()

                Button("모두 보기...") {
                    AppOrchestrator.shared.showHistory()
                }
                .keyboardShortcut("H", modifiers: [.command, .shift])
            }
        }

        Divider()

        SettingsLink {
            Text("설정...")
        }

        Divider()

        Button("ScreenTranslate 종료") {
            NSApplication.shared.terminate(nil)
        }
    }
}
