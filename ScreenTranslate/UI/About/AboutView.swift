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
        }
        .frame(width: 300, height: 220)
    }
}
