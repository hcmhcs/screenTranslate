import SwiftUI

struct TranslationPopupView: View {
    let state: TranslationCoordinator.State
    let onCopy: (String) -> Void
    let onClose: () -> Void
    let onToggleOriginal: (Bool) -> Void

    @State private var didCopy = false
    @State private var showingOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .idle:
                EmptyView()

            case .recognizing:
                loadingView(message: L10n.recognizing)

            case .translating:
                loadingView(message: L10n.translating)

            case .completed(let result):
                completedView(result: result)

            case .failed(let message):
                errorView(message: message)
            }

            HStack {
                if case .completed = state {
                    Toggle(L10n.showOriginal, isOn: $showingOriginal)
                        .toggleStyle(.checkbox)
                        .onChange(of: showingOriginal) { _, newValue in
                            onToggleOriginal(newValue)
                        }
                }

                Spacer()

                if case .completed(let result) = state {
                    Button(didCopy ? L10n.copied : L10n.copy) {
                        onCopy(result.translatedText)
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            didCopy = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(didCopy ? .green : .accentColor)
                    .keyboardShortcut("c", modifiers: .command)
                }

                Button(L10n.close) {
                    onClose()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.2), value: showingOriginal)
    }

    // MARK: - Subviews

    private func loadingView(message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    private func completedView(result: TranslationCoordinator.TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.lowConfidence {
                Label(L10n.lowConfidence, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // 번역문 — 짧은 텍스트는 자연 크기, 긴 텍스트만 스크롤
            ScrollView {
                Text(result.translatedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)

            // 원문 (토글 시)
            if showingOriginal {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.originalText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let lang = result.sourceLanguage {
                            Text(Locale.current.localizedString(
                                forIdentifier: lang.minimalIdentifier) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ScrollView {
                        Text(result.sourceText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
