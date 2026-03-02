import SwiftUI

struct HistoryView: View {
    let historyManager: TranslationHistoryManager

    @State private var expandedRecordID: UUID?
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
                List(historyManager.recentRecords, id: \.id) { record in
                    HistoryRowView(
                        record: record,
                        isExpanded: expandedRecordID == record.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedRecordID == record.id {
                                expandedRecordID = nil
                            } else {
                                expandedRecordID = record.id
                            }
                        }
                    }
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
    let isExpanded: Bool

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

                // 펼침 표시
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // 타임스탬프
                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isExpanded {
                // 펼침: 전체 내용 표시
                expandedContent
            } else {
                // 접힘: 축약 표시
                collapsedContent
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 접힘 상태 (기존과 동일)

    @ViewBuilder
    private var collapsedContent: some View {
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

        if !record.sourceText.isEmpty {
            Text(record.sourceText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - 펼침 상태 (상세 보기)

    @ViewBuilder
    private var expandedContent: some View {
        // 번역문 전체
        if let translated = record.translatedText {
            VStack(alignment: .leading, spacing: 4) {
                Text("번역문")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(translated)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        } else if let error = record.errorMessage {
            Text(error)
                .font(.body)
                .foregroundStyle(.red)
        }

        Divider()

        // 원문 전체
        if !record.sourceText.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("원문")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.sourceText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }

        // 액션 버튼
        HStack(spacing: 12) {
            if let translated = record.translatedText {
                Button("번역문 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translated, forType: .string)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !record.sourceText.isEmpty {
                Button("원문 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.sourceText, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    private func languageName(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
