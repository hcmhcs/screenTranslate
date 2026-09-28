import AppKit
import ScreenCaptureKit

/// 실시간 번역용 — 선택한 영역만 캡처한다 (화면 전체를 캡처해 자르는 ScreenCapturer 방식은 5K에서 약 59MB/회).
/// 디스플레이별 SCContentFilter를 재사용하고, 캡처가 실패하면 필터를 새로 만들어 한 번 다시 시도한다.
final class RegionScreenCapturer: LiveFrameSource {
    private var cachedFilter: (displayID: CGDirectDisplayID, filter: SCContentFilter)?

    func captureFrame(of region: LiveRegion) async throws -> CGImage {
        do {
            return try await capture(region, using: try await filter(for: region.displayID, refresh: false))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // 디스플레이 배치가 바뀌었거나 필터가 낡았을 수 있다
            return try await capture(region, using: try await filter(for: region.displayID, refresh: true))
        }
    }

    private func filter(for displayID: CGDirectDisplayID, refresh: Bool) async throws -> SCContentFilter {
        if !refresh, let cachedFilter, cachedFilter.displayID == displayID {
            return cachedFilter.filter
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplayFound
        }
        // 자기 앱 창(영역 테두리·툴바·자막 바)이 캡처에 섞이지 않도록 제외
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        cachedFilter = (displayID, filter)
        return filter
    }

    private func capture(_ region: LiveRegion, using filter: SCContentFilter) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.sourceRect = region.rect  // 디스플레이 좌표(포인트, 좌상단 원점) — 오버레이 좌표와 같다
        config.width = max(1, Int(region.rect.width * region.scale))
        config.height = max(1, Int(region.rect.height * region.scale))
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
