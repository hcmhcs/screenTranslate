#!/bin/bash

# ========================================
# ScreenTranslate 로컬 릴리스 배포 스크립트
# ========================================
# 목적: 로컬에서 빌드 → 서명 → 공증 → DMG/ZIP → 업로드 → appcast 업데이트
# 사용법: ./scripts/release-local.sh [options]
#
# Options:
#   --skip-build          이미 빌드된 .app 사용 (빌드 단계 건너뛰기)
#   --skip-notarization   코드 서명/공증 건너뛰기 (테스트용)
#   --help                도움말 표시
#
# 필수 환경변수 (.env.local에 설정):
#   - DEVELOPER_ID_APPLICATION: 서명 ID
#   - APPLE_API_KEY_BASE64: Apple API Key (.p8) base64 인코딩
#   - APPLE_API_KEY_ID: Apple API Key ID
#   - APPLE_API_ISSUER_ID: Apple API Issuer ID
#   - SPARKLE_PRIVATE_KEY: Sparkle EdDSA 비밀키
#   - AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY: Oracle Cloud S3 호환 키

set -e

# ========================================
# 색상 정의
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================================
# 함수 정의
# ========================================

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

show_help() {
    cat << EOF
ScreenTranslate 로컬 릴리스 배포 스크립트

사용법:
  ./scripts/release-local.sh [options]

옵션:
  --skip-build          이미 빌드된 .app 사용 (빌드 단계 건너뛰기)
  --skip-notarization   코드 서명/공증 건너뛰기 (테스트용, 비권장)
  --help                이 도움말 표시

프로세스:
  1. 환경변수 로드 (.env.local)
  2. Xcode 프로젝트에서 버전 읽기
  3. xcodebuild archive + export (Developer ID)
  4. 앱 코드 서명 (Hardened Runtime)
  5. 앱 공증 (Apple Notarization) + 스탬프
  6. ZIP 생성 + 공증
  7. DMG 생성 + 서명 + 공증 + 스탬프
  8. Sparkle EdDSA 서명
  9. Oracle Cloud에 ZIP + DMG 업로드
  10. appcast.xml 업데이트
  11. 업로드 검증

필수 도구:
  - Xcode (xcodebuild)
  - create-dmg (brew install create-dmg)
  - awscli (brew install awscli)
  - python3 + boto3 (pip3 install boto3)
EOF
    exit 0
}

# ========================================
# 파라미터 파싱
# ========================================

SKIP_BUILD=false
SKIP_NOTARIZATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-notarization)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "알 수 없는 옵션: $1"
            echo "도움말: ./scripts/release-local.sh --help"
            exit 1
            ;;
    esac
done

# ========================================
# 프로젝트 경로 설정
# ========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="ScreenTranslate"
PROJECT="ScreenTranslate.xcodeproj"
APP_NAME="ScreenTranslate"
BUILD_DIR="$HOME/build/ScreenTranslate"

# ========================================
# Step 1: 환경변수 로드
# ========================================

print_header "Step 1: 환경변수 로드"

if [ -f ".env.local" ]; then
    print_info ".env.local 파일에서 설정 로드 중..."
    source .env.local
    CONFIG_SOURCE=".env.local"
elif [ -f ".env.gitsecret" ]; then
    print_info ".env.gitsecret 파일에서 설정 로드 중..."
    source .env.gitsecret
    CONFIG_SOURCE=".env.gitsecret"
else
    print_error ".env.local 또는 .env.gitsecret 파일이 없습니다!"
    exit 1
fi

# 필수 환경변수 확인
for var in STORAGE_BASE_URL STORAGE_BUCKET STORAGE_ENDPOINT AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
    if [ -z "${!var:-}" ]; then
        print_error "$var 가 설정되지 않았습니다!"
        exit 1
    fi
done

# Sparkle 키 확인
if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
    print_warning "SPARKLE_PRIVATE_KEY가 없습니다. 서명 없이 진행합니다."
    HAS_SPARKLE_KEY=false
else
    HAS_SPARKLE_KEY=true
fi

