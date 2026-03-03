import Foundation

/// 앱 전체 UI 문자열의 영어/한국어 로컬라이제이션.
/// UserDefaults에서 직접 읽어 nonisolated 컨텍스트(Error enum 등)에서도 안전하게 사용.
nonisolated enum L10n {
    private static var lang: String {
        UserDefaults.standard.string(forKey: "com.screentranslate.appLanguage") ?? "en"
    }

    private static func s(_ en: String, ko: String) -> String {
        lang == "ko" ? ko : en
    }

    // MARK: - Menu Bar

    static var translate: String { s("Translate", ko: "번역하기") }
    static var recentTranslations: String { s("Recent Translations", ko: "최근 번역") }
    static var noHistory: String { s("No history", ko: "히스토리 없음") }
    static var showAll: String { s("Show All...", ko: "모두 보기...") }
    static var aboutApp: String { s("About ScreenTranslate", ko: "ScreenTranslate 정보") }
    static var settingsMenu: String { s("Settings...", ko: "설정...") }
    static var checkForUpdates: String { s("Check for Updates...", ko: "업데이트 확인...") }
    static var quit: String { s("Quit", ko: "종료") }

    // MARK: - Popup

    static var recognizing: String { s("Recognizing...", ko: "인식 중...") }
    static var translating: String { s("Translating...", ko: "번역 중...") }
    static var showOriginal: String { s("Show Original", ko: "원문 보기") }
    static var copied: String { s("Copied", ko: "복사됨") }
    static var copy: String { s("Copy", ko: "복사") }
    static var close: String { s("Close", ko: "닫기") }
    static var lowConfidence: String { s("Low recognition confidence", ko: "인식 정확도가 낮습니다") }
    static var originalText: String { s("Original", ko: "원문") }

    // MARK: - Settings

    static var generalSection: String { s("General", ko: "일반") }
    static var appLanguageLabel: String { s("App Language", ko: "앱 언어") }
    static var translationSection: String { s("Translation", ko: "번역") }
    static var sourceLanguageLabel: String { s("Source", ko: "원문") }
    static var autoDetect: String { s("Auto Detect", ko: "자동 감지") }
    static var targetLanguageLabel: String { s("Target", ko: "번역") }
    static var ocrEngine: String { s("OCR Engine", ko: "OCR 엔진") }
    static var translationEngine: String { s("Translation Engine", ko: "번역 엔진") }
    static var shortcutSection: String { s("Shortcut", ko: "단축키") }
    static var translationShortcut: String { s("Translation Shortcut", ko: "번역 단축키") }
    static var ocrEngineName: String { s("Apple Vision (Local)", ko: "Apple Vision (로컬)") }
    static var translationEngineName: String { s("Apple Translation (Local)", ko: "Apple Translation (로컬)") }
    static var swapLanguages: String { s("Swap Languages", ko: "언어 교체") }
    static var launchAtLogin: String { s("Launch at Login", ko: "로그인 시 열기") }
    static var languagePackNotInstalled: String { s("Language Pack Not Installed", ko: "언어팩 미설치") }
    static var confirm: String { s("OK", ko: "확인") }
    static var download: String { s("Download", ko: "다운로드") }
    static var downloading: String { s("Downloading...", ko: "다운로드 중...") }
    static var later: String { s("Later", ko: "나중에") }

    // MARK: - API Keys

    static var apiKeysSection: String { s("API Keys", ko: "API 키") }
    static var enterApiKey: String { s("Enter API Key", ko: "API 키 입력") }
    static var apiKeyRequired: String { s("API key required to use this engine.", ko: "이 엔진을 사용하려면 API 키가 필요합니다.") }
    static var apiKeySaved: String { s("Saved", ko: "저장됨") }
    static var clear: String { s("Clear", ko: "삭제") }
    static var apiKeyInvalid: String { s("API key is invalid. Please check your key.", ko: "API 키가 유효하지 않습니다. 키를 확인해주세요.") }
    static var quotaExceeded: String { s("API quota exceeded. Please check your plan.", ko: "API 사용량을 초과했습니다. 요금제를 확인해주세요.") }
    static var regionLabel: String { s("Region", ko: "리전") }
    static var regionPlaceholder: String { s("e.g. koreacentral", ko: "예: koreacentral") }

    // MARK: - Advanced

    static var autoCopyToClipboard: String { s("Auto-copy to Clipboard", ko: "자동 클립보드 복사") }
    static var autoCopyToClipboardDesc: String { s("Automatically copy translated text to clipboard.", ko: "번역 완료 시 번역문을 자동으로 클립보드에 복사합니다.") }

    static var advancedSection: String { s("Advanced", ko: "고급") }
    static var ocrTextPreprocessing: String { s("Text Preprocessing", ko: "텍스트 전처리") }
    static var ocrTextPreprocessingDesc: String { s("Merge line breaks from OCR into natural sentences before translation.", ko: "번역 전 OCR 줄바꿈을 자연스러운 문장으로 병합합니다.") }

    static func languagePackMessage(name: String) -> String {
        s("\(name) language pack is not installed.\nWould you like to download it now?",
          ko: "\(name) 언어팩이 설치되지 않았습니다.\n지금 다운로드할까요?")
    }

    // MARK: - History

    static var translationHistory: String { s("Translation History", ko: "번역 히스토리") }
    static var deleteAll: String { s("Delete All", ko: "전체 삭제") }
    static var copyTranslation: String { s("Copy Translation", ko: "번역문 복사") }
    static var copyOriginal: String { s("Copy Original", ko: "원문 복사") }
    static var delete: String { s("Delete", ko: "삭제") }
    static var deleteAllHistory: String { s("Delete All History", ko: "모든 히스토리 삭제") }
    static var cancel: String { s("Cancel", ko: "취소") }
    static var deleteAllConfirmation: String {
        s("All translation history will be deleted.\nThis action cannot be undone.",
          ko: "모든 번역 히스토리가 삭제됩니다.\n이 작업은 되돌릴 수 없습니다.")
    }
    static var noHistoryMessage: String { s("No translation history", ko: "번역 히스토리가 없습니다") }
    static var translatedText: String { s("Translation", ko: "번역문") }
    static var selectRecord: String { s("Select a translation record", ko: "번역 기록을 선택하세요") }

    // MARK: - Permission

    static var permissionRequired: String { s("Screen access permission required", ko: "화면 접근 권한이 필요합니다") }
    static var permissionDescription: String {
        s("Please allow ScreenTranslate in System Settings > Privacy & Security > Screen Recording.",
          ko: "시스템 설정 > 개인 정보 보호 및 보안 > 화면 기록에서 ScreenTranslate를 허용해주세요.")
    }
    static var openSystemSettings: String { s("Open System Settings", ko: "시스템 설정 열기") }

    // MARK: - Onboarding

    static var onboardingWelcome: String { s("Welcome to ScreenTranslate", ko: "ScreenTranslate에 오신 것을 환영합니다") }
    static var onboardingShortcutTitle: String { s("Set Your Shortcut", ko: "단축키를 설정하세요") }
    static var onboardingShortcutDesc: String { s("Press the shortcut anywhere to translate text on screen.", ko: "어디서든 단축키를 눌러 화면의 텍스트를 번역하세요.") }
    static var onboardingFlow1: String { s("Press shortcut", ko: "단축키 누르기") }
    static var onboardingFlow2: String { s("Select area", ko: "영역 선택") }
    static var onboardingFlow3: String { s("See translation", ko: "번역 확인") }
    static var onboardingChangeHint: String { s("Use the default or click to change", ko: "기본값을 사용하거나 클릭하여 변경하세요") }
    static var onboardingLangTitle: String { s("Download Language Pack", ko: "언어팩 다운로드") }
    static var onboardingLangAutoSet: String { s("Your translation language has been set automatically.", ko: "번역 언어가 자동으로 설정되었습니다.") }
    static var onboardingLangChoose: String { s("Which language do you want to translate into?", ko: "어떤 언어로 번역할까요?") }
    static var onboardingLangInstalled: String { s("Language pack installed", ko: "언어팩 설치됨") }
    static var onboardingLangNotInstalled: String { s("Language pack not installed", ko: "언어팩 미설치") }
    static var onboardingNext: String { s("Next", ko: "다음") }
    static var onboardingDone: String { s("Get Started", ko: "시작하기") }
    static var onboardingSkip: String { s("Skip", ko: "건너뛰기") }

    // MARK: - Errors

    static var noTextFound: String { s("No text found in the selected area.", ko: "선택한 영역에서 텍스트를 찾을 수 없습니다.") }
    static var unsupportedLanguagePair: String { s("This language pair is not supported.", ko: "이 언어 조합은 지원되지 않습니다.") }
    static var noTextToTranslate: String { s("No text to translate.", ko: "번역할 텍스트가 없습니다.") }
    static var noDisplayFound: String { s("No display found.", ko: "디스플레이를 찾을 수 없습니다.") }
    static var cropFailed: String { s("Image crop failed.", ko: "이미지 크롭에 실패했습니다.") }

    static func captureError(_ description: String) -> String {
        s("Capture error: \(description)", ko: "캡처 오류: \(description)")
    }

    static func ocrFailed(_ reason: String) -> String {
        s("Text recognition failed: \(reason)", ko: "텍스트 인식 실패: \(reason)")
    }

    static func translationFailed(_ reason: String) -> String {
        s("Translation failed: \(reason)", ko: "번역 실패: \(reason)")
    }
}
