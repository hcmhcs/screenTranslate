import SwiftUI

struct HistoryView: View {
    let historyManager: TranslationHistoryManager

    @State private var selectedRecord: TranslationRecord?
    @State private var showingDeleteAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // 툴바
            HStack {
                Text("번역 히스토리")
                    .font(.headline)

                Spacer()

                Button("전체 삭제", role: .destructive) {
                    showingDeleteAllConfirm = true
                }
                .buttonStyle(.bordered)
                .disabled(historyManager.recentRecords.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 히스토리 목록
            if historyManager.recentRecords.isEmpty {
                emptyView
            } else {
                List(historyManager.recentRecords, id: \.id, selection: $selectedRecord) { record in
                    HistoryRowView(record: record)
                        .contextMenu {
                            if let translated = record.translatedText {
                                Button("번역문 복사") {
                                    copyToClipboard(translated)
                                }
                            }
                            Button("원문 복사") {
                                copyToClipboard(record.sourceText)
                            }
                            Divider()
                            Button("삭제", role: .destructive) {
                                historyManager.delete(record)
                            }
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 800,
               minHeight: 400, idealHeight: 500, maxHeight: 700)
        .confirmationDialog("전체 삭제", isPresented: $showingDeleteAllConfirm) {
            Button("모든 히스토리 삭제", role: .destructive) {
                historyManager.deleteAll()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 번역 히스토리가 삭제됩니다.\n이 작업은 되돌릴 수 없습니다.")
        }
        .onAppear {
            historyManager.fetchRecent()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("번역 히스토리가 없습니다")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Row View

struct HistoryRowView: View {
    let record: TranslationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // 상태 아이콘
                Image(systemName: record.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(record.isSuccess ? .green : .red)
                    .font(.caption)

                // 언어 정보
                if let sourceLang = record.sourceLanguageCode {
                    Text(languageName(for: sourceLang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(languageName(for: record.targetLanguageCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // 타임스탬프
                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // 번역문 또는 에러
            if let translated = record.translatedText {
                Text(translated)
                    .font(.body)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else if let error = record.errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            // 원문 (축약)
            if !record.sourceText.isEmpty {
                Text(record.sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func languageName(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
