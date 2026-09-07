#!/usr/bin/env bash
#
# ScreenTranslate uninstaller
#
# Removes the app bundle and its user data: settings (UserDefaults), stored
# API keys (Keychain), translation history, downloaded/imported fonts,
# permission grants, caches. Each step asks before deleting anything.
#
# Usage:
#   bash uninstall.sh
#
# Manual instructions: see UNINSTALL.md in the repository root.

set -euo pipefail

BUNDLE_ID="com.changmin.ScreenTranslate"
KEYCHAIN_SERVICE="com.changmin.ScreenTranslate"
KEYCHAIN_ACCOUNTS=(
  "com.screentranslate.api.deepl"
  "com.screentranslate.api.google"
  "com.screentranslate.api.azure"
)
APP_PATHS=(
  "/Applications/ScreenTranslate.app"
  "$HOME/Applications/ScreenTranslate.app"
)
APP_SUPPORT="$HOME/Library/Application Support/ScreenTranslate"
LEGACY_STORE="$HOME/Library/Application Support/default.store"
CACHES="$HOME/Library/Caches/$BUNDLE_ID"
SAVED_STATE="$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"

step() { printf '\n==> %s\n' "$1"; }

# ask <prompt> [default Y|N] — returns 0 (yes) or 1 (no)
ask() {
  local prompt="$1" default="${2:-N}" answer hint="y/N"
  [ "$default" = "Y" ] && hint="Y/n"
  # stdin이 tty가 아니면(파이프 실행 등) 기본값으로 안전하게 빠진다
  read -r -p "$prompt [$hint] " answer || true
  answer="${answer:-$default}"
  case "$answer" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

echo "ScreenTranslate Uninstaller"
echo "Each step asks before deleting. Ctrl+C aborts at any time."

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Error: this script is for macOS only."
  exit 1
fi

# 0. 실행 중이면 종료
if pgrep -x ScreenTranslate >/dev/null 2>&1; then
  step "Quitting ScreenTranslate"
  killall ScreenTranslate 2>/dev/null || true
  sleep 1
fi

# 1. 앱 번들
step "1/7 — App bundle"
found=0
for path in "${APP_PATHS[@]}"; do
  if [ -d "$path" ]; then
    found=1
    if ask "  Delete \"$path\"?"; then
      if rm -rf "$path" 2>/dev/null; then
        echo "  Deleted: $path"
      else
        echo "  Permission denied. Run it yourself:"
        echo "    sudo rm -rf \"$path\""
      fi
    fi
  fi
done
[ "$found" = "0" ] && echo "  App bundle not found (already removed?)"

# 2. 설정 (UserDefaults)
step "2/7 — Settings (languages, shortcuts, onboarding)"
if ask "  Delete preferences?"; then
  if defaults delete "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "  Deleted."
  else
    echo "  Nothing to delete."
  fi
fi

# 3. API 키 (Keychain)
step "3/7 — Stored API keys (DeepL / Google / Azure)"
if ask "  Delete stored API keys?"; then
  deleted=0
  for account in "${KEYCHAIN_ACCOUNTS[@]}"; do
    if security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1; then
      echo "  Deleted: $account"
      deleted=1
    fi
  done
  [ "$deleted" = "0" ] && echo "  No stored keys found."
fi

# 4. 히스토리 DB + 폰트
step "4/7 — History database and fonts"
if [ -d "$APP_SUPPORT" ]; then
  echo "  $APP_SUPPORT"
  echo "  Contains: translation history, downloaded/imported fonts."
  if ask "  Delete it?"; then
    rm -rf "$APP_SUPPORT"
    echo "  Deleted."
  fi
else
  echo "  Not found."
fi

# 5. 구버전 히스토리 (v1.5.2 이하) — 별도 경고
step "5/7 — Legacy history database (v1.5.2 and earlier)"
if [ -f "$LEGACY_STORE" ]; then
  echo "  $LEGACY_STORE"
  echo "  Warning: this is your translation history from v1.5.2 or earlier."
  echo "  The filename (\"default.store\") is generic — another non-sandboxed app"
  echo "  could theoretically use the same file. Only delete it if you know"
  echo "  it belongs to ScreenTranslate."
  if ask "  Delete it anyway?" "N"; then
    rm -f "$LEGACY_STORE" "$LEGACY_STORE-wal" "$LEGACY_STORE-shm"
    echo "  Deleted."
  else
    echo "  Kept."
  fi
else
  echo "  Not found."
fi

# 6. 권한 (TCC)
step "6/7 — Permission grants (Screen Recording, Accessibility)"
if ask "  Reset permission grants?"; then
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 && echo "  Screen Recording reset." || true
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 && echo "  Accessibility reset." || true
fi

# 7. 캐시·윈도우 상태
step "7/7 — Caches and saved window state"
if [ -e "$CACHES" ] || [ -e "$SAVED_STATE" ]; then
  if ask "  Delete caches and saved window state?"; then
    for path in "$CACHES" "$SAVED_STATE"; do
      if [ -e "$path" ]; then
        rm -rf "$path"
        echo "  Deleted: $path"
      fi
    done
  fi
else
  echo "  Nothing to delete."
fi

cat <<'EOF'

Done.

Note: if "Launch at Login" was enabled, remove the leftover entry in
System Settings > General > Login Items & Extensions.
EOF
