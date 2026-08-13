#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/private/tmp/xike-release-${UID}/Xike.xcarchive}"
ZIP_PATH="$ROOT_DIR/dist/Xike.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
TEAM_ID="${TEAM_ID:-}"

usage() {
  echo "usage: DEVELOPER_ID_APPLICATION='Developer ID Application: Name (TEAMID)' TEAM_ID=TEAMID NOTARY_PROFILE=xike-notary $0 [archive|preflight|notarize|validate]" >&2
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "缺少环境变量：$name" >&2
    usage
    exit 2
  fi
}

MODE="${1:-archive}"
case "$MODE" in
  archive)
    require_value DEVELOPER_ID_APPLICATION "$DEVELOPER_ID_APPLICATION"
    require_value TEAM_ID "$TEAM_ID"
    /bin/mkdir -p "$ROOT_DIR/dist" "$(dirname "$ARCHIVE_PATH")"
    COPYFILE_DISABLE=1 DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcodebuild \
      -project "$ROOT_DIR/Xike.xcodeproj" \
      -scheme Xike \
      -configuration Release \
      -archivePath "$ARCHIVE_PATH" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
      archive
    "$0" preflight
    ;;
  preflight)
    APP="$ARCHIVE_PATH/Products/Applications/Xike.app"
    if [[ ! -d "$APP" ]]; then echo "未找到归档 App：$APP" >&2; exit 1; fi
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
    /usr/bin/codesign -d --entitlements :- "$APP"
    ;;
  notarize)
    require_value NOTARY_PROFILE "$NOTARY_PROFILE"
    "$0" preflight
    /bin/rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --keepParent "$ARCHIVE_PATH/Products/Applications/Xike.app" "$ZIP_PATH"
    DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun stapler staple "$ARCHIVE_PATH/Products/Applications/Xike.app"
    "$0" validate
    /bin/rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --keepParent "$ARCHIVE_PATH/Products/Applications/Xike.app" "$ZIP_PATH"
    echo "已生成包含公证票据的发布包：$ZIP_PATH"
    ;;
  validate)
    APP="$ARCHIVE_PATH/Products/Applications/Xike.app"
    if [[ ! -d "$APP" ]]; then echo "未找到归档 App：$APP" >&2; exit 1; fi
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
    /usr/bin/codesign -d --entitlements :- "$APP"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$APP"
    DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun stapler validate "$APP"
    ;;
  *) usage; exit 2 ;;
esac
