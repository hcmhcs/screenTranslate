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

    // API Key 입력 상태
    @State private var deepLKeyInput = ""
    @State private var googleKeyInput = ""

    var body: some View {
        Form {
            Section(L10n.generalSection) {
                Picker(L10n.appLanguageLabel, selection: $settings.appLanguage) {
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                }
                .pickerStyle(.menu)

                Toggle(L10n.launchAtLogin, isOn: $launchAtLogin)
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
                }

                Picker(L10n.ocrEngine, selection: $settings.ocrProviderName) {
                    Text(L10n.ocrEngineName).tag("Apple Vision")
                }
                .pickerStyle(.menu)
                .disabled(true)

                Picker(L10n.translationEngine, selection: $settings.translationProviderName) {
                    Text(L10n.translationEngineName).tag("Apple Translation")
                    if settings.hasDeepLKey {
                        Text("DeepL").tag("DeepL")
                    }
                    if settings.hasGoogleKey {
                        Text("Google Cloud").tag("Google Cloud")
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.translationProviderName) { _, _ in
                    AppOrchestrator.shared.updateTranslationProvider()
                }
            }

            Section(L10n.apiKeysSection) {
                // DeepL API Key
                HStack {
                    Text("DeepL")
                        .frame(width: 100, alignment: .leading)
                    if settings.hasDeepLKey {
                        Text(L10n.apiKeySaved)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.clear) {
                            settings.deleteDeepLKey()
                            deepLKeyInput = ""
                            if settings.translationProviderName == "DeepL" {
                                settings.translationProviderName = "Apple Translation"
                                AppOrchestrator.shared.updateTranslationProvider()
                            }
                        }
                        .controlSize(.small)
                    } else {
                        SecureField(L10n.enterApiKey, text: $deepLKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button(L10n.confirm) {
                            guard !deepLKeyInput.isEmpty else { return }
                            try? settings.saveDeepLKey(deepLKeyInput)
                            deepLKeyInput = ""
                        }
                        .controlSize(.small)
                        .disabled(deepLKeyInput.isEmpty)
                    }
                }

                // Google Cloud API Key
                HStack {
                    Text("Google Cloud")
                        .frame(width: 100, alignment: .leading)
                    if settings.hasGoogleKey {
                        Text(L10n.apiKeySaved)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.clear) {
                            settings.deleteGoogleKey()
                            googleKeyInput = ""
                            if settings.translationProviderName == "Google Cloud" {
                                settings.translationProviderName = "Apple Translation"
                                AppOrchestrator.shared.updateTranslationProvider()
                            }
                        }
                        .controlSize(.small)
                    } else {
                        SecureField(L10n.enterApiKey, text: $googleKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button(L10n.confirm) {
                            guard !googleKeyInput.isEmpty else { return }
                            try? settings.saveGoogleKey(googleKeyInput)
                            googleKeyInput = ""
                        }
                        .controlSize(.small)
                        .disabled(googleKeyInput.isEmpty)
                    }
                }

                Text(L10n.apiKeyRequired)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.shortcutSection) {
                KeyboardShortcuts.Recorder(L10n.translationShortcut, name: .translate)
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
        }
        .alert(L10n.languagePackNotInstalled, isPresented: $showDownloadAlert) {
            Button(L10n.download) {
                isDownloading = true
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
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.large)
                    Text(L10n.downloading)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
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
