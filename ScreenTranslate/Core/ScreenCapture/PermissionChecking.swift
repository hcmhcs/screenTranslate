import CoreGraphics

protocol PermissionChecking {
    func hasScreenCapturePermission() -> Bool
}

struct SystemPermissionChecker: PermissionChecking {
    func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
