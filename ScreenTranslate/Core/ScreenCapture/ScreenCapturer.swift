import ScreenCaptureKit
import CoreGraphics
import AppKit

final class ScreenCapturer {
    /// 지정된 화면 좌표 영역을 캡처한다.
    /// - Parameters:
    ///   - rect: 캡처할 화면 영역 (SwiftUI 좌표계 — 좌상단 원점, 포인트 단위)
    ///   - screen: 캡처 대상 화면
    /// - Returns: 캡처된 CGImage
    func capture(rect: CGRect, screen: NSScreen? = nil) async throws -> CGImage {
        guard let targetScreen = screen ?? NSScreen.main else {
            throw CaptureError.noDisplayFound
        }
        let scaleFactor = targetScreen.backingScaleFactor

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // H7: displayID로 매칭한다. frame 비교는 Retina 스케일링,
        // 디스플레이 배치 변경 등으로 불일치할 수 있다.
        let screenID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == screenID })
            ?? content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        // H7: 자기 앱(팝업, 오버레이 잔상)이 스크린샷에 찍혀 OCR 대상에 섞이지 않도록 제외
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        // 픽셀 단위로 설정 (Retina 대응)
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.scalesToFit = false
        config.capturesAudio = false
        config.showsCursor = false

        let screenshot = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // 좌표 변환: SwiftUI (좌상단 원점, 포인트) → CGImage (좌상단, 픽셀)
        // rect는 오버레이 윈도우 로컬 좌표(이미 스크린 로컬)이므로
        // 스크린 글로벌 원점을 빼면 안 된다 (멀티모니터에서 오류 발생).
        let croppingRect = CGRect(
            x: rect.origin.x * scaleFactor,
            y: rect.origin.y * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        )

        guard let cropped = screenshot.cropping(to: croppingRect) else {
            throw CaptureError.cropFailed
        }

        return cropped
    }
}

nonisolated enum CaptureError: LocalizedError {
    case noDisplayFound
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return L10n.noDisplayFound
        case .cropFailed: return L10n.cropFailed
        }
    }
}

// MARK: - Permission Check

extension ScreenCapturer {
    static func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }
}
