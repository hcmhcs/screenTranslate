import AppKit
import Testing
@testable import ScreenTranslate

/// 메뉴바 아이콘 숨김(이슈 #3)의 판정 로직.
@Suite struct MenuBarIconPolicyTests {

    private func makeEvent(_ eventID: AEEventID, loginItem: Bool) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: kCoreEventClass,
            eventID: eventID,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if loginItem {
            event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        }
        return event
    }

    // MARK: - 실행 종류

    @Test("missing launch event counts as a regular launch")
    func nilEventIsRegular() {
        #expect(MenuBarIconPolicy.launchKind(from: nil) == .regular)
    }

    @Test("open-application event without the login flag is a regular launch")
    func plainOpenIsRegular() {
        #expect(MenuBarIconPolicy.launchKind(from: makeEvent(kAEOpenApplication, loginItem: false)) == .regular)
    }

    @Test("open-application event with the login flag is a login-item launch")
    func loginFlagIsLoginItem() {
        #expect(MenuBarIconPolicy.launchKind(from: makeEvent(kAEOpenApplication, loginItem: true)) == .loginItem)
    }

    @Test("login flag on a reopen event is ignored")
    func loginFlagOnReopenIsIgnored() {
        #expect(MenuBarIconPolicy.launchKind(from: makeEvent(kAEReopenApplication, loginItem: true)) == .regular)
    }

    // MARK: - 실행 안내

    @Test("background notice only when the icon is hidden and the user launched the app", arguments: [
        (true, LaunchKind.regular, false),
        (true, LaunchKind.loginItem, false),
        (false, LaunchKind.regular, true),
        (false, LaunchKind.loginItem, false),
    ])
    func backgroundNotice(isVisible: Bool, launchKind: LaunchKind, expected: Bool) {
        #expect(MenuBarIconPolicy.shouldShowBackgroundNotice(
            isMenuBarIconVisible: isVisible, launchKind: launchKind) == expected)
    }

    // MARK: - 단축키 없는 기능

    @Test("nothing is unreachable when every shortcut is set")
    func allShortcutsSet() {
        #expect(MenuBarIconPolicy.featuresWithoutShortcut(
            hasScreenTranslateShortcut: true, hasDragTranslateShortcut: true,
            dragTranslateMode: "custom", hasQuickTranslateShortcut: true).isEmpty)
    }

    @Test("features without a shortcut are listed in menu order")
    func missingShortcutsInMenuOrder() {
        #expect(MenuBarIconPolicy.featuresWithoutShortcut(
            hasScreenTranslateShortcut: false, hasDragTranslateShortcut: false,
            dragTranslateMode: "custom", hasQuickTranslateShortcut: false)
            == [.screenTranslate, .dragTranslate, .quickTranslate])
    }

    @Test("drag translate in Cmd+C+C mode needs no shortcut")
    func doubleCopyModeNeedsNoShortcut() {
        #expect(MenuBarIconPolicy.featuresWithoutShortcut(
            hasScreenTranslateShortcut: true, hasDragTranslateShortcut: false,
            dragTranslateMode: "doubleCopy", hasQuickTranslateShortcut: true).isEmpty)
    }
}