# 코드 서명/공증 환경변수 확인
if [ "$SKIP_NOTARIZATION" = false ]; then
    if [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
        print_error "DEVELOPER_ID_APPLICATION이 설정되지 않았습니다!"
        print_info "예시: DEVELOPER_ID_APPLICATION=\"Developer ID Application: Your Name (TEAM_ID)\""
        print_info "또는 --skip-notarization 옵션으로 건너뛸 수 있습니다."
        exit 1
    fi

    if [ -z "${APPLE_API_KEY_BASE64:-}" ] || [ -z "${APPLE_API_KEY_ID:-}" ] || [ -z "${APPLE_API_ISSUER_ID:-}" ]; then
        print_error "Apple 공증 환경변수가 설정되지 않았습니다!"
        print_info "필수: APPLE_API_KEY_BASE64, APPLE_API_KEY_ID, APPLE_API_ISSUER_ID"
        exit 1
    fi

    # base64에서 .p8 파일 자동 생성
    mkdir -p "$BUILD_DIR"
    API_KEY_PATH="$BUILD_DIR/AuthKey_${APPLE_API_KEY_ID}.p8"
    echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_PATH"

    HAS_NOTARIZATION=true
    print_success "코드 서명/공증 설정 확인 완료"
    print_info "Developer ID: $DEVELOPER_ID_APPLICATION"
else
    HAS_NOTARIZATION=false
    print_warning "코드 서명/공증을 건너뜁니다 (--skip-notarization)"
fi

print_success "설정 로드 완료 (from $CONFIG_SOURCE)"
print_info "Storage: $STORAGE_BASE_URL"

# ========================================
# Step 2: 버전 읽기
# ========================================

print_header "Step 2: 버전 정보 확인"

VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -showBuildSettings 2>/dev/null | grep "MARKETING_VERSION" | head -1 | tr -d ' ' | cut -d= -f2)

if [ -z "$VERSION" ]; then
    print_error "MARKETING_VERSION을 읽을 수 없습니다!"
    exit 1
fi

print_success "버전: $VERSION"

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
RELEASE_DIR="releases/${VERSION}"

# ========================================
# Step 3: Archive + Export
# ========================================

mkdir -p "$BUILD_DIR"

if [ "$SKIP_BUILD" = true ]; then
    print_header "Step 3: 빌드 (건너뛰기)"
    print_warning "기존 빌드 사용 (--skip-build)"
else
    print_header "Step 3: Archive + Export"

    print_info "Archiving..."
    xcodebuild archive \
        -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        2>&1 | tail -3

    print_info "Exporting with Developer ID..."
    xcodebuild -exportArchive \
        -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
        -exportOptionsPlist "ExportOptions.plist" \
        -exportPath "$BUILD_DIR/export" \
        2>&1 | tail -3

    print_success "빌드 완료"
fi

APP_PATH="$BUILD_DIR/export/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    print_error "빌드된 앱을 찾을 수 없습니다: $APP_PATH"
    exit 1
fi

# ========================================
# Step 4: 앱 코드 서명 (Hardened Runtime)
# ========================================

if [ "$HAS_NOTARIZATION" = true ]; then
    print_header "Step 4: 앱 코드 서명"

    codesign --deep --force --verify --verbose \
        --options runtime \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$APP_PATH"

    codesign --verify --verbose=2 "$APP_PATH"
    print_success "앱 서명 완료"
else
    print_header "Step 4: 앱 코드 서명 (건너뛰기)"
fi

# ========================================
# Step 5: 앱 공증 + 스탬프
# ========================================

if [ "$HAS_NOTARIZATION" = true ]; then
    print_header "Step 5: 앱 공증 + 스탬프"

    ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/app-notarize.zip"

    print_info "Apple에 공증 요청 중... (몇 분 소요될 수 있습니다)"
    xcrun notarytool submit "$BUILD_DIR/app-notarize.zip" \
        --key "$API_KEY_PATH" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        --wait

    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    rm "$BUILD_DIR/app-notarize.zip"

    print_success "앱 공증 + 스탬프 완료"
else
    print_header "Step 5: 앱 공증 (건너뛰기)"
fi

# ========================================
# Step 6: ZIP 생성 + 공증
# ========================================

print_header "Step 6: Sparkle ZIP 생성"

ZIP_FILE="$BUILD_DIR/$ZIP_NAME"
rm -f "$ZIP_FILE"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_FILE"

