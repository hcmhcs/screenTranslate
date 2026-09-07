import AppKit
import SwiftUI

/// Screen Recording / Accessibility 권한 안내를 floating 팝업으로 표시한다.
/// 모달 NSAlert 대신 TranslationPopup과 동일한 비모달 팝업 패턴을 사용하여
/// 사용자가 기대하는 가벼운 인터랙션 흐름을 유지한다.
enum PermissionGuard {
    /// 표시할 권한 안내의 종류 — 패널 구성(제목·설명·아이콘·설정 페인)을 결정한다.
    private enum Kind {
        case screenRecording
        case accessibility

        /// 시스템 설정의 Privacy 페인 식별자
        var settingsPane: String {
            switch self {
            case .screenRecording: return "Privacy_ScreenCapture"
            case .accessibility: return "Privacy_Accessibility"
            }
        }

        var title: String {
            switch self {
            case .screenRecording: return L10n.permissionRequired
            case .accessibility: return L10n.accessibilityPermissionRequired
            }
        }

        var description: String {
            switch self {
            case .screenRecording: return L10n.permissionDescription
            case .accessibility: return L10n.accessibilityPermissionDescription
            }
        }

        var icon: String {
            switch self {
            case .screenRecording: return "rectangle.dashed.badge.record"
            case .accessibility: return "hand.raised.circle"
            }
        }
    }

    private static var panels: [Kind: NSPanel] = [:]

    static func requestScreenRecordingPermission() {
        show(.screenRecording)
    }

    static func requestAccessibilityPermission() {
        show(.accessibility)
    }

    /// 권한 안내 패널을 화면 중앙에 표시한다. 같은 종류가 이미 표시 중이면 무시한다.
    private static func show(_ kind: Kind) {
        guard panels[kind] == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false  // ARC 환경에서 close() 시 이중 해제 방지
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false

        let permissionView = PermissionRequestView(
            onOpenSettings: {
                let pane = "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsPane)"
                if let url = URL(string: pane) {
                    NSWorkspace.shared.open(url)
                }
            },
            onClose: {
                panels[kind]?.close()
                panels[kind] = nil
            },
            title: kind.title,
            description: kind.description,
            icon: kind.icon
        )

        panel.contentView = NSHostingView(rootView: permissionView)

        // 화면 중앙에 표시
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let popupWidth: CGFloat = 360
        let popupHeight: CGFloat = 180
        let origin = CGPoint(
            x: screen.frame.midX - popupWidth / 2,
            y: screen.frame.midY - popupHeight / 2
        )
        panel.setFrameOrigin(origin)
        panel.setContentSize(NSSize(width: popupWidth, height: popupHeight))
        panel.makeKeyAndOrderFront(nil)
        panels[kind] = panel
    }
}

/// 권한 요청 팝업 뷰.
struct PermissionRequestView: View {
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    var title: String = L10n.permissionRequired
    var description: String = L10n.permissionDescription
    var icon: String = "rectangle.dashed.badge.record"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button(L10n.openSystemSettings) { onOpenSettings() }
                    .buttonStyle(.borderedProminent)

                Button(L10n.close) { onClose() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 12, y: 4)
    }
}
