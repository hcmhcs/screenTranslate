import SwiftUI

struct HistoryView: View {
    let historyManager: TranslationHistoryManager
    var initialExpandedID: UUID?
    /// 스토어를 열 수 없어 인메모리로 동작 중이면 경고 배너를 띄운다 (H2)
    var isInMemory = false

    @State private var expandedRecordID: UUID?
    @State private var showingDeleteAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // 툴바
            HStack {
                Text(L10n.translationHistory)
                    .font(.headline)

                Spacer()

                Button(L10n.deleteAll, role: .destructive) {
                    showingDeleteAllConfirm = true
                }
                .buttonStyle(.bordered)
                .disabled(historyManager.recentRecords.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if isInMemory {
                Label(L10n.historyNotPersisted, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                Divider()
            }

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
                            Button(L10n.copyTranslation) {
                                copyToClipboard(translated)
                            }
                        }
                        Button(L10n.copyOriginal) {
                            copyToClipboard(record.sourceText)
                        }
                        Divider()
                        Button(L10n.delete, role: .destructive) {
                            historyManager.delete(record)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(minWidth: 500, idealWidth: 600, maxWidth: .infinity,
               minHeight: 400, idealHeight: 500, maxHeight: .infinity)
        .confirmationDialog(L10n.deleteAll, isPresented: $showingDeleteAllConfirm) {
            Button(L10n.deleteAllHistory, role: .destructive) {
                historyManager.deleteAll()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.deleteAllConfirmation)
        }
        .onAppear {
            historyManager.fetchRecent()
            if let id = initialExpandedID {
                expandedRecordID = id
            }
        }
        .onChange(of: initialExpandedID) { _, newValue in
            // H5: 창이 이미 열려 있을 때 rootView가 교체되면 onAppear는 다시 호출되지 않는다
            if let newValue {
                expandedRecordID = newValue
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(L10n.noHistoryMessage)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyToClipboard(_ text: String) {
        Clipboard.copy(text)
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
                    .accessibilityLabel(record.isSuccess ? L10n.historySucceeded : L10n.historyFailed)

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
                Text(L10n.smartTimestamp(for: record.timestamp))
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
                Text(L10n.translatedText)
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
                Text(L10n.originalText)
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
                Button(L10n.copyTranslation) {
                    Clipboard.copy(translated)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !record.sourceText.isEmpty {
                Button(L10n.copyOriginal) {
                    Clipboard.copy(record.sourceText)
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
