#!/bin/bash
# Extract release notes for a specific version from CHANGELOG.md
# Usage: ./scripts/extract_changelog.sh <version>

set -e

VERSION="${1:?Usage: extract_changelog.sh <version>}"
CHANGELOG="${2:-CHANGELOG.md}"

if [ ! -f "$CHANGELOG" ]; then
    echo ""
    exit 0
fi

awk -v ver="$VERSION" '
    /^## \[/ {
        if (found) exit
        if (index($0, "[" ver "]")) found=1
        next
    }
    found { print }
' "$CHANGELOG" | sed -e '/^$/N;/^\n$/d' -e 's/^[[:space:]]*$//'
