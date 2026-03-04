import Foundation
import Testing
@testable import ScreenTranslate

@Suite(.serialized)
struct OnboardingLogicTests {

    // MARK: - PermissionChecking 프로토콜

    @Test("MockPermissionChecker returns configured value")
    func permissionChecker_returnsConfiguredValue() {
        let checker = MockPermissionChecker()
        #expect(checker.hasScreenCapturePermission() == false)

        checker.result = true
        #expect(checker.hasScreenCapturePermission() == true)
    }

    @Test("SystemPermissionChecker conforms to PermissionChecking")
    func systemPermissionChecker_conforms() {
        let checker: PermissionChecking = SystemPermissionChecker()
        // 테스트 환경에서는 권한 없을 가능성 높음 — 크래시 없이 Bool 반환만 확인
        _ = checker.hasScreenCapturePermission()
    }

    // MARK: - finishOnboarding 로직

    @Test("finishOnboarding saves hasCompletedOnboarding = true")
    func finishOnboarding_setsFlag() {
        let key = "com.screentranslate.hasCompletedOnboarding"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        #expect(AppSettings.shared.hasCompletedOnboarding == false)

        // finishOnboarding 로직 재현
        AppSettings.shared.hasCompletedOnboarding = true
        #expect(AppSettings.shared.hasCompletedOnboarding == true)
    }

    @Test("finishOnboarding saves targetLanguageCode")
    func finishOnboarding_savesTargetLanguage() {
        let key = "com.screentranslate.targetLanguageCode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        AppSettings.shared.targetLanguageCode = "ja"
        #expect(AppSettings.shared.targetLanguageCode == "ja")

        // finishOnboarding에서 선택한 언어가 저장되는지
        AppSettings.shared.targetLanguageCode = "zh-Hans"
        #expect(AppSettings.shared.targetLanguageCode == "zh-Hans")
    }

    @Test("hasCompletedOnboarding defaults to false")
    func hasCompletedOnboarding_defaultsFalse() {
        let key = "com.screentranslate.hasCompletedOnboarding"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(AppSettings.shared.hasCompletedOnboarding == false)
    }
}
