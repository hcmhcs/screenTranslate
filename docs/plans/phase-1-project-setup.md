# Phase 1: 프로젝트 셋업

> [← Overview](./00-overview.md) | [Phase 2 →](./phase-2-core-providers.md)

---

## Task 1: Xcode 프로젝트 생성 및 초기 설정

**Files:**
- Create: `ScreenTranslate.xcodeproj` (Xcode GUI로 생성)
- Create: `ScreenTranslate/Info.plist`
- Create: `ScreenTranslate/ScreenTranslate.entitlements`
- Create: `ScreenTranslate/App/ScreenTranslateApp.swift`

**Step 1: Xcode에서 새 프로젝트 생성**

```
Xcode → File → New → Project
Template: macOS → App
Product Name: ScreenTranslate
Bundle Identifier: com.yourname.ScreenTranslate
Interface: SwiftUI
Language: Swift
Minimum Deployment: macOS 15.0
☑ Include Tests
```

**Step 2: Info.plist에 필수 키 추가**

`ScreenTranslate/Info.plist`에서 다음 키를 추가:

```xml
<key>LSUIElement</key>
<true/>
<key>NSScreenCaptureUsageDescription</key>
<string>선택한 화면 영역의 텍스트를 인식하고 번역하기 위해 화면 접근 권한이 필요합니다.</string>
```

> `LSUIElement = true` → Dock 아이콘 숨김, 메뉴바 전용 앱으로 동작
> `NSScreenCaptureUsageDescription` → Screen Recording 권한 요청 다이얼로그에 표시되는 사유. 이 키가 없으면 macOS가 권한 요청 UI를 표시하지 않으며, `SCShareableContent` 호출 시 즉시 거부될 수 있다.

**Step 3: Entitlements 파일 설정**

`ScreenTranslate/ScreenTranslate.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

> App Sandbox를 비활성화해야 ScreenCaptureKit 전역 캡처 및 전역 단축키가 동작한다.

**Step 4: KeyboardShortcuts SPM 의존성 추가**

```
Xcode → File → Add Package Dependencies
URL: https://github.com/sindresorhus/KeyboardShortcuts
Version: Up to Next Major Version
```

> 주의: 저자는 sindresorhus (nicklockwood 아님).

**Step 5: 기본 App 진입점 작성**

`ScreenTranslate/App/ScreenTranslateApp.swift`:

```swift
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translate = Self("translate", default: .init(.t, modifiers: [.control, .shift]))
}

@main
struct ScreenTranslateApp: App {
    var body: some Scene {
        MenuBarExtra("ScreenTranslate", systemImage: "text.viewfinder") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Step 6: 임시 MenuBarView 작성 (빌드용)**

`ScreenTranslate/UI/MenuBar/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button("번역하기") { }
        Divider()
        Button("ScreenTranslate 종료") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

**Step 7: 빌드 확인**

```
Xcode → Product → Build (Cmd+B)
```
Expected: Build Succeeded. 메뉴바에 아이콘이 표시된다.

**Step 8: Commit**

```bash
git init
git add .
git commit -m "feat: initial Xcode project setup with MenuBarExtra"
```
