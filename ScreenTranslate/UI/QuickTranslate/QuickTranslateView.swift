import SwiftUI

struct QuickTranslateView: View {
    @Bindable var model: QuickTranslateModel

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var isInputFocused: Bool

    private var fontSize: CGFloat { AppSettings.shared.popupFontSize }
    private var popupFont: Font { FontManager.shared.swiftUIFont(size: fontSize) }

    var body: some View {
        VStack(spacing: 0) {
            languageBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // 입력/결과 영역 — GeometryReader로 40:60 비율 분할
            GeometryReader { geo in
                VStack(spacing: 0) {
                    inputArea
                        .frame(height: geo.size.height * 0.4)

                    Divider()

                    resultArea
                        .frame(height: geo.size.height * 0.6)
                }
            }

            Divider()

            hintBar
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                : AnyShapeStyle(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12, y: 4)
        .onAppear {
            isInputFocused = true
        }
        .onDisappear {
            model.cancelTasks()
        }
    }

    // MARK: - Language Bar

    private var languageBar: some View {
        HStack {
            Picker(selection: $model.sourceLanguageCode) {
                Text(L10n.autoDetect).tag("auto")
                Divider()
                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L10n.sourceLanguageSelect)

            Button {
                model.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.sourceLanguageCode == "auto")
            .accessibilityLabel(L10n.swapLanguages)

            Picker(selection: $model.targetLanguageCode) {
                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L10n.targetLanguageSelect)
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        TextEditor(text: $model.inputText)
            .font(popupFont)
            .scrollContentBackground(.hidden)
            .focused($isInputFocused)
            .accessibilityLabel(L10n.inputPlaceholder)
            .overlay(alignment: .topLeading) {
                if model.inputText.isEmpty {
                    Text(L10n.inputPlaceholder)
                        .font(popupFont)
                        .foregroundStyle(.secondary)
                        .padding(.top, 0)
                        .padding(.leading, 7)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    // MARK: - Result Area

    private var resultArea: some View {
        Group {
            switch model.coordinator.state {
            case .idle:
                Text(L10n.resultPlaceholder)
                    .font(popupFont)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            case .translating:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.translating)
                        .font(popupFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onAppear {
                    AccessibilityNotification.Announcement(L10n.translating).post()
                }

            case .completed(let result):
                ScrollView {
                    Text(result.translatedText)
                        .font(popupFont)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(L10n.translatedText)
                        .accessibilityValue(result.translatedText)
                }

            case .failed(let message):
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(popupFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .recognizing:
                EmptyView()  // QuickTranslate에서는 사용하지 않음
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Hint Bar

    private var hintBar: some View {
        HStack {
            if model.didCopyResult {
                Label(L10n.copied, systemImage: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text(L10n.quickTranslateHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.didCopyResult)
    }
}
