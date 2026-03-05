import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import Translation

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var packManager = LanguagePackManager()
    @State private var showDownloadAlert = false
    @State private var pendingDownloadCode: String?
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var isDownloading = false
    @State private var downloadStartTime: Date?

    // API Key 입력 상태
    @State private var deepLKeyInput = ""
    @State private var googleKeyInput = ""
    @State private var azureKeyInput = ""
    @State private var azureRegionInput = ""

    var body: some View {
        Form {
            Section(L10n.generalSection) {
                Picker(L10n.appLanguageLabel, selection: $settings.appLanguage) {
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                }
                .pickerStyle(.menu)
                .help(L10n.appLanguageHelp)

                Toggle(L10n.launchAtLogin, isOn: $launchAtLogin)
                    .help(L10n.launchAtLoginHelp)
                    .onChange(of: launchAtLogin) { _, newValue in
                        Task {
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try await SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            }
                        }
                    }

                Toggle(isOn: $settings.autoCopyToClipboard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.autoCopyToClipboard)
                        Text(L10n.autoCopyToClipboardDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.translationSection) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text(L10n.sourceLanguageLabel)
                            .foregroundStyle(.secondary)
                        Picker(L10n.sourceLanguageLabel, selection: $settings.sourceLanguageCode) {
                            Text(L10n.autoDetect).tag("auto")
                            Divider()
                            ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                                Label {
                                    Text(lang.name)
                                } icon: {
                                    languageStatusIcon(for: lang.code)
                                }
                                .tag(lang.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: settings.sourceLanguageCode) { _, newValue in
                            if newValue != "auto" {
                                let status = packManager.languageStatuses[newValue]
                                if status == .available {
                                    pendingDownloadCode = newValue
                                    showDownloadAlert = true
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(L10n.sourceLanguageHelp)

                    Button {
                        let oldSource = settings.sourceLanguageCode
                        let oldTarget = settings.targetLanguageCode
                        settings.sourceLanguageCode = oldTarget
                        settings.targetLanguageCode = oldSource
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .disabled(settings.sourceLanguageCode == "auto")
                    .help(L10n.swapLanguages)

                    HStack(spacing: 4) {
                        Text(L10n.targetLanguageLabel)
                            .foregroundStyle(.secondary)
                        Picker(L10n.targetLanguageLabel, selection: $settings.targetLanguageCode) {
                            ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                                Label {
                                    Text(lang.name)
                                } icon: {
                                    languageStatusIcon(for: lang.code)
                                }
                                .tag(lang.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: settings.targetLanguageCode) { _, newValue in
                            let status = packManager.languageStatuses[newValue]
                            if status == .available {
                                pendingDownloadCode = newValue
                                showDownloadAlert = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(L10n.targetLanguageHelp)
                }

                Picker(L10n.ocrEngine, selection: $settings.ocrProviderName) {
                    Text(L10n.ocrEngineName).tag("Apple Vision")
                }
                .pickerStyle(.menu)
                .disabled(true)
                .help(L10n.ocrEngineHelp)

                Picker(L10n.translationEngine, selection: $settings.translationProviderName) {
                    Label {
                        Text(L10n.translationEngineName)
                    } icon: {
                        engineStatusIcon(ready: true)
                    }
                    .tag("Apple Translation")

                    Label {
                        Text("DeepL")
                    } icon: {
                        engineStatusIcon(ready: settings.hasDeepLKey)
                    }
                    .tag("DeepL")

                    Label {
                        Text("Google Cloud")
                    } icon: {
                        engineStatusIcon(ready: settings.hasGoogleKey)
                    }
                    .tag("Google Cloud")

                    Label {
                        Text("Microsoft Azure")
                    } icon: {
                        engineStatusIcon(ready: settings.hasAzureKey)
                    }
                    .tag("Microsoft Azure")
                }
                .pickerStyle(.menu)
                .onChange(of: settings.translationProviderName) { _, _ in
                    AppOrchestrator.shared.updateTranslationProvider()
                }

                Text(engineDescription(for: settings.translationProviderName))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // DeepL 선택 시 API 키 입력 인라인 표시
                if settings.translationProviderName == "DeepL" {
                    if settings.hasDeepLKey {
                        HStack {
                            Label(L10n.apiKeySaved, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                            Spacer()
                            Button(L10n.clear) {
                                settings.deleteDeepLKey()
                                deepLKeyInput = ""
                                settings.translationProviderName = "Apple Translation"
                                AppOrchestrator.shared.updateTranslationProvider()
                            }
                            .controlSize(.small)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                SecureField(L10n.enterApiKey, text: $deepLKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                Button(L10n.confirm) {
                                    guard !deepLKeyInput.isEmpty else { return }
                                    try? settings.saveDeepLKey(deepLKeyInput)
                                    deepLKeyInput = ""
                                    AppOrchestrator.shared.updateTranslationProvider()
                                }
                                .controlSize(.small)
                                .disabled(deepLKeyInput.isEmpty)
                            }
                            Button(L10n.engineGuide) {
                                if let url = URL(string: "https://screentranslate.filient.ai/engines?utm_source=app&utm_medium=settings&utm_campaign=screentranslate") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // Google Cloud 선택 시 API 키 입력 인라인 표시
                if settings.translationProviderName == "Google Cloud" {
                    if settings.hasGoogleKey {
                        HStack {
                            Label(L10n.apiKeySaved, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                            Spacer()
                            Button(L10n.clear) {
                                settings.deleteGoogleKey()
                                googleKeyInput = ""
                                settings.translationProviderName = "Apple Translation"
                                AppOrchestrator.shared.updateTranslationProvider()
                            }
                            .controlSize(.small)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                SecureField(L10n.enterApiKey, text: $googleKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                Button(L10n.confirm) {
                                    guard !googleKeyInput.isEmpty else { return }
                                    try? settings.saveGoogleKey(googleKeyInput)
                                    googleKeyInput = ""
                                    AppOrchestrator.shared.updateTranslationProvider()
                                }
                                .controlSize(.small)
                                .disabled(googleKeyInput.isEmpty)
                            }
                            Button(L10n.engineGuide) {
                                if let url = URL(string: "https://screentranslate.filient.ai/engines?utm_source=app&utm_medium=settings&utm_campaign=screentranslate") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // Microsoft Azure 선택 시 API 키 + 리전 입력 인라인 표시
                if settings.translationProviderName == "Microsoft Azure" {
                    if settings.hasAzureKey {
                        HStack {
                            Label(
                                settings.azureRegion.map { "\(L10n.apiKeySaved) (\($0))" } ?? L10n.apiKeySaved,
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)
                            .font(.callout)
                            Spacer()
                            Button(L10n.clear) {
                                settings.deleteAzureKey()
                                settings.azureRegion = nil
                                azureKeyInput = ""
                                azureRegionInput = ""
                                settings.translationProviderName = "Apple Translation"
                                AppOrchestrator.shared.updateTranslationProvider()
                            }
                            .controlSize(.small)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                SecureField(L10n.enterApiKey, text: $azureKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                TextField(L10n.regionPlaceholder, text: $azureRegionInput)
                                    .textFieldStyle(.roundedBorder)
                                Button(L10n.confirm) {
                                    guard !azureKeyInput.isEmpty else { return }
                                    try? settings.saveAzureKey(azureKeyInput)
                                    let region = azureRegionInput.trimmingCharacters(in: .whitespaces)
                                    settings.azureRegion = region.isEmpty ? nil : region
                                    azureKeyInput = ""
                                    azureRegionInput = ""
                                    AppOrchestrator.shared.updateTranslationProvider()
                                }
                                .controlSize(.small)
                                .disabled(azureKeyInput.isEmpty)
                            }
                            Button(L10n.engineGuide) {
                                if let url = URL(string: "https://screentranslate.filient.ai/engines?utm_source=app&utm_medium=settings&utm_campaign=screentranslate") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: settings.translationProviderName)

            Section(L10n.shortcutSection) {
                KeyboardShortcuts.Recorder(L10n.translationShortcut, name: .translate)
                    .help(L10n.shortcutHelp)
                KeyboardShortcuts.Recorder(L10n.dragTranslateShortcut, name: .dragTranslate)
                    .help(L10n.dragTranslateShortcutHelp)
            }

            Section(L10n.advancedSection) {
                Toggle(isOn: $settings.ocrTextPreprocessing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.ocrTextPreprocessing)
                        Text(L10n.ocrTextPreprocessingDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await packManager.refreshAllStatuses()
            // 외부에서 Keychain이 초기화된 경우 선택값 유효성 검증
            if settings.translationProviderName == "DeepL" && !settings.hasDeepLKey {
                settings.translationProviderName = "Apple Translation"
                AppOrchestrator.shared.updateTranslationProvider()
            }
            if settings.translationProviderName == "Google Cloud" && !settings.hasGoogleKey {
                settings.translationProviderName = "Apple Translation"
                AppOrchestrator.shared.updateTranslationProvider()
            }
            if settings.translationProviderName == "Microsoft Azure" && !settings.hasAzureKey {
                settings.translationProviderName = "Apple Translation"
                AppOrchestrator.shared.updateTranslationProvider()
            }
        }
        .alert(L10n.languagePackNotInstalled, isPresented: $showDownloadAlert) {
            Button(L10n.download) {
                isDownloading = true
                downloadStartTime = Date()
                Task {
                    // 미설치 언어를 이미 설치된 언어와 쌍으로 구성하여 다운로드.
                    // 설치된 쪽은 시스템이 스킵하므로 미설치 언어만 실제 다운로드된다.
                    let downloadCode = pendingDownloadCode ?? settings.targetLanguageCode
                    let installedRef = packManager.findInstalledLanguage(excluding: downloadCode) ?? "en"

                    let source: Locale.Language
                    let target: Locale.Language
                    if downloadCode == settings.sourceLanguageCode {
                        source = Locale.Language(identifier: downloadCode)
                        target = Locale.Language(identifier: installedRef)
                    } else {
                        source = Locale.Language(identifier: installedRef)
                        target = Locale.Language(identifier: downloadCode)
                    }

                    do {
                        _ = try await TranslationBridge.shared.translate(
                            text: " ", from: source, to: target
                        )
                    } catch {
                        // 다운로드 프롬프트 표시 후 실패해도 상태 갱신
                    }
                    await packManager.refreshAllStatuses()
                    isDownloading = false
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.later, role: .cancel) {}
        } message: {
            if let code = pendingDownloadCode,
               let name = AppSettings.supportedLanguages.first(where: { $0.code == code })?.name {
                Text(L10n.languagePackMessage(name: name))
            }
        }
        .overlay {
            if isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 8) {
                            Text(L10n.downloading)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let start = downloadStartTime {
                                Text(elapsedText(from: start))
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func elapsedText(from start: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(start))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - 엔진 설명

    private func engineDescription(for name: String) -> String {
        switch name {
        case "DeepL": return L10n.engineDescDeepL
        case "Google Cloud": return L10n.engineDescGoogle
        case "Microsoft Azure": return L10n.engineDescAzure
        default: return L10n.engineDescApple
        }
    }

    // MARK: - 엔진 상태 아이콘

    @ViewBuilder
    private func engineStatusIcon(ready: Bool) -> some View {
        if ready {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "key")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - 상태 아이콘 (개별 언어 기준)

    @ViewBuilder
    private func languageStatusIcon(for code: String) -> some View {
        switch packManager.languageStatuses[code] {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.orange)
        case .unsupported:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}
