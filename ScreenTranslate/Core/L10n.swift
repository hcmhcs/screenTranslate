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
    static var swapLanguages: String { s("Swap Languages", ko: "언어 교체") }
    static var launchAtLogin: String { s("Launch at Login", ko: "로그인 시 열기") }
    static var languagePackNotInstalled: String { s("Language Pack Not Installed", ko: "언어팩 미설치") }
    static var confirm: String { s("OK", ko: "확인") }
    static var download: String { s("Download", ko: "다운로드") }
    static var downloading: String { s("Downloading...", ko: "다운로드 중...") }
    static var later: String { s("Later", ko: "나중에") }

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
