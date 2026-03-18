#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

RELEASE_VERSION="$1"
SCHEME="${SCHEME:-Navi macOS}"
CONFIGURATION="${CONFIGURATION:-Release}"
NOTARY_PROFILE="${NOTARY_PROFILE:-release}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-ed25519}"
BUILD_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/Navi.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PATH="$BUILD_DIR/ExportOptions.plist"
ZIP_PATH="$BUILD_DIR/Navi.zip"
APPCAST_PATH="$ROOT_DIR/appcast.xml"
HAS_NOTARY_PROFILE=0

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

for command_name in bun gh jj python3 xcodebuild xcrun ditto; do
    require_command "$command_name"
done

if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    exit 1
fi

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    HAS_NOTARY_PROFILE=1
elif [[ -z "$NOTARY_APPLE_ID" && -t 0 ]]; then
    printf 'Apple ID for notarization: ' >&2
    read -r NOTARY_APPLE_ID
fi

if [[ "$HAS_NOTARY_PROFILE" -eq 0 && -z "$NOTARY_APPLE_ID" ]]; then
    echo "Notarization credentials are not configured." >&2
    echo "Either store a notary profile with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" ..." >&2
    echo "or set NOTARY_APPLE_ID and run this from an interactive terminal to enter the app-specific password." >&2
    exit 1
fi

if ! jj diff --quiet; then
    echo "Working copy must be clean before releasing." >&2
    echo "Commit, squash, or abandon existing changes first." >&2
    exit 1
fi

sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${RELEASE_VERSION};/g" Navi.xcodeproj/project.pbxproj
sed -i '' "s/\"version\": \".*\"/\"version\": \"${RELEASE_VERSION}\"/" ExtensionSource/manifest.json

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Navi.xcodeproj/project.pbxproj | head -1 | tr -d ' ')
TEAM_ID=$(sed -n 's/.*DEVELOPMENT_TEAM = \(.*\);/\1/p' Navi.xcodeproj/project.pbxproj | head -1 | tr -d ' ')
BUILD_NUMBER=$(jj log -r '::@' --count | tr -d '[:space:]')
TAG="v${VERSION}"
DOWNLOAD_URL="https://github.com/finnvoor/Navi/releases/download/${TAG}/Navi.zip"

if [[ -z "$VERSION" || -z "$TEAM_ID" || -z "$BUILD_NUMBER" || "$VERSION" != "$RELEASE_VERSION" ]]; then
    echo "Failed to determine version metadata from the project." >&2
    exit 1
fi

echo "Releasing ${VERSION} (${BUILD_NUMBER})"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$ZIP_PATH"

bun install --frozen-lockfile
xcodebuild -resolvePackageDependencies -project Navi.xcodeproj -scheme "$SCHEME"

cat > "$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

xcodebuild archive \
    -project Navi.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates

APP_PATH=$(find "$EXPORT_PATH" -maxdepth 1 -name "*.app" -print -quit)
if [[ -z "$APP_PATH" ]]; then
    echo "Exported app not found." >&2
    exit 1
fi

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ "$HAS_NOTARY_PROFILE" -eq 1 ]]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$NOTARY_APPLE_ID" \
        --team-id "$TEAM_ID" \
        --wait
fi
xcrun stapler staple "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

find_sign_update() {
    find "$HOME/Library/Developer/Xcode/DerivedData" \( \
        -path "*/Sparkle/bin/sign_update" -o \
        -path "*/Sparkle/sign_update" -o \
        -path "*/SourcePackages/artifacts/*/Sparkle/bin/sign_update" \
    \) -type f 2>/dev/null | head -1
}

SIGN_UPDATE=$(find_sign_update)

if [[ -z "$SIGN_UPDATE" ]]; then
    echo "Sparkle sign_update tool not found in Xcode DerivedData artifacts." >&2
    echo "Resolve packages in Xcode once so Sparkle's bundled CLI tools are downloaded." >&2
    exit 1
fi

SPARKLE_OUTPUT=$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$ZIP_PATH")
ED_SIGNATURE=$(printf '%s\n' "$SPARKLE_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_LENGTH=$(stat -f%z "$ZIP_PATH")

if [[ -z "$ED_SIGNATURE" ]]; then
    echo "Failed to extract Sparkle edSignature." >&2
    echo "$SPARKLE_OUTPUT" >&2
    exit 1
fi

PUB_DATE=$(LC_ALL=C date -R)
export VERSION BUILD_NUMBER ED_SIGNATURE FILE_LENGTH DOWNLOAD_URL PUB_DATE APPCAST_PATH
python3 <<'PY'
import os
import re
from pathlib import Path

appcast_path = Path(os.environ["APPCAST_PATH"])
version = os.environ["VERSION"]
build_number = os.environ["BUILD_NUMBER"]
ed_signature = os.environ["ED_SIGNATURE"]
file_length = os.environ["FILE_LENGTH"]
download_url = os.environ["DOWNLOAD_URL"]
pub_date = os.environ["PUB_DATE"]

content = appcast_path.read_text()
pattern = re.compile(
    r'\n\s*<item>\s*'
    r'<title>Version ' + re.escape(version) + r'</title>[\s\S]*?'
    r'</item>',
    re.MULTILINE,
)
content = re.sub(pattern, "", content)

item = f"""    <item>
      <title>Version {version}</title>
      <pubDate>{pub_date}</pubDate>
      <enclosure
        url="{download_url}"
        sparkle:version="{build_number}"
        sparkle:shortVersionString="{version}"
        sparkle:edSignature="{ed_signature}"
        length="{file_length}"
        type="application/octet-stream"
      />
    </item>
"""

if "  </channel>" not in content:
    raise SystemExit("appcast.xml is missing </channel>")

content = content.replace("  </channel>", item + "  </channel>")
appcast_path.write_text(content)
PY

if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP_PATH" --clobber
else
    gh release create "$TAG" \
        --title "Navi ${TAG}" \
        --generate-notes \
        "$ZIP_PATH"
fi

jj describe -m "Release ${TAG}"
jj new

echo "Release complete: ${TAG}"
echo "Committed release metadata locally. Push the release commit and appcast update when ready."
