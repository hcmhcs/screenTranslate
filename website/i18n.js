const translations = {
    en: {
        "nav.features": "Features",
        "nav.howItWorks": "How It Works",
        "nav.download": "Download",
        "hero.pill1": "Private",
        "hero.pill2": "Fast",
        "hero.pill3": "Offline",
        "hero.title": "Translate anything<br>on your screen",
        "hero.description": "Select any area, get instant translation.<br>Powered by Apple Vision OCR and Apple Translation — entirely on-device.",
        "hero.download": "Download for Mac",
        "hero.learnMore": "See how it works",
        "hero.free": "Free",
        "features.title": "Built for your workflow",
        "features.subtitle": "No context switching. No copy-paste into a browser. Just select and read.",
        "features.privacy.title": "Completely Private",
        "features.privacy.desc": "All processing happens on your Mac. Your text never leaves the device — no servers, no tracking, no data collection.",
        "features.instant.title": "Instant Translation",
        "features.instant.desc": "One shortcut triggers area selection, OCR recognition, and translation — all in a single fluid motion.",
        "features.languages.title": "18 Languages",
        "features.languages.desc": "Translate between Korean, English, Japanese, Chinese, and 14 more languages. Auto-detect source language supported.",
        "features.offline.title": "Works Offline",
        "features.offline.desc": "Download language packs once, translate anywhere — no internet connection required after initial setup.",
        "features.history.title": "Translation History",
        "features.history.desc": "Every translation is automatically saved. Search, review, and copy previous results anytime from the menu bar.",
        "features.menubar.title": "Lives in Menu Bar",
        "features.menubar.desc": "Lightweight menu bar app that uses minimal system resources. Always available, never in the way.",
        "howItWorks.title": "Three steps. That's it.",
        "howItWorks.step1.title": "Press shortcut",
        "howItWorks.step1.desc": "Hit your customizable keyboard shortcut to enter selection mode.",
        "howItWorks.step2.title": "Drag to select",
        "howItWorks.step2.desc": "Draw a rectangle around the text you want to translate.",
        "howItWorks.step3.title": "Read translation",
        "howItWorks.step3.desc": "Translation appears in a popup near your selection in under a second. One click to copy.",
        "showcase.title": "Everything you need",
        "showcase.subtitle": "Menu bar access, translation history, and customizable settings.",
        "showcase.menubar": "Menu Bar",
        "showcase.history": "Translation History",
        "showcase.settings": "Settings",
        "download.title": "Ready to try?",
        "download.subtitle": "Free to use. No account required. No data collected.",
        "download.button": "Download DMG",
        "download.free": "Free",
    },
    ko: {
        "nav.features": "기능",
        "nav.howItWorks": "사용 방법",
        "nav.download": "다운로드",
        "hero.pill1": "프라이버시",
        "hero.pill2": "빠른 속도",
        "hero.pill3": "오프라인",
        "hero.title": "화면의 어떤 텍스트든<br>드래그 한 번으로 번역",
        "hero.description": "영역을 선택하면 즉시 번역됩니다.<br>Apple Vision OCR과 Apple Translation 기반 — 모든 처리가 기기 내에서 완료됩니다.",
        "hero.download": "Mac용 다운로드",
        "hero.learnMore": "사용 방법 보기",
        "hero.free": "무료",
        "features.title": "워크플로우에 맞게 설계",
        "features.subtitle": "컨텍스트 전환 없이, 브라우저에 복사할 필요 없이. 선택하고 읽으세요.",
        "features.privacy.title": "완전한 프라이버시",
        "features.privacy.desc": "모든 처리가 Mac에서 이루어집니다. 텍스트가 외부 서버로 전송되지 않으며, 추적이나 데이터 수집이 없습니다.",
        "features.instant.title": "즉시 번역",
        "features.instant.desc": "단축키 하나로 영역 선택, OCR 인식, 번역까지 — 하나의 자연스러운 동작으로 완료됩니다.",
        "features.languages.title": "18개 언어",
        "features.languages.desc": "한국어, 영어, 일본어, 중국어 등 18개 언어 간 번역. 소스 언어 자동 감지를 지원합니다.",
        "features.offline.title": "오프라인 사용",
        "features.offline.desc": "언어팩을 한 번 다운로드하면 인터넷 연결 없이도 어디서든 번역할 수 있습니다.",
        "features.history.title": "번역 히스토리",
        "features.history.desc": "모든 번역 기록이 자동으로 저장됩니다. 메뉴바에서 언제든 이전 번역을 검색하고 복사하세요.",
        "features.menubar.title": "메뉴바 앱",
        "features.menubar.desc": "시스템 리소스를 거의 사용하지 않는 메뉴바 앱. 항상 대기하며, 방해하지 않습니다.",
        "howItWorks.title": "세 단계면 충분합니다.",
        "howItWorks.step1.title": "단축키 입력",
        "howItWorks.step1.desc": "설정한 키보드 단축키를 누르면 선택 모드가 시작됩니다.",
        "howItWorks.step2.title": "영역 드래그",
        "howItWorks.step2.desc": "번역할 텍스트가 있는 영역을 마우스로 드래그합니다.",
        "howItWorks.step3.title": "번역 확인",
        "howItWorks.step3.desc": "1초 이내로 선택 영역 근처에 번역 결과가 팝업으로 표시됩니다. 클릭 한 번으로 복사.",
        "showcase.title": "필요한 모든 것",
        "showcase.subtitle": "메뉴바 접근, 번역 히스토리, 커스터마이징 가능한 설정.",
        "showcase.menubar": "메뉴바",
        "showcase.history": "번역 히스토리",
        "showcase.settings": "설정",
        "download.title": "지금 시작하세요",
        "download.subtitle": "무료로 사용. 계정 불필요. 데이터 수집 없음.",
        "download.button": "DMG 다운로드",
        "download.free": "무료",
    },
};

function setLang(lang) {
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-i18n]").forEach((el) => {
        const key = el.getAttribute("data-i18n");
        const text = translations[lang]?.[key];
        if (text) el.innerHTML = text;
    });

    // Update page title & meta
    if (lang === "ko") {
        document.title = "ScreenTranslate — Mac 화면 번역";
        document.querySelector('meta[name="description"]').content =
            "화면의 어떤 텍스트든 드래그 한 번으로 번역. macOS 전용 온디바이스 번역 앱.";
    } else {
        document.title = "ScreenTranslate — Translate Any Text on Your Screen";
        document.querySelector('meta[name="description"]').content =
            "Select any area on your Mac screen and get instant translation. Fully on-device with Apple Translation. Private, fast, offline.";
    }

    localStorage.setItem("lang", lang);
}

function toggleLang() {
    const current = localStorage.getItem("lang") || "en";
    setLang(current === "en" ? "ko" : "en");
}

// Init
document.addEventListener("DOMContentLoaded", () => {
    const saved = localStorage.getItem("lang");
    const browserLang = navigator.language.startsWith("ko") ? "ko" : "en";
    setLang(saved || browserLang);

    document.getElementById("lang-switch").addEventListener("click", toggleLang);
});
