import CoreGraphics
import Foundation
import Observation

/// 실시간 자막 번역의 감시 루프 (PR #4 아이디어를 베타로 재구현).
/// 캡처 → 화면 변화 확인 → 글자 인식 → 안정화 → Apple 번역 → 표시를 주기마다 반복한다.
/// 의존성을 모두 주입받아 가짜 캡처·인식·번역으로 테스트한다.
@MainActor @Observable
final class LiveTranslationSession {
    struct Dependencies {
        var frameSource: LiveFrameSource
        var ocr: OCRProvider
        var translator: TranslationProvider
        /// Apple 번역 브리지가 요청을 처리 중인지 — 자기 요청이 없는데 true면 다른 기능이 쓰는 중이다
        var isTranslatorBusy: () -> Bool
        var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        var interval: Duration = .milliseconds(333)
    }

    enum Display: Equatable {
        case hidden
        case subtitle(String)
        case message(String)
    }

    enum StopReason: Equatable {
        case user
        case screenLocked
        case displayRemoved
        case betaDisabled
        case captureFailed(String)
    }

    private(set) var display: Display = .hidden
    private(set) var isRunning = false
    private(set) var translationCount = 0
    @ObservationIgnored var onDisplayChange: ((Display) -> Void)?
    @ObservationIgnored var onStop: ((StopReason) -> Void)?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let region: () -> LiveRegion?
    @ObservationIgnored private let languages: () -> (source: Locale.Language?, target: Locale.Language)
    @ObservationIgnored private let preprocess: () -> Bool

    @ObservationIgnored private var stabilizer = LiveTextStabilizer()
    @ObservationIgnored private var lastFingerprint: FrameFingerprint?
    @ObservationIgnored private var lastRecognized: String?
    @ObservationIgnored private var pendingText: String?
    @ObservationIgnored private var hasShownSubtitle = false
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var translationTask: Task<Void, Never>?
    @ObservationIgnored private var translationToken = UUID()

    init(
        dependencies: Dependencies,
        region: @escaping () -> LiveRegion?,
        languages: @escaping () -> (source: Locale.Language?, target: Locale.Language),
        preprocess: @escaping () -> Bool
    ) {
        self.dependencies = dependencies
        self.region = region
        self.languages = languages
        self.preprocess = preprocess
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        setDisplay(.message(L10n.liveWaitingForText))
        loopTask = Task { [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                await self.tick()
                do {
                    try await self.dependencies.sleep(self.dependencies.interval)
                } catch {
                    return
                }
            }
        }
    }

    /// 여러 번 불러도 한 번만 정리하고 알린다
    func stop(_ reason: StopReason) {
        guard isRunning else { return }
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        cancelTranslation()
        pendingText = nil
        setDisplay(.hidden)
        onStop?(reason)
    }

    /// 한 번의 감시 — 루프가 주기마다 부른다
    func tick() async {
        guard isRunning, let region = region() else { return }
        let image: CGImage
        do {
            image = try await dependencies.frameSource.captureFrame(of: region)
        } catch is CancellationError {
            return
        } catch {
            stop(.captureFailed(error.localizedDescription))
            return
        }
        guard isRunning, let recognized = await recognizeIfChanged(image), isRunning else { return }

        let text = preprocess() ? TranslationCoordinator.preprocessOCRText(recognized) : recognized
        switch stabilizer.ingest(text) {
        case .show(let subtitle):
            cancelTranslation()
            pendingText = subtitle
        case .clear:
            cancelTranslation()
            pendingText = nil
            if hasShownSubtitle { setDisplay(.hidden) }
        case nil:
            break
        }
        startPendingTranslationIfPossible()
    }

    // MARK: - Private

    private func setDisplay(_ newValue: Display) {
        guard display != newValue else { return }
        display = newValue
        onDisplayChange?(newValue)
    }

    /// 화면이 직전과 거의 같으면 인식을 건너뛰고 직전 결과를 쓴다. 인식이 실패하면 이번 틱은 건너뛴다(nil).
    private func recognizeIfChanged(_ image: CGImage) async -> String? {
        let fingerprint = FrameFingerprint(image: image)
        if let fingerprint, let lastFingerprint, let lastRecognized,
           fingerprint.isNearlyIdentical(to: lastFingerprint) {
            return lastRecognized
        }
        let text: String
        do {
            text = try await dependencies.ocr.recognize(image: image).text
        } catch OCRError.noTextFound {
            text = ""
        } catch {
            return nil
        }
        lastFingerprint = fingerprint
        lastRecognized = text
        return text
    }

    private func startPendingTranslationIfPossible() {
        guard isRunning, let text = pendingText, translationTask == nil else { return }
        // 자기 요청이 없는데 브리지가 바쁘면 다른 기능(화면·빠른 번역)이 쓰는 중 — 사용자가 직접 한 번역이 우선
        guard !dependencies.isTranslatorBusy() else { return }
        pendingText = nil
        let token = UUID()
        translationToken = token
        let (source, target) = languages()
        let translator = dependencies.translator
        translationTask = Task { [weak self] in
            do {
                let translated = try await translator.translate(text: text, from: source, to: target)
                self?.finishTranslation(token, text: text, result: .success(translated))
            } catch {
                self?.finishTranslation(token, text: text, result: .failure(error))
            }
        }
    }

    private func finishTranslation(_ token: UUID, text: String, result: Result<String, Error>) {
        guard token == translationToken else { return }  // 새 자막에 밀린 옛 결과
        translationTask = nil
        guard isRunning else { return }
        switch result {
        case .success(let translated):
            hasShownSubtitle = true
            translationCount += 1
            setDisplay(.subtitle(translated))
        case .failure(let error):
            if let translationError = error as? TranslationError, case .superseded = translationError {
                pendingText = pendingText ?? text  // 다른 기능에 밀림 — 다음 틱에 다시
            } else if !(error is CancellationError) {
                // 같은 자막은 안정화기가 다시 내보내지 않으므로 재시도하지 않는다
                setDisplay(.message(error.localizedDescription))
            }
        }
    }

    private func cancelTranslation() {
        translationToken = UUID()
        translationTask?.cancel()
        translationTask = nil
    }
}
