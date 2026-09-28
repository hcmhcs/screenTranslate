import AppKit

/// 앱이 어떻게 실행됐는지
nonisolated enum LaunchKind: Equatable, Sendable {
    /// 로그인 항목으로 자동 실행
    case loginItem
    /// Finder·Spotlight·업데이트 후 재시작 등 그 밖의 실행
    case regular
}

/// 메뉴바 아이콘 숨김(이슈 #3)의 판정 — UI와 분리해 단위 테스트한다.
nonisolated enum MenuBarIconPolicy {

    /// 실행 Apple 이벤트로 로그인 자동 실행인지 판정한다.
    /// - 이벤트는 applicationDidFinishLaunching 안에서만 읽힌다 (willFinishLaunching에서는 nil, 2026-09-29 실측).
    /// - SMAppService.mainApp 로그인 실행에서 이 표시가 오는지는 실측하지 못했다.
    ///   오지 않으면 .regular로 분류되어 로그인 때 안내가 한 번 뜬다 — 직접 실행했는데 아무것도 안 뜨는 쪽보다 안전하다.
    static func launchKind(from event: NSAppleEventDescriptor?) -> LaunchKind {
        guard let event,
              event.eventClass == kCoreEventClass,
              event.eventID == kAEOpenApplication,
              event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        else { return .regular }
        return .loginItem
    }

    /// 새로 실행됐을 때 "실행 중" 안내를 띄울지.
    /// 아이콘이 보이면 필요 없고, 로그인 자동 실행마다 뜨면 방해가 된다.
    static func shouldShowBackgroundNotice(isMenuBarIconVisible: Bool, launchKind: LaunchKind) -> Bool {
        !isMenuBarIconVisible && launchKind == .regular
    }

    /// 아이콘 없이는 실행할 길이 없어지는 기능 — 숨기기 확인창에서 경고한다.
    nonisolated enum Feature: Equatable, Sendable {
        case screenTranslate
        case dragTranslate
        case quickTranslate

        var title: String {
            switch self {
            case .screenTranslate: L10n.translate
            case .dragTranslate: L10n.dragTranslate
            case .quickTranslate: L10n.quickTranslate
            }
        }
    }

    /// 단축키가 비어 있는 기능을 메뉴 순서대로 돌려준다.
    /// 드래그 번역은 ⌘C+C 모드("doubleCopy")면 단축키가 필요 없다.
    static func featuresWithoutShortcut(
        hasScreenTranslateShortcut: Bool,
        hasDragTranslateShortcut: Bool,
        dragTranslateMode: String,
        hasQuickTranslateShortcut: Bool
    ) -> [Feature] {
        var features: [Feature] = []
        if !hasScreenTranslateShortcut { features.append(.screenTranslate) }
        if dragTranslateMode == "custom", !hasDragTranslateShortcut { features.append(.dragTranslate) }
        if !hasQuickTranslateShortcut { features.append(.quickTranslate) }
        return features
    }
}
