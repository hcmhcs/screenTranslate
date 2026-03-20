import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            Text("ScreenTranslate")
                .font(.title2.bold())

            VStack(spacing: 4) {
                Text("Version \(AppVersion.fullVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Copyright \u{00A9} 2026 hanchangmin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(L10n.checkForUpdates) {
                AppOrchestrator.shared.checkForUpdates()
            }
            .disabled(!AppOrchestrator.shared.canCheckForUpdates)

            Divider()

            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Link(L10n.aboutWebsite, destination: URL(string: "https://screentranslate.filient.ai/?utm_source=app&utm_medium=about&utm_campaign=screentranslate")!)
                    Link("GitHub", destination: URL(string: "https://github.com/hcmhcs/screenTranslate")!)
                    Link(L10n.aboutPrivacyPolicy, destination: URL(string: "https://screentranslate.filient.ai/privacy?utm_source=app&utm_medium=about&utm_campaign=screentranslate")!)
                }
                Link("teams@filient.ai", destination: URL(string: "mailto:teams@filient.ai")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 16)
    }
}
