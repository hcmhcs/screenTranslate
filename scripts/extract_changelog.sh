#!/bin/bash
# Extract release notes for a specific version from CHANGELOG.md
#
# Usage:
#   ./scripts/extract_changelog.sh <version>                    # Full notes
#   ./scripts/extract_changelog.sh <version> --highlights       # Highlights only
#   ./scripts/extract_changelog.sh <version> --highlights CHANGELOG.md

set -e

VERSION="${1:?Usage: extract_changelog.sh <version> [--highlights] [CHANGELOG.md]}"
shift

# Parse optional flags
HIGHLIGHTS_ONLY=false
CHANGELOG="CHANGELOG.md"

for arg in "$@"; do
    case "$arg" in
        --highlights) HIGHLIGHTS_ONLY=true ;;
        *) CHANGELOG="$arg" ;;
    esac
done

if [ ! -f "$CHANGELOG" ]; then
    echo ""
    exit 0
fi

if [ "$HIGHLIGHTS_ONLY" = true ]; then
    # Highlights 섹션만 추출 (### Highlights ~ 다음 ### 전까지)
    # Highlights가 없으면 빈 문자열 반환
    awk -v ver="$VERSION" '
        /^## \[/ {
            if (in_version) exit
            if (index($0, "[" ver "]")) in_version=1
            next
        }
        in_version && /^### Highlights/ { in_highlights=1; next }
        in_version && in_highlights && /^### / { exit }
        in_highlights { print }
    ' "$CHANGELOG" | sed -e '/^$/N;/^\n$/d' -e 's/^[[:space:]]*$//'
else
    # 전체 릴리즈 노트 추출 (기존 동작)
    awk -v ver="$VERSION" '
        /^## \[/ {
            if (found) exit
            if (index($0, "[" ver "]")) found=1
            next
        }
        found { print }
    ' "$CHANGELOG" | sed -e '/^$/N;/^\n$/d' -e 's/^[[:space:]]*$//'
fi