ZIP_SIZE=$(stat -f%z "$ZIP_FILE")
ZIP_SIZE_MB=$(echo "scale=2; $ZIP_SIZE / 1024 / 1024" | bc)
print_info "파일: $ZIP_NAME ($ZIP_SIZE_MB MB)"

if [ "$HAS_NOTARIZATION" = true ]; then
    print_info "ZIP 공증 요청 중..."
    xcrun notarytool submit "$ZIP_FILE" \
        --key "$API_KEY_PATH" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        --wait
    print_success "ZIP 공증 완료"
fi

# ========================================
# Step 7: DMG 생성 + 서명 + 공증
# ========================================

print_header "Step 7: DMG 생성"

DMG_FILE="$BUILD_DIR/$DMG_NAME"
rm -f "$DMG_FILE"

if ! command -v create-dmg &> /dev/null; then
    print_error "create-dmg가 설치되지 않았습니다!"
    print_info "설치: brew install create-dmg"
    exit 1
fi

set +e
create-dmg \
    --volname "${APP_NAME}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 180 170 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 420 170 \
    "$DMG_FILE" \
    "$BUILD_DIR/export/"
CREATE_DMG_EXIT=$?
set -e

if [ $CREATE_DMG_EXIT -ne 0 ] || [ ! -f "$DMG_FILE" ]; then
    print_warning "create-dmg 실패, hdiutil 폴백"
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$BUILD_DIR/export/" \
        -ov -format UDZO "$DMG_FILE"
fi

DMG_SIZE=$(stat -f%z "$DMG_FILE")
DMG_SIZE_MB=$(echo "scale=2; $DMG_SIZE / 1024 / 1024" | bc)
print_info "파일: $DMG_NAME ($DMG_SIZE_MB MB)"

if [ "$HAS_NOTARIZATION" = true ]; then
    print_info "DMG 서명 중..."
    codesign --force --verify --verbose \
        --sign "$DEVELOPER_ID_APPLICATION" "$DMG_FILE"

    print_info "DMG 공증 요청 중..."
    xcrun notarytool submit "$DMG_FILE" \
        --key "$API_KEY_PATH" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        --wait

    xcrun stapler staple "$DMG_FILE"
    xcrun stapler validate "$DMG_FILE"

    print_success "DMG 서명 + 공증 + 스탬프 완료"
fi

# ========================================
# Step 8: 체크섬 + Sparkle EdDSA 서명
# ========================================

print_header "Step 8: 체크섬 + Sparkle 서명"

CHECKSUM=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')
print_info "SHA256: $CHECKSUM"

if [ "$HAS_SPARKLE_KEY" = true ]; then
    # Sparkle sign_update 도구 찾기
    SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData \
        -name "sign_update" -path "*/Sparkle/*" -type f 2>/dev/null | head -1)

    if [ -z "$SIGN_UPDATE" ]; then
        print_error "Sparkle sign_update를 찾을 수 없습니다."
        print_info "Xcode에서 프로젝트를 빌드한 후 다시 시도하세요."
        exit 1
    fi

    print_info "sign_update: $SIGN_UPDATE"

    echo "$SPARKLE_PRIVATE_KEY" > "$BUILD_DIR/sparkle_key.txt"
    SIGNATURE_OUTPUT=$("$SIGN_UPDATE" "$ZIP_FILE" -f "$BUILD_DIR/sparkle_key.txt")
    ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | \
        grep -o 'sparkle:edSignature="[^"]*"' | \
        sed 's/sparkle:edSignature="\(.*\)"/\1/')
    rm "$BUILD_DIR/sparkle_key.txt"

    if [ -z "$ED_SIGNATURE" ]; then
        print_error "EdDSA 서명 추출 실패"
        print_info "Raw output: $SIGNATURE_OUTPUT"
        exit 1
    fi

    print_success "EdDSA 서명: ${ED_SIGNATURE:0:40}..."
else
    ED_SIGNATURE=""
    print_warning "SPARKLE_PRIVATE_KEY가 없어 서명 건너뜀"
fi

# ========================================
# Step 9: Oracle Cloud 업로드
# ========================================

print_header "Step 9: Oracle Cloud 업로드"

ZIP_PUBLIC_URL="${STORAGE_BASE_URL}/${RELEASE_DIR}/${ZIP_NAME}"
DMG_PUBLIC_URL="${STORAGE_BASE_URL}/${RELEASE_DIR}/${DMG_NAME}"

