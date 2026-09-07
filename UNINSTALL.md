# Uninstalling ScreenTranslate

Two ways to remove ScreenTranslate completely — including settings, stored API keys, translation history, downloaded fonts, and permission grants.

- **Option 1** — Uninstall script (asks before deleting each item)
- **Option 2** — Manual removal (step-by-step commands)

> **Note for Homebrew users:** `brew uninstall --cask screentranslate` removes only the app bundle. Follow Option 1 or 2 below to also remove user data.

---

## Option 1 — Uninstall script (recommended)

Download the script and run it locally (so you can review it first):

```bash
curl -fsSL -o uninstall.sh \
  https://raw.githubusercontent.com/hcmhcs/screenTranslate/main/scripts/uninstall.sh

# Optional: review before running
less uninstall.sh

bash uninstall.sh
```

The script walks through 7 steps and asks **y/N** before each deletion:

1. App bundle (`/Applications/ScreenTranslate.app`)
2. Settings — languages, shortcuts, onboarding (UserDefaults)
3. Stored API keys — DeepL / Google / Azure (Keychain)
4. Translation history + downloaded/imported fonts
5. Legacy history database from v1.5.2 or earlier (`default.store`) — **double warning**, default No
6. Permission grants — Screen Recording, Accessibility
7. Caches and saved window state

It also quits the app first if it is running.

---

## Option 2 — Manual removal

### 1. Quit the app

Menu bar icon → **Quit** (or `killall ScreenTranslate` in Terminal).

### 2. Delete the app bundle

```bash
rm -rf "/Applications/ScreenTranslate.app"
```

Installed via Homebrew instead? Use `brew uninstall --cask screentranslate`.

### 3. Delete settings

```bash
defaults delete com.changmin.ScreenTranslate
```

Removes: language selection, keyboard shortcuts, onboarding completion, auto-copy and popup preferences.

### 4. Delete stored API keys (if you used cloud engines)

```bash
security delete-generic-password -s "com.changmin.ScreenTranslate" -a "com.screentranslate.api.deepl"
security delete-generic-password -s "com.changmin.ScreenTranslate" -a "com.screentranslate.api.google"
security delete-generic-password -s "com.changmin.ScreenTranslate" -a "com.screentranslate.api.azure"
```

"Could not be found" means you never stored that key — that's fine.

### 5. Delete history and fonts

```bash
rm -rf "$HOME/Library/Application Support/ScreenTranslate"
```

Contains: the translation history database and downloaded/imported fonts.

### 6. (v1.5.2 or earlier) Legacy history database

```bash
rm -f "$HOME/Library/Application Support/default.store" \
      "$HOME/Library/Application Support/default.store-wal"
```

> ⚠️ **Warning:** the filename `default.store` is generic. It is the ScreenTranslate history database used by v1.5.2 and earlier, but other non-sandboxed apps could theoretically use the same path. Delete it only if you know it belongs to ScreenTranslate.

### 7. Reset permission grants

```bash
tccutil reset ScreenCapture com.changmin.ScreenTranslate
tccutil reset Accessibility com.changmin.ScreenTranslate
```

### 8. Caches and saved window state (optional)

```bash
rm -rf "$HOME/Library/Caches/com.changmin.ScreenTranslate"
rm -rf "$HOME/Library/Saved Application State/com.changmin.ScreenTranslate.savedState"
```

### 9. Login item (if "Launch at Login" was enabled)

Remove the leftover entry in **System Settings → General → Login Items & Extensions**.

---

## 한국어 안내

ScreenTranslate를 완전히 삭제하는 두 가지 방법입니다. 설정, 저장된 API 키, 번역 히스토리, 다운로드한 폰트, 권한 허용까지 모두 삭제합니다.

### 방법 1 — 삭제 스크립트 (권장)

```bash
curl -fsSL -o uninstall.sh \
  https://raw.githubusercontent.com/hcmhcs/screenTranslate/main/scripts/uninstall.sh
bash uninstall.sh
```

각 항목을 삭제하기 전에 **y/N**으로 확인합니다. 구버전(v1.5.2 이하) 히스토리 파일(`default.store`)은 별도 경고 후 기본값 No로만 삭제됩니다.

### 방법 2 — 직접 삭제

1. 메뉴바 아이콘 → **종료**
2. `rm -rf "/Applications/ScreenTranslate.app"` (Homebrew 설치는 `brew uninstall --cask screentranslate`)
3. `defaults delete com.changmin.ScreenTranslate` — 언어·단축키·온보딩 등 설정
4. API 키 사용 시: `security delete-generic-password -s "com.changmin.ScreenTranslate" -a "com.screentranslate.api.deepl"` (`.google`, `.azure`도 동일)
5. `rm -rf "$HOME/Library/Application Support/ScreenTranslate"` — 히스토리·폰트
6. (v1.5.2 이하 사용자) `rm -f "$HOME/Library/Application Support/default.store"*` — ⚠️ 파일명이 공용이라 다른 앱 소유일 가능성이 있으니 확인 후 삭제
7. `tccutil reset ScreenCapture com.changmin.ScreenTranslate` / `tccutil reset Accessibility com.changmin.ScreenTranslate` — 권한 초기화
8. 시작 시 실행을 켜둔 경우: 시스템 설정 → 일반 → 로그인 항목에서 잔여 항목 제거
