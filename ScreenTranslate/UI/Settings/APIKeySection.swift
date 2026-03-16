import SwiftUI

/// 번역 엔진 API 키 입력/표시 공통 컴포넌트.
struct APIKeySection: View {
    let hasKey: Bool
    let savedLabel: String?  // nil이면 기본 "API 키 저장됨" 표시
    let onSave: (String) -> Void
    let onDelete: () -> Void
    var regionInput: Binding<String>? = nil  // Azure 전용

    @State private var keyInput = ""

    var body: some View {
        if hasKey {
            HStack {
                Label(savedLabel ?? L10n.apiKeySaved, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Spacer()
                Button(L10n.clear) { onDelete() }
                    .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SecureField(L10n.enterApiKey, text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                    if regionInput == nil {
                        confirmButton
                    }
                }
                if let regionInput {
                    HStack {
                        TextField(L10n.regionPlaceholder, text: regionInput)
                            .textFieldStyle(.roundedBorder)
                        confirmButton
                    }
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

    private var confirmButton: some View {
        Button(L10n.confirm) {
            guard !keyInput.isEmpty else { return }
            onSave(keyInput)
            keyInput = ""
        }
        .controlSize(.small)
        .disabled(keyInput.isEmpty)
    }
}
