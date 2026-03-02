#!/bin/bash
# ========================================
# CHANGELOG.md에서 특정 버전의 릴리즈 노트 추출
# ========================================
# Usage: ./scripts/extract_changelog.sh 0.0.1
#
# CHANGELOG.md에서 지정된 버전의 섹션만 추출하여 stdout으로 출력.
# 버전이 없으면 빈 문자열 반환 (exit 0).

set -e

VERSION="${1:?Usage: extract_changelog.sh <version>}"
CHANGELOG="${2:-CHANGELOG.md}"

if [ ! -f "$CHANGELOG" ]; then
    echo ""
    exit 0
fi

# 버전 헤더 사이의 내용 추출 (## [version] 부터 다음 ## [ 까지)
awk -v ver="$VERSION" '
    /^## \[/ {
        if (found) exit
        if (index($0, "[" ver "]")) found=1
        next
    }
    found { print }
' "$CHANGELOG" | sed -e '/^$/N;/^\n$/d' -e 's/^[[:space:]]*$//'
