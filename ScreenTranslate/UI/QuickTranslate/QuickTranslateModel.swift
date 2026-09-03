import Foundation
import Observation

/// 빠른 번역 패널의 상태와 동작.
///
/// 뷰(QuickTranslateView)는 표시만 담당하고, 윈도우(QuickTranslateWindow)의 키 모니터는
/// 이 모델의 메서드를 직접 호출한다. 이전에는 뷰가 `NSApp.keyWindow`를 찾아 콜백을 꽂는 방식이라
/// 창이 key가 되는 타이밍에 따라 Enter·⌘⇧C·⌘/가 먹통이 되는 문제가 있었다.
///
/// 의존성(히스토리, 자동복사 설정, 클립보드, 텔레메트리)은 주입받아 테스트에서 대체한다.
@MainActor @Observable
final class QuickTranslateModel {
    let coordinator: TranslationCoordinator

    var inputText = ""
    /// "auto"이면 자동 감지
    var sourceLanguageCode: String
    var targetLanguageCode: String
    private(set) var didCopyResult = false

    @ObservationIgnored private let historyManager: TranslationHistoryManager
    @ObservationIgnored private let autoCopyEnabled: () -> Bool
    @ObservationIgnored private let copyToClipboard: (String) -> Void
    @ObservationIgnored private let telemetry: (String) -> Void
    @ObservationIgnored private var observeTask: Task<Void, Never>?
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?

    init(
        coordinator: TranslationCoordinator,
        historyManager: TranslationHistoryManager,
        sourceLanguageCode: String,
        targetLanguageCode: String,
        autoCopyEnabled: @escaping () -> Bool,
        copyToClipboard: @escaping (String) -> Void,
        telemetry: @escaping (String) -> Void
    ) {
        self.coordinator = coordinator
        self.historyManager = historyManager
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.autoCopyEnabled = autoCopyEnabled
        self.copyToClipboard = copyToClipboard
        self.telemetry = telemetry
    }

    // MARK: - Actions

    /// 입력 텍스트를 번역한다. 완료되면 히스토리에 기록하고 설정에 따라 자동 복사한다.
    func translate() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        coordinator.sourceLanguage = sourceLanguageCode == "auto"
            ? nil
            : Locale.Language(identifier: sourceLanguageCode)
        coordinator.targetLanguage = Locale.Language(identifier: targetLanguageCode)

        observeTask?.cancel()
        observeTask = nil

        coordinator.startProcessing(text: trimmed)

        // 스트림은 startProcessing 직후에 만들어 현재 실행의 상태만 받는다.
        let stream = coordinator.makeStateStream()
        let targetCode = coordinator.targetLanguage.minimalIdentifier
        observeTask = Task { [weak self] in
            for await state in stream {
                guard let self, !Task.isCancelled else { return }
                switch state {
                case .completed(let result):
                    self.telemetry(self.coordinator.translationProvider.name)
                    self.historyManager.recordSuccess(
                        sourceText: result.sourceText,
                        translatedText: result.translatedText,
                        sourceLanguageCode: result.sourceLanguage?.minimalIdentifier,
                        targetLanguageCode: targetCode
                    )
                    if self.autoCopyEnabled() {
                        self.copyToClipboard(result.translatedText)
                        self.showCopyFeedback()
                    }
                    return

                case .failed(let message):
                    self.historyManager.recordFailure(
                        sourceText: trimmed,
                        errorMessage: message,
                        targetLanguageCode: targetCode
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

    /// 소스·타겟 언어를 바꾼다. 결과가 있으면 결과를 입력으로 옮기고 결과를 비운다.
    func swapLanguages() {
        guard sourceLanguageCode != "auto" else { return }
        let oldSource = sourceLanguageCode
        sourceLanguageCode = targetLanguageCode
        targetLanguageCode = oldSource

        if case .completed(let result) = coordinator.state {
            inputText = result.translatedText
            coordinator.cancel()  // 상태를 idle로 리셋
        }
    }

    /// 번역 결과를 클립보드에 복사한다. 결과가 없으면 아무것도 하지 않는다.
    func copyResult() {
        guard case .completed(let result) = coordinator.state else { return }
        copyToClipboard(result.translatedText)
        showCopyFeedback()
    }

    /// 패널을 닫을 때: 입력·결과·진행 중 작업을 비운다. 언어 선택은 유지한다.
    func resetForNewSession() {
        cancelTasks()
        coordinator.cancel()
        inputText = ""
        didCopyResult = false
    }

    /// 뷰가 사라질 때 진행 중인 관찰·피드백 태스크를 멈춘다.
    func cancelTasks() {
        observeTask?.cancel()
        observeTask = nil
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
    }

    private func showCopyFeedback() {
        copyFeedbackTask?.cancel()
        didCopyResult = true
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            self?.didCopyResult = false
        }
    }
}
