<div align="center">

<img src="https://screentranslate.filient.ai/assets/logo.png" alt="ScreenTranslate" width="128" height="128">

# ScreenTranslate

**Translate any text on your Mac screen — just drag to select.**

Powered by Apple Vision OCR. On-device by default, with optional cloud engines.

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](#license)

[Download](https://screentranslate.filient.ai/) · [Website](https://screentranslate.filient.ai/)

<table>
<tr>
<td align="center"><img src="https://screentranslate.filient.ai/assets/area-selection.png" alt="Drag to select" width="400"></td>
<td align="center"><b>→</b></td>
<td align="center"><img src="https://screentranslate.filient.ai/assets/translation-result-2.png" alt="Translation result" width="400"></td>
</tr>
<tr>
<td align="center"><b>Drag to select</b></td>
<td></td>
<td align="center"><b>Translation result</b></td>
</tr>
</table>

</div>

---

## How It Works

1. **Press shortcut** — Hit `Ctrl + Shift + T` (customizable) to enter selection mode
2. **Drag to select** — Draw a rectangle around the text you want to translate
3. **Read translation** — Translation appears in a popup near your selection

That's it. No copy-paste, no browser tabs, no context switching.

## Features

- **Completely Private** — On-device by default. No servers, no tracking, no data collection
- **Instant Translation** — One shortcut triggers area selection, OCR, and translation in a single motion
- **18 Languages** — Korean, English, Japanese, Chinese, and 14 more. Auto-detect source language supported
- **Works Offline** — Download language packs once, translate anywhere without internet
- **BYOK Cloud Engines** — Bring your own API key for DeepL, Google Cloud Translation, or Microsoft Azure Translator
- **Auto Copy** — Translation results are automatically copied to clipboard
- **Translation History** — Every translation is saved. Search and copy previous results anytime
- **Menu Bar App** — Lightweight, always available, never in the way

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon or Intel

## Installation

### Download DMG

Download the latest version from the [website](https://screentranslate.filient.ai/).

### Build from Source

```bash
git clone https://github.com/hcmhcs/screenTranslate.git
cd screenTranslate
open ScreenTranslate.xcodeproj
```

Build and run with Xcode 16+.

## Getting Started

1. Launch ScreenTranslate — it appears in your **menu bar**
2. Grant **Screen Recording** permission when prompted (System Settings → Privacy & Security)
3. Press `Ctrl + Shift + T` and drag over any text on screen
4. The translation popup appears instantly

### Changing Languages

Open Settings from the menu bar icon to:
- Set source language (or leave as Auto-detect)
- Set target language
- Download language packs for offline use
- Customize the keyboard shortcut

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI + AppKit |
| OCR | Apple Vision |
| Translation | Apple Translation (on-device), DeepL, Google, Azure |
| Data | SwiftData |
| Updates | Sparkle |
| Architecture | @Observable, MainActor isolation |

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
