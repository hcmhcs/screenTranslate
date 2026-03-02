# Phase 5: 권한 처리 및 마무리

> [← Phase 4](./phase-4-ui.md) | [Overview](./00-overview.md)

---

## Task 10: 권한 처리 및 첫 실행 안내

**Files:**
- Create: `ScreenTranslate/App/PermissionGuard.swift`

**Step 1: PermissionGuard 작성**

`ScreenTranslate/App/PermissionGuard.swift`:

```swift
import AppKit
import SwiftUI

/// Screen Recording 권한 안내를 floating 팝업으로 표시한다.
/// 모달 NSAlert 대신 TranslationPopup과 동일한 비모달 팝업 패턴을 사용하여
/// 사용자가 기대하는 가벼운 인터랙션 흐름을 유지한다.
@MainActor
final class PermissionGuard {
    private static var permissionWindow: NSPanel?

    static func requestScreenRecordingPermission() async {
        // 이미 표시 중이면 무시
        guard permissionWindow == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false

        let permissionView = PermissionRequestView(
            onOpenSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            },
            onClose: {
                permissionWindow?.close()
                permissionWindow = nil
            }
        )

        panel.contentView = NSHostingView(rootView: permissionView)

        // 화면 중앙에 표시
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let popupWidth: CGFloat = 360
        let popupHeight: CGFloat = 180
        let origin = CGPoint(
            x: screen.frame.midX - popupWidth / 2,
            y: screen.frame.midY - popupHeight / 2
        )
        panel.setFrameOrigin(origin)
        panel.setContentSize(NSSize(width: popupWidth, height: popupHeight))
        panel.makeKeyAndOrderFront(nil)
        permissionWindow = panel
    }
}

/// 권한 요청 팝업 뷰.
struct PermissionRequestView: View {
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("화면 접근 권한이 필요합니다")
                .font(.headline)

            Text("시스템 설정 → 개인 정보 보호 및 보안 → 화면 기록에서 ScreenTranslate를 허용해주세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("시스템 설정 열기") { onOpenSettings() }
                    .buttonStyle(.borderedProminent)

                Button("닫기") { onClose() }
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
```

> **변경점**: (1) 권한 요청을 앱 첫 실행이 아닌 **첫 번역 시도 시**로 이동 (AppOrchestrator에서 호출). (2) 모달 `NSAlert` 대신 `TranslationPopup`과 동일한 floating `NSPanel` 팝업을 사용하여 비모달 UX를 유지한다.

**Step 2: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```

**Step 3: 최종 테스트**

```
Xcode → Product → Test (Cmd+U)
```

Expected: 모든 단위 테스트 PASS

```
Xcode → Product → Run (Cmd+R)
```

전체 시나리오 수동 테스트:
- [ ] 첫 번역 시도 시 Screen Recording 권한 미승인이면 안내 팝업
- [ ] 권한 승인 후 `Ctrl+Shift+T`로 오버레이 실행
- [ ] 영어 텍스트 영역 드래그 → 로딩("인식 중...") → 로딩("번역 중...") → 한국어 번역 결과
- [ ] OCR 신뢰도 낮은 영역 → 경고 아이콘 표시
- [ ] 빈 영역 드래그 → "텍스트를 찾을 수 없습니다" 에러
- [ ] 복사 버튼으로 클립보드 복사 + "복사됨" 피드백
- [ ] 설정에서 타겟 언어를 영어로 변경 후 한국어 텍스트 번역
- [ ] 단축키 변경 후 새 단축키로 동작 확인
- [ ] 팝업 ESC로 닫기
- [ ] 오버레이 ESC로 취소

**Step 4: 최종 Commit**

```bash
git add ScreenTranslate/App/PermissionGuard.swift
git commit -m "feat: add PermissionGuard with lazy screen recording permission request"
git tag v1.0.0
```
