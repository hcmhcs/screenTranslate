import CoreGraphics
import KeyboardShortcuts
import SwiftUI
import Translation

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var packManager = LanguagePackManager()
    @State private var selectedTargetCode: String = AppSettings.shared.targetLanguageCode
    @State private var isDownloading = false
    @State private var downloadCompleted = false
    @State private var downloadStartTime: Date?
    var permissionChecker: PermissionChecking = SystemPermissionChecker()
    var onComplete: () -> Void

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 20)

            // Content
            Group {
                switch currentStep {
                case 0:
                    permissionStep
                case 1:
                    shortcutStep
                default:
                    languagePackStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 480, height: 420)
        .onAppear {
            // 권한이 이미 있으면 Step 1(권한)을 건너뛰고 Step 2(단축키)로 이동
            if permissionChecker.hasScreenCapturePermission() {
                currentStep = 1
            }
        }
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

    // MARK: - Step 1: Permission

    private var permissionStep: some View {
        VStack(spacing: 16) {
            Text(L10n.onboardingWelcome)
                .font(.title2)
                .fontWeight(.bold)

            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(L10n.onboardingPermDesc)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // 프라이버시 보장 항목
            VStack(alignment: .leading, spacing: 6) {
                privacyItem(L10n.onboardingPermPrivacy1)
                privacyItem(L10n.onboardingPermPrivacy2)
                privacyItem(L10n.onboardingPermPrivacy3)
            }

            // 시스템 설정 열기 버튼
            Button(L10n.openSystemSettings) {
                UserDefaults.standard.synchronize()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // 재시작 안내
            Text(L10n.onboardingPermRestart)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 32)
    }

    private func privacyItem(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Step 2: Shortcut

    private var shortcutStep: some View {
        VStack(spacing: 20) {
            Text(L10n.onboardingShortcutTitle)
                .font(.title2)
                .fontWeight(.bold)

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

    // MARK: - Step 3: Language Pack

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
                VStack(spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.downloading)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let start = downloadStartTime {
                                Text(DateFormatting.elapsedText(from: start))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Text(L10n.downloadingHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            } else if status == .installed || downloadCompleted {
                Label(L10n.onboardingLangInstalled, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if status == .available {
                Label(L10n.onboardingLangNotInstalled, systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)
                    .font(.callout)
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
                // Step 1, 2: "다음" 버튼만
                Button(L10n.onboardingNext) {
                    currentStep += 1
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                // Step 3 (마지막): 언어팩 상태에 따라 분기
                lastStepButtons
            }
        }
    }

    /// Step 3(언어팩) 마지막 스텝의 버튼. 언어팩 설치 상태에 따라 분기한다.
    private var lastStepButtons: some View {
        Group {
            let status = packManager.languageStatuses[selectedTargetCode]
            if isDownloading {
                // 다운로드 중: 버튼 비활성
                Button(L10n.onboardingDone) {
                    finishOnboarding()
                }
                .controlSize(.large)
                .disabled(true)
            } else if status == .installed || downloadCompleted {
                // 설치됨: "시작하기" 단일 버튼
                Button(L10n.onboardingDone) {
                    finishOnboarding()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                // 미설치: "나중에 다운로드" + "다운로드"
                Button(L10n.onboardingDownloadLater) {
                    finishOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.large)

                Button(L10n.download) {
                    downloadLanguagePack()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions


    private func downloadLanguagePack() {
        isDownloading = true
        downloadStartTime = Date()
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
