<div align="center">

<img src="https://screentranslate.filient.ai/assets/logo.png" alt="ScreenTranslate" width="128" height="128">

# ScreenTranslate

**Translate any text on your Mac screen — capture or select.**

Screen capture with OCR, or select text and translate directly. On-device by default, with optional cloud engines.

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](#license)

<a href="https://www.producthunt.com/products/screentranslate"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1089066&theme=neutral&t=1772670917164" alt="Product Hunt" width="200"></a>

[Download](https://github.com/hcmhcs/screenTranslate/releases/latest) · [Website](https://screentranslate.filient.ai/?utm_source=github&utm_medium=readme&utm_campaign=screentranslate) · [Privacy Policy](https://screentranslate.filient.ai/privacy?utm_source=github&utm_medium=readme&utm_campaign=screentranslate)

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

### Screen Capture Translation

1. **Press shortcut** — Hit `Cmd + Shift + T` (customizable) to enter selection mode
2. **Drag to select** — Draw a rectangle around the text you want to translate
3. **Read translation** — Translation appears in a popup near your selection

### Text Selection Translation

1. **Select text** — Highlight text in any app
2. **Press shortcut** — Hit `Cmd + Option + Z` (customizable) to translate
3. **Read translation** — Translation appears instantly — no OCR needed

No copy-paste, no browser tabs, no context switching.

## Features

- **Free & Open Source** — No subscription, no ads, no hidden costs. Licensed under GPL-3.0
- **Completely Private** — On-device by default. No servers, no tracking, no data collection
- **Instant Translation** — One shortcut triggers area selection, OCR, and translation in a single motion
- **Text Selection Translation** — Select text in any app and translate directly — no OCR needed. Supports even more languages with cloud engines
- **20 Languages** — Auto-detect source language supported. Full list below
- **Works Offline** — Download language packs once, translate anywhere without internet
- **Optional Cloud Engines (BYOK)** — Already works without any API key. Optionally connect DeepL, Google Cloud, or Azure for more languages
- **Auto Copy** — Translation results are copied to clipboard by default (can be disabled in Settings)
- **Translation History** — Every translation is saved. Search and copy previous results anytime
- **Menu Bar App** — Lightweight, always available, never in the way

### Supported Languages

| | | | |
|---|---|---|---|
| Korean | English | Japanese | Chinese (Simplified) |
| Chinese (Traditional) | French | German | Spanish |
| Portuguese | Italian | Russian | Arabic |
| Dutch | Hindi | Indonesian | Polish |
| Thai | Turkish | Ukrainian | Vietnamese |

All powered by Apple Translation — on-device and offline capable.
Connect your own API key (DeepL, Google, Azure) for additional languages.

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
3. Grant **Accessibility** permission for text selection translation (System Settings → Privacy & Security)
4. Press `Cmd + Shift + T` and drag over any text on screen — or select text and press `Cmd + Option + Z`
5. The translation popup appears instantly

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
