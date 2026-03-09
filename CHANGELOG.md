# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.2] - 2026-03-10

### Highlights

- 🆕 Popup width toggle — match popup width to selection area or auto-adjust by text length
- 🔧 Settings reorganized into General / Advanced tabs

### Added

- Popup width matching toggle in Settings (default: off, adjusts by text length)

### Improved

- Settings reorganized into two tabs: General (languages, shortcuts, app) and Advanced (engine, popup, other)
- Capture overlay crosshair cursor now appears instantly (AppKit-based)

### Fixed

- Screen capture overlay no longer re-activates when already active
- Capture overlay completion handler safety improvements
- CI archive now uses Developer ID certificate only

## [1.4.1] - 2026-03-07

### Highlights

- 🆕 Popup font size setting — adjust translation popup text size (11pt to 20pt)

### Added

- Popup font size setting in General section (stepper, 11-20pt, default 13pt)
- Dynamic popup size calculation based on font size

## [1.4.0] - 2026-03-06

### Highlights

- 🆕 Text Selection Translation — select text in any app, press shortcut to translate instantly (no OCR needed)
- 🔧 Sparkle update dialog now shows release highlights with GitHub link

### Added

- Text selection translation (`Cmd+Option+Z`) — translate selected text directly without screen capture
- Sparkle update dialog HTML release notes with Highlights section
- Changelog Highlights extraction for Sparkle (`extract_changelog.sh --highlights`)
- GitHub release link in Sparkle update dialog (`fullReleaseNotesLink`)

### Improved

- Popup position stability (top-left anchor fixed when height changes)
- TextGrabber safety (clipboard backup/restore, CoreFoundation cast guard separation)
- Settings shortcut label renamed to "Screen Translate Shortcut"
- README updated with two translation modes (screen capture + text selection)

## [1.3.1] - 2026-03-05

### Added

- Engine inline descriptions in Settings (shows engine type and API key requirement)
- Engine status icons in translation engine picker (key status at a glance)
- Engine setup guide link for cloud engines (opens website engines page)
- Help tooltips on 6 settings controls (hover to see description)
- External links section in About window (Website, Engines Guide, Privacy Policy, GitHub)

### Improved

- Language pack download UX in Settings and Onboarding (progress indicator, elapsed time, hints)

## [1.3.0] - 2026-03-05

### Added

- Popup window resize via bottom-right drag grip
- Expanded supported languages to 20 (Arabic, Dutch, Hindi, Indonesian, Polish, Portuguese, Romanian, Swedish, Thai, Turkish, Ukrainian, Vietnamese added)
- OCR preprocessing: preserve line breaks for bullet/numbered lists

### Improved

- Onboarding UI refinement and X button behavior change
- History timestamps now use smart format (relative for recent, date for older)
- Test suite expanded from 17 to 79 tests

### Changed

- Default shortcut changed from Ctrl+Shift+T to Cmd+Shift+T

## [1.2.1] - 2026-03-04

### Added

- OCR paragraph break detection (preserves paragraph structure in multi-paragraph text)

### Improved

- Popup UX: auto-copy feedback, drag position retention, accessibility support, precise text height measurement

### Changed

- License changed from MIT to GPL v3
- Updated README with BYOK engine info and revised project description
- Removed unnecessary files from git tracking (website, local scripts)
- Public CHANGELOG converted to English

## [1.2.0] - 2026-03-04

### Added

- Auto-copy translation to clipboard (configurable, enabled by default)
- First-launch onboarding (shortcut setup + language pack download)
- BYOK translation engines (DeepL, Google Cloud Translation, Microsoft Azure Translator)
- OCR text preprocessing (line break merging for natural sentence flow)

### Improved

- Reduced "Copied" feedback duration (1.5s → 0.5s)
- Improved DeepL translation quality (split_sentences nonewlines parameter)

### Fixed

- Popup window not appearing above other apps
- Sparkle update check error (CFBundleVersion mismatch)
- Improved API key error messages

## [1.1.1] - 2026-03-04

### Added

- Contact email in About window
- README.md

### Fixed

- Unnecessary files included in DMG (DistributionSummary.plist, ExportOptions.plist, Packaging.log)
- OCR/translation engine name i18n in Settings

## [1.1.0] - 2026-03-03

### Added

- TelemetryDeck SDK integration (privacy-first analytics)
  - `appLaunched` signal (DAU/MAU tracking)
  - `translationCompleted` signal (feature usage)
- Auto-copy latest DMG in CI (stable download URL)

### Fixed

- CI archive signing error (added API Key authentication flags)
- Xcode 16.4 concurrency error (added @MainActor to AppOrchestrator)

## [1.0.0] - 2026-03-03

### Added

- Update check button disabled state in menu bar and About window
- Release notes display in Sparkle update dialog

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
- GitHub Actions CI/CD pipeline

### Fixed

- Drag not working after keyboard shortcut
- Continuous translation stopping unexpectedly
- Popup flickering on repeated translations
