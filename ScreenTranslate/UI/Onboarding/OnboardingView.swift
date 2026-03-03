import KeyboardShortcuts
import SwiftUI
import Translation

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var packManager = LanguagePackManager()
    @State private var selectedTargetCode: String = AppSettings.shared.targetLanguageCode
    @State private var isDownloading = false
    @State private var downloadCompleted = false
    var onComplete: () -> Void

    private let totalSteps = 2

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 20)

            // Content
            Group {
                if currentStep == 0 {
                    shortcutStep
                } else {
                    languagePackStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 480, height: 360)
        .task {
            await packManager.refreshAllStatuses()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Shortcut

    private var shortcutStep: some View {
        VStack(spacing: 20) {
            Text(L10n.onboardingWelcome)
                .font(.title2)
                .fontWeight(.bold)

            Text(L10n.onboardingShortcutTitle)
                .font(.headline)

            Text(L10n.onboardingShortcutDesc)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // 사용 흐름 시각 설명
            HStack(spacing: 16) {
                flowItem(icon: "command", text: L10n.onboardingFlow1)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                flowItem(icon: "rectangle.dashed", text: L10n.onboardingFlow2)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                flowItem(icon: "text.bubble", text: L10n.onboardingFlow3)
            }
            .padding(.vertical, 8)

            // 단축키 레코더
            VStack(spacing: 6) {
                KeyboardShortcuts.Recorder(L10n.translationShortcut, name: .translate)
                Text(L10n.onboardingChangeHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 32)
    }

    private func flowItem(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: Language Pack

    private var languagePackStep: some View {
        VStack(spacing: 20) {
            Text(L10n.onboardingLangTitle)
                .font(.title2)
                .fontWeight(.bold)

            if AppSettings.systemLanguageIsSupported {
                // 시스템 언어가 지원됨 → 자동 설정 안내
                autoLanguageContent
            } else {
                // 영어/기타 → 언어 선택 UI
                chooseLanguageContent
            }

            // 언어팩 상태 표시
            languagePackStatus
        }
        .padding(.horizontal, 32)
    }

    private var autoLanguageContent: some View {
        VStack(spacing: 12) {
            Text(L10n.onboardingLangAutoSet)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            let targetName = AppSettings.supportedLanguages.first(where: { $0.code == selectedTargetCode })?.name ?? selectedTargetCode
            Text("English → \(targetName)")
                .font(.title3)
                .fontWeight(.semibold)
        }
    }

    private var chooseLanguageContent: some View {
        VStack(spacing: 12) {
            Text(L10n.onboardingLangChoose)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("", selection: $selectedTargetCode) {
                ForEach(AppSettings.supportedLanguages.filter({ $0.code != "en" }), id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            .onChange(of: selectedTargetCode) { _, newValue in
                AppSettings.shared.targetLanguageCode = newValue
                Task { await packManager.refreshAllStatuses() }
            }
        }
    }

    private var languagePackStatus: some View {
        Group {
            let status = packManager.languageStatuses[selectedTargetCode]
            if isDownloading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.downloading)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if status == .installed || downloadCompleted {
                Label(L10n.onboardingLangInstalled, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if status == .available {
                VStack(spacing: 8) {
                    Label(L10n.onboardingLangNotInstalled, systemImage: "arrow.down.circle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Button(L10n.download) {
                        downloadLanguagePack()
                    }
                    .controlSize(.regular)
                }
            } else {
                // unsupported 또는 아직 로딩 중
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button(action: { currentStep -= 1 }) {
                    Text("←")
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button(L10n.onboardingNext) {
                    currentStep += 1
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.onboardingSkip) {
                    finishOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.large)

                Button(L10n.onboardingDone) {
                    finishOnboarding()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func downloadLanguagePack() {
        isDownloading = true
        Task {
            let downloadCode = selectedTargetCode
            // 온보딩에서는 항상 타겟 언어를 다운로드하므로 SettingsView의 source/target 조건 분기가 불필요.
            // "en" 폴백: macOS에는 영어가 항상 사전 설치되어 있으므로 안전한 기본값.
            let installedRef = packManager.findInstalledLanguage(excluding: downloadCode) ?? "en"

            let source = Locale.Language(identifier: installedRef)
            let target = Locale.Language(identifier: downloadCode)

            do {
                _ = try await TranslationBridge.shared.translate(
                    text: " ", from: source, to: target
                )
            } catch {
                // 다운로드 프롬프트 표시 후 실패해도 계속 진행
            }
            await packManager.refreshAllStatuses()
            isDownloading = false

            if packManager.languageStatuses[downloadCode] == .installed {
                downloadCompleted = true
            }
        }
    }

    private func finishOnboarding() {
        AppSettings.shared.targetLanguageCode = selectedTargetCode
        AppSettings.shared.hasCompletedOnboarding = true
        onComplete()
    }
}
