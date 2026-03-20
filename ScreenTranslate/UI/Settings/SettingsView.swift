import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import Translation
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var packManager = LanguagePackManager()
    @State private var fontManager = FontManager.shared
    @State private var showDownloadAlert = false
    @State private var pendingDownloadCode: String?
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var isDownloading = false
    @State private var downloadStartTime: Date?
    @State private var showRemoveFontAlert = false
    @State private var fontToRemove: String?
    @State private var downloadingFontIDs: Set<String> = []
    @State private var showFontError = false
    @State private var fontErrorMessage = ""
    @State private var previousFontName = "system"
    @State private var isDownloadingFont = false
    @State private var showFontDownloadConfirm = false
    @State private var pendingCatalogFont: FontManager.CatalogFont?

    // API Key 입력 상태
    @State private var azureRegionInput = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L10n.generalTab, systemImage: "gearshape") }
            advancedTab
                .tabItem { Label(L10n.advancedTab, systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await packManager.refreshAllStatuses()
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
        .alert(L10n.removeFont, isPresented: $showRemoveFontAlert) {
            Button(L10n.delete, role: .destructive) {
                if let id = fontToRemove {
                    fontManager.removeFont(id: id)
                    if settings.popupFontName == id {
                        settings.popupFontName = "system"
                    }
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            if let id = fontToRemove,
               let font = fontManager.installedFonts.first(where: { $0.id == id }) {
                Text(L10n.removeFontConfirmation(name: font.displayName))
            }
        }
        .alert(fontErrorMessage, isPresented: $showFontError) {
            Button(L10n.confirm) {}
        }
        .alert(L10n.fontDownloadConfirmTitle, isPresented: $showFontDownloadConfirm) {
            Button(L10n.download) {
                guard let catalogFont = pendingCatalogFont else { return }
                startFontDownload(catalogFont)
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.cancel, role: .cancel) {
                // 이전 폰트로 롤백
                settings.popupFontName = previousFontName
                pendingCatalogFont = nil
            }
        } message: {
            if let font = pendingCatalogFont {
                Text(L10n.fontDownloadConfirmMessage(name: font.name, size: formatBytes(font.sizeBytes)))
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - 일반 탭

    private var generalTab: some View {
        Form {
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
            }

            Section(L10n.shortcutSection) {
                KeyboardShortcuts.Recorder(L10n.translationShortcut, name: .translate)
                    .help(L10n.shortcutHelp)

                // 드래그 번역: 커스텀 단축키 또는 ⌘C+C 택 1
                HStack {
                    Text(L10n.dragTranslateShortcut)
                    Spacer()

                    // 커스텀 단축키 옵션
                    KeyboardShortcuts.Recorder("", name: .dragTranslate)
                        .opacity(settings.dragTranslateMode == "custom" ? 1.0 : 0.4)
                        .disabled(settings.dragTranslateMode != "custom")
                        .overlay {
                            // .disabled가 onTapGesture도 차단하므로,
                            // 비활성 상태에서 투명 overlay로 탭을 캐치하여 모드 전환
                            if settings.dragTranslateMode != "custom" {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        settings.dragTranslateMode = "custom"
                                        AppOrchestrator.shared.updateDragTranslateMode()
                                    }
                            }
                        }

                    // ⌘C+C 옵션
                    Text(L10n.doubleCopyShortcut)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.dragTranslateMode == "doubleCopy"
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(settings.dragTranslateMode == "doubleCopy"
                                    ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                        .foregroundStyle(settings.dragTranslateMode == "doubleCopy"
                            ? .primary : .secondary)
                        .onTapGesture {
                            settings.dragTranslateMode = "doubleCopy"
                            AppOrchestrator.shared.updateDragTranslateMode()
                        }
                }
                .help(L10n.doubleCopyHelp)

                KeyboardShortcuts.Recorder(L10n.quickTranslateShortcut, name: .quickTranslate)
                    .help(L10n.quickTranslateShortcutHelp)
            }

            Section(L10n.appSection) {
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

                Button(L10n.checkForUpdates) {
                    AppOrchestrator.shared.checkForUpdates()
                }
                .disabled(!AppOrchestrator.shared.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 고급 탭

    private var advancedTab: some View {
        Form {
            Section(L10n.engineSection) {
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

                // DeepL API 키
                if settings.translationProviderName == "DeepL" {
                    APIKeySection(
                        hasKey: settings.hasDeepLKey,
                        savedLabel: nil,
                        onSave: { key in
                            try? settings.saveDeepLKey(key)
                            AppOrchestrator.shared.updateTranslationProvider()
                        },
                        onDelete: {
                            settings.deleteDeepLKey()
                            settings.translationProviderName = "Apple Translation"
                            AppOrchestrator.shared.updateTranslationProvider()
                        }
                    )
                }

                // Google Cloud API 키
                if settings.translationProviderName == "Google Cloud" {
                    APIKeySection(
                        hasKey: settings.hasGoogleKey,
                        savedLabel: nil,
                        onSave: { key in
                            try? settings.saveGoogleKey(key)
                            AppOrchestrator.shared.updateTranslationProvider()
                        },
                        onDelete: {
                            settings.deleteGoogleKey()
                            settings.translationProviderName = "Apple Translation"
                            AppOrchestrator.shared.updateTranslationProvider()
                        }
                    )
                }

                // Microsoft Azure API 키 + 리전
                if settings.translationProviderName == "Microsoft Azure" {
                    APIKeySection(
                        hasKey: settings.hasAzureKey,
                        savedLabel: settings.azureRegion.map { "\(L10n.apiKeySaved) (\($0))" },
                        onSave: { key in
                            try? settings.saveAzureKey(key)
                            let region = azureRegionInput.trimmingCharacters(in: .whitespaces)
                            settings.azureRegion = region.isEmpty ? nil : region
                            azureRegionInput = ""
                            AppOrchestrator.shared.updateTranslationProvider()
                        },
                        onDelete: {
                            settings.deleteAzureKey()
                            settings.azureRegion = nil
                            azureRegionInput = ""
                            settings.translationProviderName = "Apple Translation"
                            AppOrchestrator.shared.updateTranslationProvider()
                        },
                        regionInput: $azureRegionInput
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: settings.translationProviderName)

            Section(L10n.popupSection) {
                Stepper(value: $settings.popupFontSize, in: 11...20, step: 1) {
                    HStack {
                        Text(L10n.popupFontSize)
                        Spacer()
                        Text("\(Int(settings.popupFontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                }
                .help(L10n.popupFontSizeDesc)

                // 폰트 선택 — 통합 Picker (시스템 + 번들 + 카탈로그 + 임포트)
                HStack {
                    Text(L10n.popupFont)
                    Spacer()

                    if isDownloadingFont {
                        if fontManager.downloadProgress < 0 {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        } else {
                            ProgressView(value: fontManager.downloadProgress)
                                .frame(width: 60)
                                .padding(.trailing, 4)
                        }
                    }

                    Picker(L10n.popupFont, selection: $settings.popupFontName) {
                        Text(L10n.systemDefault).tag("system")
                        Divider()

                        // 번들 폰트
                        ForEach(fontManager.installedFonts.filter { $0.source == .bundled }, id: \.id) { font in
                            Text(font.displayName).tag(font.id)
                        }

                        // 카탈로그 폰트 (설치/미설치 통합)
                        if !fontManager.catalogFonts.isEmpty {
                            Divider()
                            ForEach(fontManager.catalogFonts) { catalogFont in
                                if fontManager.isInstalled(catalogFont) {
                                    Label(catalogFont.name, systemImage: "checkmark.circle.fill")
                                        .tag(catalogFont.id)
                                } else {
                                    Label {
                                        Text("\(catalogFont.name) (\(formatBytes(catalogFont.sizeBytes)))")
                                    } icon: {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                    .tag(catalogFont.id)
                                }
                            }
                        }

                        // 사용자 임포트 폰트
                        let importedFonts = fontManager.installedFonts.filter { $0.source == .imported }
                        if !importedFonts.isEmpty {
                            Divider()
                            ForEach(importedFonts, id: \.id) { font in
                                Text(font.displayName).tag(font.id)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                    .disabled(isDownloadingFont)
                    .id(fontManager.installedFonts.count)
                    .onChange(of: settings.popupFontName) { oldValue, newValue in
                        handleFontSelection(oldValue: oldValue, newValue: newValue)
                    }

                    Button(L10n.addFont) {
                        importFontFromFile()
                    }
                    .controlSize(.small)
                    .help(L10n.fontSelectMessage)
                }
                .help(L10n.popupFontDesc)

                // 미리보기 (컴팩트)
                Text(L10n.fontPreviewSample(for: settings.targetLanguageCode))
                    .font(fontManager.swiftUIFont(size: settings.popupFontSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(L10n.fontPreview)

                // 삭제 버튼 (임포트/다운로드 폰트 선택 시)
                if settings.popupFontName != "system",
                   let selected = fontManager.installedFonts.first(where: { $0.id == settings.popupFontName }),
                   selected.source != .bundled {
                    Button(role: .destructive) {
                        fontToRemove = selected.id
                        showRemoveFontAlert = true
                    } label: {
                        Label(L10n.removeFont, systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help(L10n.removeFont)
                }

                Toggle(isOn: $settings.matchPopupWidthToSelection) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.matchPopupWidth)
                        Text(L10n.matchPopupWidthDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .help(L10n.matchPopupWidthHelp)
            }

            Section(L10n.otherSection) {
                Toggle(isOn: $settings.autoCopyToClipboard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.autoCopyToClipboard)
                        Text(L10n.autoCopyToClipboardDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
    }

    // MARK: - Helpers

    private func handleFontSelection(oldValue: String, newValue: String) {
        // 다운로드 중이면 무시 (Picker .id() 리빌드에 의한 재트리거 방지)
        guard !isDownloadingFont else { return }

        // 이미 설치된 폰트이면 바로 적용
        if newValue == "system" || fontManager.installedFonts.contains(where: { $0.id == newValue }) {
            return
        }

        // 미설치 카탈로그 폰트 → 확인 팝업
        guard let catalogFont = fontManager.catalogFonts.first(where: { $0.id == newValue }) else {
            return
        }

        previousFontName = oldValue
        pendingCatalogFont = catalogFont
        showFontDownloadConfirm = true
    }

    private func startFontDownload(_ catalogFont: FontManager.CatalogFont) {
        isDownloadingFont = true
        downloadingFontIDs.insert(catalogFont.id)

        Task {
            do {
                try await fontManager.downloadFont(catalogFont)
            } catch {
                settings.popupFontName = previousFontName
                fontErrorMessage = L10n.fontDownloadFailed
                showFontError = true
            }
            isDownloadingFont = false
            downloadingFontIDs.remove(catalogFont.id)
            pendingCatalogFont = nil
        }
    }

    private func importFontFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.fontSelectMessage

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let countBefore = fontManager.installedFonts.count
        do {
            try fontManager.importFont(from: url)
            // Select the newly added font
            if fontManager.installedFonts.count > countBefore,
               let newFont = fontManager.installedFonts.last {
                settings.popupFontName = newFont.id
            }
        } catch {
            fontErrorMessage = L10n.fontImportFailed
            showFontError = true
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.1fMB", mb)
    }


    private func engineDescription(for name: String) -> String {
        switch name {
        case "DeepL": return L10n.engineDescDeepL
        case "Google Cloud": return L10n.engineDescGoogle
        case "Microsoft Azure": return L10n.engineDescAzure
        default: return L10n.engineDescApple
        }
    }

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
