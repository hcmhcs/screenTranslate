#!/usr/bin/env python3
"""
Sparkle appcast.xml 갱신 스크립트.

Oracle Cloud Object Storage에서 기존 appcast.xml을 다운로드하고,
새 릴리즈 항목을 추가한 뒤 다시 업로드한다.

사용법:
  python scripts/update_appcast.py \
    --version 1.0.0 \
    --url "https://.../.../ScreenTranslate-1.0.0.zip" \
    --size 12345678 \
    --checksum "sha256hash" \
    --signature "edSignature"
"""

import argparse
import os
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

import boto3

APP_NAME = "ScreenTranslate"

# Sparkle XML 네임스페이스
SPARKLE_NS = "http://www.andymatuschak.net/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)


def get_s3_client():
    return boto3.client(
        "s3",
        region_name=os.environ["STORAGE_REGION"],
        endpoint_url=os.environ["STORAGE_ENDPOINT"],
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    )


def download_appcast(s3, bucket: str) -> str | None:
    """기존 appcast.xml 다운로드. 없으면 None 반환."""
    try:
        response = s3.get_object(Bucket=bucket, Key="appcast.xml")
        return response["Body"].read().decode("utf-8")
    except s3.exceptions.NoSuchKey:
        return None
    except Exception:
        return None


def create_empty_appcast() -> str:
    """빈 appcast.xml 생성."""
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="{SPARKLE_NS}"
     xmlns:dc="{DC_NS}">
  <channel>
    <title>{APP_NAME}</title>
    <link>{os.environ.get("STORAGE_BASE_URL", "")}</link>
    <description>{APP_NAME} updates</description>
    <language>en</language>
  </channel>
</rss>"""


def add_item(
    xml_str: str,
    version: str,
    url: str,
    size: int,
    checksum: str,
    signature: str,
) -> str:
    """appcast.xml에 새 릴리즈 항목 추가."""
    root = ET.fromstring(xml_str)
    channel = root.find("channel")

    # 중복 버전 체크 — 이미 존재하면 제거 후 재추가
    for item in channel.findall("item"):
        enclosure = item.find("enclosure")
        if enclosure is not None:
            existing_ver = enclosure.get(f"{{{SPARKLE_NS}}}version", "")
            if existing_ver == version:
                channel.remove(item)

    # 새 item 생성
    item = ET.SubElement(channel, "item")

    title = ET.SubElement(item, "title")
    title.text = f"{APP_NAME} v{version}"

    pub_date = ET.SubElement(item, "pubDate")
    pub_date.text = datetime.now(timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )

    sparkle_version = ET.SubElement(item, f"{{{SPARKLE_NS}}}version")
    sparkle_version.text = version

    short_version = ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString")
    short_version.text = version

    min_os = ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion")
    min_os.text = "15.0"

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", url)
    enclosure.set("length", str(size))
    enclosure.set("type", "application/octet-stream")
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", signature)
    enclosure.set(f"{{{SPARKLE_NS}}}version", version)
    enclosure.set(f"{{{SPARKLE_NS}}}shortVersionString", version)

    # XML 문자열로 변환
    ET.indent(root, space="  ")
    xml_declaration = '<?xml version="1.0" encoding="utf-8"?>\n'
    return xml_declaration + ET.tostring(root, encoding="unicode")


def upload_appcast(s3, bucket: str, xml_str: str):
    """appcast.xml을 Oracle Cloud에 업로드."""
    s3.put_object(
        Bucket=bucket,
        Key="appcast.xml",
        Body=xml_str.encode("utf-8"),
        ContentType="application/xml",
    )


def main():
    parser = argparse.ArgumentParser(description="Update Sparkle appcast.xml")
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--size", required=True, type=int)
    parser.add_argument("--checksum", required=True)
    parser.add_argument("--signature", required=True)
    args = parser.parse_args()

    bucket = os.environ["STORAGE_BUCKET"]
    s3 = get_s3_client()

    # 기존 appcast 다운로드 또는 새로 생성
    xml_str = download_appcast(s3, bucket)
    if xml_str is None:
        print("No existing appcast.xml found, creating new one.")
        xml_str = create_empty_appcast()
    else:
        print("Downloaded existing appcast.xml")

    # 새 항목 추가
    xml_str = add_item(
        xml_str,
        version=args.version,
        url=args.url,
        size=args.size,
        checksum=args.checksum,
        signature=args.signature,
    )

    # 업로드
    upload_appcast(s3, bucket, xml_str)
    print(f"Updated appcast.xml with version {args.version}")


if __name__ == "__main__":
    main()
