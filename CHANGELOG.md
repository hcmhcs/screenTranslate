# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
