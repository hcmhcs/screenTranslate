# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-03-04

### Added
- 웹사이트 인터랙티브 데모 섹션 (드래그 번역 체험)
- About 화면 및 웹사이트 푸터에 연락처 이메일 추가
- README.md 추가

### Fixed
- DMG 설치 파일에 불필요한 파일 포함되는 문제 수정 (DistributionSummary.plist, ExportOptions.plist, Packaging.log)
- 설정 화면 OCR/번역 엔진 이름 i18n 처리 (로컬/Local)

## [1.1.0] - 2026-03-03

### Added
- TelemetryDeck SDK 통합 (프라이버시 중심 사용자 분석)
  - `appLaunched` 시그널 (DAU/MAU 산출)
  - `translationCompleted` 시그널 (기능 사용률)
- Google Analytics 4 다운로드 클릭 이벤트 추적
- 웹사이트 SEO 최적화 (Open Graph, Twitter Card, JSON-LD, sitemap.xml)
- 웹사이트 GEO 최적화 (llms.txt, llms-full.txt — AI 검색 엔진 대응)
- CI에서 latest DMG 자동 복사 (안정적 다운로드 URL)

### Fixed
- CI archive 서명 오류 수정 (API Key 인증 플래그 추가)
- Xcode 16.4 동시성 에러 수정 (AppOrchestrator @MainActor 추가)

## [1.0.0] - 2026-03-03

### Added
- Update check button disabled state in menu bar and About window (canCheckForUpdates binding)
- Release notes display in Sparkle update dialog
- Landing page website (EN/KO i18n, Docker deployment)
- Website deployment script and documentation

## [0.0.1] - 2026-03-03

### Added
- Screen capture with region selection overlay
- OCR text recognition (Apple Vision)
- Translation pipeline (Apple Translation, on-device)
- Translation popup with copy, close, original text toggle
- Menu bar app (MenuBarExtra)
- Translation history with SwiftData persistence
- Recent translations submenu in menu bar
- Language pack management with download status
- Source/target language selection with swap button
- Auto-detect source language
- Keyboard shortcut for translation (customizable)
- App language setting (English / Korean)
- Launch at login toggle
- About window with version info
- Check for Updates menu item (Sparkle)
- Sparkle auto-update framework integration
- DMG distribution with code signing and notarization
- Oracle Cloud Object Storage for update hosting
- GitHub Actions CI/CD pipeline
- Local release script with interactive prompts

### Fixed
- Drag not working after keyboard shortcut
- Continuous translation stopping unexpectedly
- Popup flickering on repeated translations
