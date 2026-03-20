import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button(L10n.translate) {
            AppOrchestrator.shared.startTranslation()
        }
        .globalKeyboardShortcut(.translate)

        Button(L10n.dragTranslate) {
            AppOrchestrator.shared.startDragTranslation()
        }
        .globalKeyboardShortcut(.dragTranslate)

        Button(L10n.quickTranslate) {
            AppOrchestrator.shared.toggleQuickTranslate()
        }
        .globalKeyboardShortcut(.quickTranslate)

        Divider()

        // 최근 번역 서브메뉴
        let records = AppOrchestrator.shared.historyManager.recentRecords
        Menu(L10n.recentTranslations) {
            if records.isEmpty {
                Text(L10n.noHistory)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(5), id: \.id) { record in
                    Button {
                        AppOrchestrator.shared.showHistory(expandingRecord: record.id)
                    } label: {
                        Label {
                            let text = record.translatedText ?? record.errorMessage ?? ""
                            Text(text.count > 40 ? String(text.prefix(40)) + "…" : text)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: record.isSuccess
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                        }
                    }
                }

                Divider()

                Button(L10n.showAll) {
                    AppOrchestrator.shared.showHistory()
                }
                .keyboardShortcut("H", modifiers: [.command, .shift])
            }
        }

        Divider()

        Button(L10n.aboutApp) {
            AppOrchestrator.shared.showAbout()
        }

        Button(L10n.settingsMenu) {
            AppOrchestrator.shared.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(L10n.quit) {
            NSApplication.shared.terminate(nil)
        }
    }
}