print_info "ZIP 업로드 중..."
./scripts/oci_s3.sh s3 cp "$ZIP_FILE" \
    "s3://${STORAGE_BUCKET}/${RELEASE_DIR}/${ZIP_NAME}" \
    --content-type "application/zip"
print_success "ZIP 업로드 완료"

print_info "DMG 업로드 중..."
./scripts/oci_s3.sh s3 cp "$DMG_FILE" \
    "s3://${STORAGE_BUCKET}/${RELEASE_DIR}/${DMG_NAME}" \
    --content-type "application/x-apple-diskimage"
print_success "DMG 업로드 완료"

# ========================================
# Step 10: appcast.xml 업데이트
# ========================================

print_header "Step 10: appcast.xml 업데이트"

python3 scripts/update_appcast.py \
    --version "$VERSION" \
    --url "$ZIP_PUBLIC_URL" \
    --size "$ZIP_SIZE" \
    --checksum "$CHECKSUM" \
    --signature "$ED_SIGNATURE"

print_success "appcast.xml 업데이트 완료"

# ========================================
# Step 11: 업로드 검증
# ========================================

print_header "Step 11: 업로드 검증"

print_info "ZIP 파일 접근성 확인 중..."
ZIP_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ZIP_PUBLIC_URL")
if [ "$ZIP_HTTP_CODE" = "200" ]; then
    print_success "ZIP 다운로드 가능: HTTP $ZIP_HTTP_CODE"
else
    print_error "ZIP 접근 실패: HTTP $ZIP_HTTP_CODE"
fi

print_info "DMG 파일 접근성 확인 중..."
DMG_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$DMG_PUBLIC_URL")
if [ "$DMG_HTTP_CODE" = "200" ]; then
    print_success "DMG 다운로드 가능: HTTP $DMG_HTTP_CODE"
else
    print_error "DMG 접근 실패: HTTP $DMG_HTTP_CODE"
fi

APPCAST_URL="${STORAGE_BASE_URL}/appcast.xml"
print_info "appcast.xml 확인 중..."
APPCAST_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APPCAST_URL")
if [ "$APPCAST_HTTP_CODE" = "200" ]; then
    print_success "appcast.xml 접근 가능: HTTP $APPCAST_HTTP_CODE"
else
    print_error "appcast.xml 접근 실패: HTTP $APPCAST_HTTP_CODE"
fi

# ========================================
# 완료 요약
# ========================================

print_header "🎉 배포 완료!"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                    배포 정보 요약${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📦 버전:${NC}         $VERSION"
if [ "$HAS_NOTARIZATION" = true ]; then
    echo -e "${BLUE}🔐 코드 서명:${NC}    ✅ 완료 (Developer ID)"
    echo -e "${BLUE}📮 공증:${NC}         ✅ 완료 (Apple Notarization)"
else
    echo -e "${YELLOW}🔐 코드 서명:${NC}    ⚠️ 건너뜀"
    echo -e "${YELLOW}📮 공증:${NC}         ⚠️ 건너뜀"
fi
echo ""
echo -e "${BLUE}📦 ZIP:${NC} $ZIP_SIZE_MB MB | SHA256: ${CHECKSUM:0:16}..."
echo -e "   URL: $ZIP_PUBLIC_URL"
echo ""
echo -e "${BLUE}💿 DMG:${NC} $DMG_SIZE_MB MB"
echo -e "   URL: $DMG_PUBLIC_URL"
echo ""
echo -e "${BLUE}📡 Appcast:${NC} $APPCAST_URL"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 로컬 빌드 파일 정리 여부
echo -e "${YELLOW}로컬 빌드 파일 삭제하시겠습니까? (y/N):${NC} "
read -r CLEANUP_RESPONSE

if [[ "$CLEANUP_RESPONSE" =~ ^[Yy]$ ]]; then
    rm -rf "$BUILD_DIR"
    print_success "빌드 디렉토리 삭제 완료: $BUILD_DIR"
else
    print_info "빌드 파일 유지: $BUILD_DIR"
fi

# 임시 API Key 파일 정리
if [ -n "${API_KEY_PATH:-}" ] && [ -f "$API_KEY_PATH" ]; then
    rm -f "$API_KEY_PATH"
fi

print_success "모든 작업이 완료되었습니다! 🚀"
