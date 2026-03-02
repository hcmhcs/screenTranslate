#!/bin/bash
# ========================================
# Oracle Cloud Object Storage AWS CLI Wrapper
# ========================================
# Purpose: Wrapper for AWS CLI to work with Oracle Cloud Object Storage
# Usage: ./scripts/oci_s3.sh s3 cp file.txt s3://bucket/path
#
# AWS CLI 2.23.5+ 체크섬 호환성 이슈 해결을 위한 래퍼.
# 환경변수 AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY는 .env.local에서 로드.

set -e

# Oracle Cloud S3 호환성 환경변수 설정
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

# Oracle Cloud 엔드포인트 설정
OCI_ENDPOINT="${STORAGE_ENDPOINT:-https://axo5sh9pv2lg.compat.objectstorage.ap-chuncheon-1.oraclecloud.com}"
OCI_REGION="${STORAGE_REGION:-ap-chuncheon-1}"

# AWS CLI 명령어 실행
aws --endpoint-url "$OCI_ENDPOINT" \
    --region "$OCI_REGION" \
    "$@"
