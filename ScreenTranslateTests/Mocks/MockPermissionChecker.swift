@testable import ScreenTranslate

final class MockPermissionChecker: PermissionChecking {
    var result = false

    func hasScreenCapturePermission() -> Bool {
        result
    }
}
