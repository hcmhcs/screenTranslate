import SwiftUI
import TelemetryDeck

struct QuickTranslateView: View {
    let coordinator: TranslationCoordinator

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inputText = ""
    @State private var sourceLanguageCode: String = AppSettings.shared.sourceLanguageCode
    @State private var targetLanguageCode: String = AppSettings.shared.targetLanguageCode
    @State private var didCopyResult = false
    @State private var autoCopyTask: Task<Void, Never>?
    @State private var copyFeedbackTask: Task<Void, Never>?

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
            // keyWindow가 설정된 후 콜백을 연결하기 위해 한 틱 지연.
            // .onAppear 시점에는 아직 makeKeyAndOrderFront가 완료되지 않았을 수 있다.
            DispatchQueue.main.async {
                registerWindowCallbacks()
            }
            // 앱 첫 실행 시 keyWindow 설정이 늦을 수 있으므로 fallback 재시도.
            // 1차 성공 시 동일 콜백을 덮어쓸 뿐 부작용 없음.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                registerWindowCallbacks()
            }
        }
        .onDisappear {
            autoCopyTask?.cancel()
            autoCopyTask = nil
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
    }

    // MARK: - Language Bar

    private var languageBar: some View {
        HStack {
            Picker(selection: $sourceLanguageCode) {
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
                swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(sourceLanguageCode == "auto")
            .accessibilityLabel(L10n.swapLanguages)

            Picker(selection: $targetLanguageCode) {
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
        TextEditor(text: $inputText)
            .font(popupFont)
            .scrollContentBackground(.hidden)
            .focused($isInputFocused)
            .accessibilityLabel(L10n.inputPlaceholder)
            .overlay(alignment: .topLeading) {
                if inputText.isEmpty {
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
            switch coordinator.state {
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
            if didCopyResult {
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: didCopyResult)
    }

    // MARK: - Actions

    private func translateText() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        coordinator.sourceLanguage = sourceLanguageCode == "auto"
            ? nil
            : Locale.Language(identifier: sourceLanguageCode)
        coordinator.targetLanguage = Locale.Language(identifier: targetLanguageCode)

        // 이전 자동복사 Task 취소
        autoCopyTask?.cancel()
        autoCopyTask = nil

        coordinator.startProcessing(text: trimmed)

        // stateStream을 지역 변수에 캡처하여 구독.
        // stateStream은 computed property — 접근할 때마다 이전 continuation을 finish()한다.
        // 지역 변수에 저장하면 이후 접근에 의한 조기 종료를 방지한다.
        let stream = coordinator.stateStream
        autoCopyTask = Task { @MainActor in
            for await state in stream {
                switch state {
                case .completed(let result):
                    TelemetryDeck.signal("quickTranslateCompleted", parameters: ["engine": coordinator.translationProvider.name])
                    // 히스토리 기록
                    AppOrchestrator.shared.historyManager.recordSuccess(
                        sourceText: result.sourceText,
                        translatedText: result.translatedText,
                        sourceLanguageCode: result.sourceLanguage?.minimalIdentifier,
                        targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                    )
                    // 자동복사
                    if AppSettings.shared.autoCopyToClipboard {
                        Clipboard.copy(result.translatedText)
                        showCopyFeedback()
                    }
                    return

                case .failed(let message):
                    AppOrchestrator.shared.historyManager.recordFailure(
                        sourceText: trimmed,
                        errorMessage: message,
                        targetLanguageCode: coordinator.targetLanguage.minimalIdentifier
                    )
                    return

                case .idle:
                    return  // 취소됨

                case .recognizing, .translating:
                    continue
                }
            }
        }
    }

    private func swapLanguages() {
        guard sourceLanguageCode != "auto" else { return }
        let oldSource = sourceLanguageCode
        let oldTarget = targetLanguageCode
        sourceLanguageCode = oldTarget
        targetLanguageCode = oldSource

        // 입력/결과 텍스트 교환
        if case .completed(let result) = coordinator.state {
            inputText = result.translatedText
            coordinator.cancel()  // 상태를 idle로 리셋
        }
    }

    private func copyResultToClipboard() {
        if case .completed(let result) = coordinator.state {
            Clipboard.copy(result.translatedText)
            showCopyFeedback()
        }
    }

    private func showCopyFeedback() {
        copyFeedbackTask?.cancel()
        didCopyResult = true
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            didCopyResult = false
        }
    }

    /// NSPanel의 키 이벤트 콜백을 연결한다.
    /// NOTE: [self] 캡처는 struct 복사본이지만, @State는 SwiftUI 외부 스토리지를 통해
    /// 최신 값을 참조하고 coordinator는 참조 타입이므로 안전하다.
    private func registerWindowCallbacks() {
        guard let panel = NSApp.keyWindow as? QuickTranslateWindow else { return }
        panel.onTranslateAction = { [self] in translateText() }
        panel.onCopyResultAction = { [self] in copyResultToClipboard() }
        panel.onSwapAction = { [self] in swapLanguages() }
    }
}
