#!/usr/bin/env python3
"""
Update Sparkle appcast.xml on Oracle Cloud Object Storage.

Downloads existing appcast.xml, adds a new release item, and re-uploads.
Release notes are converted from Markdown to HTML and wrapped in CDATA.

Usage:
  python scripts/update_appcast.py \
    --version 1.0.0 \
    --url "https://.../.../ScreenTranslate-1.0.0.zip" \
    --size 12345678 \
    --checksum "sha256hash" \
    --signature "edSignature" \
    --description "### Added\n- New feature" \
    --release-url "https://github.com/.../releases/tag/v1.0.0"
"""

import argparse
import html
import os
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

import boto3

APP_NAME = "ScreenTranslate"

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
    try:
        response = s3.get_object(Bucket=bucket, Key="appcast.xml")
        return response["Body"].read().decode("utf-8")
    except s3.exceptions.NoSuchKey:
        return None
    except Exception:
        return None


def create_empty_appcast() -> str:
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


CDATA_PLACEHOLDER = "__CDATA_PLACEHOLDER__"


def changelog_to_html(markdown: str, release_url: str = "") -> str:
    """CHANGELOG.md에서 추출한 Markdown을 Sparkle용 간단한 HTML로 변환한다."""
    lines = markdown.strip().split("\n")
    html_parts: list[str] = []
    in_list = False

    for line in lines:
        stripped = line.strip()
        if not stripped:
            if in_list:
                html_parts.append("</ul>")
                in_list = False
            continue

        if stripped.startswith("### "):
            if in_list:
                html_parts.append("</ul>")
                in_list = False
            heading = html.escape(stripped[4:])
            html_parts.append(f"<h3>{heading}</h3>")
        elif stripped.startswith("- "):
            if not in_list:
                html_parts.append("<ul>")
                in_list = True
            item_text = html.escape(stripped[2:])
            html_parts.append(f"  <li>{item_text}</li>")
        else:
            if in_list:
                html_parts.append("</ul>")
                in_list = False
            html_parts.append(f"<p>{html.escape(stripped)}</p>")

    if in_list:
        html_parts.append("</ul>")

    if release_url:
        html_parts.append(
            f'<p><a href="{html.escape(release_url)}">Full release notes on GitHub →</a></p>'
        )

    return "\n".join(html_parts)


def add_item(
    xml_str: str,
    version: str,
    url: str,
    size: int,
    checksum: str,
    signature: str,
    description: str = "",
    release_url: str = "",
) -> str:
    root = ET.fromstring(xml_str)
    channel = root.find("channel")

    # Remove duplicate version if exists
    for item in channel.findall("item"):
        enclosure = item.find("enclosure")
        if enclosure is not None:
            existing_ver = enclosure.get(f"{{{SPARKLE_NS}}}version", "")
            if existing_ver == version:
                channel.remove(item)

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

    # HTML 릴리즈 노트 (CDATA) — 직렬화 후 치환
    html_content = None
    if description:
        html_content = changelog_to_html(description, release_url)
        desc = ET.SubElement(item, "description")
        desc.text = CDATA_PLACEHOLDER
    elif release_url:
        # description 없이 release_url만 있으면 링크만 표시
        html_content = changelog_to_html("", release_url)
        desc = ET.SubElement(item, "description")
        desc.text = CDATA_PLACEHOLDER

    # GitHub 전체 릴리즈 노트 링크 (Sparkle "Full Release Notes" 버튼)
    if release_url:
        full_notes = ET.SubElement(item, f"{{{SPARKLE_NS}}}fullReleaseNotesLink")
        full_notes.text = release_url

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", url)
    enclosure.set("length", str(size))
    enclosure.set("type", "application/octet-stream")
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", signature)
    enclosure.set(f"{{{SPARKLE_NS}}}version", version)
    enclosure.set(f"{{{SPARKLE_NS}}}shortVersionString", version)

    ET.indent(root, space="  ")
    xml_declaration = '<?xml version="1.0" encoding="utf-8"?>\n'
    result = xml_declaration + ET.tostring(root, encoding="unicode")

    # CDATA 치환 — ET는 CDATA를 지원하지 않으므로 직렬화 후 수동 교체
    if html_content:
        result = result.replace(
            f"<description>{CDATA_PLACEHOLDER}</description>",
            f"<description><![CDATA[\n{html_content}\n]]></description>",
        )

    return result


def upload_appcast(s3, bucket: str, xml_str: str):
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
    parser.add_argument("--description", default="", help="Release notes (Markdown)")
    parser.add_argument("--release-url", default="", help="GitHub release URL")
    args = parser.parse_args()

    bucket = os.environ["STORAGE_BUCKET"]
    s3 = get_s3_client()

    xml_str = download_appcast(s3, bucket)
    if xml_str is None:
        print("No existing appcast.xml found, creating new one.")
        xml_str = create_empty_appcast()
    else:
        print("Downloaded existing appcast.xml")

    xml_str = add_item(
        xml_str,
        version=args.version,
        url=args.url,
        size=args.size,
        checksum=args.checksum,
        signature=args.signature,
        description=args.description,
        release_url=args.release_url,
    )

    upload_appcast(s3, bucket, xml_str)
    print(f"Updated appcast.xml with version {args.version}")


if __name__ == "__main__":
    main()
