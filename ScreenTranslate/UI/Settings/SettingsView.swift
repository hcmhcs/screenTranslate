import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var packManager = LanguagePackManager()
    @State private var showDownloadAlert = false
    @State private var pendingDownloadCode: String?

    var body: some View {
        Form {
            Section("번역") {
                Picker("원문 언어", selection: $settings.sourceLanguageCode) {
                    Text("자동 감지").tag("auto")
                    Divider()
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Label {
                            Text(lang.name)
                        } icon: {
                            sourceStatusIcon(for: lang.code)
                        }
                        .tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.sourceLanguageCode) { _, newValue in
                    if newValue != "auto" {
                        let status = packManager.sourceStatuses[newValue]
                        if status == .available {
                            pendingDownloadCode = newValue
                            showDownloadAlert = true
                        }
                    }
                    Task {
                        await packManager.refreshStatuses(sourceCode: newValue)
                    }
                }

                Picker("번역 결과 언어", selection: $settings.targetLanguageCode) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Label {
                            Text(lang.name)
                        } icon: {
                            statusIcon(for: lang.code)
                        }
                        .tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.targetLanguageCode) { _, newValue in
                    let status = packManager.statuses[newValue]
                    if status == .available {
                        pendingDownloadCode = newValue
                        showDownloadAlert = true
                    }
                    Task {
                        await packManager.refreshSourceStatuses(targetCode: newValue)
                    }
                }

                Picker("OCR 엔진", selection: $settings.ocrProviderName) {
                    Text("Apple Vision").tag("Apple Vision")
                }
                .pickerStyle(.menu)
                .disabled(true)

                Picker("번역 엔진", selection: $settings.translationProviderName) {
                    Text("Apple Translation (로컬)").tag("Apple Translation")
                }
                .pickerStyle(.menu)
                .disabled(true)
            }

            Section("단축키") {
                KeyboardShortcuts.Recorder("번역 단축키", name: .translate)
            }
        }
        .formStyle(.grouped)
        .frame(
            minWidth: 450, idealWidth: 500, maxWidth: 600,
            minHeight: 320, idealHeight: 380, maxHeight: 500
        )
        .task {
            await packManager.refreshStatuses(sourceCode: settings.sourceLanguageCode)
            await packManager.refreshSourceStatuses(targetCode: settings.targetLanguageCode)
        }
        .alert("언어팩 미설치", isPresented: $showDownloadAlert) {
            Button("확인") {}
                .keyboardShortcut(.defaultAction)
        } message: {
            if let code = pendingDownloadCode,
               let name = AppSettings.supportedLanguages.first(where: { $0.code == code })?.name {
                Text("\(name) 언어팩이 아직 설치되지 않았습니다.\n해당 언어로 처음 번역할 때 시스템에서 자동으로 다운로드됩니다.")
            }
        }
    }

    // MARK: - 상태 아이콘

    @ViewBuilder
    private func statusIcon(for code: String) -> some View {
        switch packManager.statuses[code] {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.orange)
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .unsupported:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sourceStatusIcon(for code: String) -> some View {
        switch packManager.sourceStatuses[code] {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.orange)
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .unsupported:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}
