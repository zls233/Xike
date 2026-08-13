#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Xike"
DISPLAY_NAME="息刻"
BUNDLE_ID="com.zhanglishan.Xike"
MIN_SYSTEM_VERSION="26.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SWIFTPM_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
XCODE_DERIVED_DATA="${XCODE_DERIVED_DATA:-/private/tmp/xike-derived-data-${UID}}"
TELEMETRY_SUBSYSTEM="$BUNDLE_ID"
SWIFTPM_CACHE_DIR="$ROOT_DIR/.build/swiftpm-cache"
SWIFTPM_MODULE_CACHE_DIR="$ROOT_DIR/.build/swiftpm-module-cache"

usage() {
  echo "usage: $0 [run|--package|--debug|--logs|--telemetry|--verify]" >&2
}

case "$MODE" in
  run|--package|package|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    usage
    exit 2
    ;;
esac

BUILD_CONFIGURATION="Debug"
SWIFTPM_CONFIGURATION="debug"
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  BUILD_CONFIGURATION="Release"
  SWIFTPM_CONFIGURATION="release"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

resolve_full_xcode() {
  local active_developer_dir=""
  active_developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"

  if [[ "$active_developer_dir" == *.app/Contents/Developer ]] && \
     [[ -x "$active_developer_dir/usr/bin/xcodebuild" ]]; then
    printf '%s\n' "$active_developer_dir"
    return 0
  fi

  if [[ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" ]]; then
    printf '%s\n' "/Applications/Xcode.app/Contents/Developer"
    return 0
  fi

  if [[ -x "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild" ]]; then
    printf '%s\n' "/Applications/Xcode-beta.app/Contents/Developer"
    return 0
  fi

  return 1
}

build_with_xcode() {
  local developer_dir="$1"
  echo "使用完整 Xcode 构建 ${APP_NAME}…"
  if [[ -d "$XCODE_DERIVED_DATA" ]]; then
    /usr/bin/xattr -cr "$XCODE_DERIVED_DATA"
  fi
  COPYFILE_DISABLE=1 DEVELOPER_DIR="$developer_dir" /usr/bin/xcodebuild \
    -project "$ROOT_DIR/Xike.xcodeproj" \
    -scheme Xike \
    -configuration "$BUILD_CONFIGURATION" \
    -derivedDataPath "$XCODE_DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    build

  APP_BUNDLE="$XCODE_DERIVED_DATA/Build/Products/$BUILD_CONFIGURATION/$APP_NAME.app"
  APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
}

build_with_swiftpm() {
  echo "未检测到完整 Xcode；使用 SwiftPM 构建并暂存 app bundle…"
  local swiftpm_environment_args=()
  if [[ "${CODEX_SANDBOX:-}" == "seatbelt" ]]; then
    # SwiftPM's nested sandbox and swiftbuild PIF parser are unavailable inside
    # the Codex seatbelt. The native backend stays inside the outer sandbox.
    swiftpm_environment_args+=(--disable-sandbox --build-system native)
  fi
  /bin/mkdir -p "$SWIFTPM_CACHE_DIR" "$SWIFTPM_MODULE_CACHE_DIR"
  export CLANG_MODULE_CACHE_PATH="$SWIFTPM_MODULE_CACHE_DIR"
  export SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_MODULE_CACHE_DIR"
  if ! swift build \
      "${swiftpm_environment_args[@]}" \
      --package-path "$ROOT_DIR" \
      --cache-path "$SWIFTPM_CACHE_DIR" \
      --configuration "$SWIFTPM_CONFIGURATION" \
      --product "$APP_NAME"; then
    echo "SwiftPM 构建失败。若日志提到 CoreAudioTypes 或 SwiftUICore，请安装并切换到包含完整 macOS SDK 的 Xcode。" >&2
    return 1
  fi

  local bin_dir
  local build_binary
  local app_contents
  local app_macos
  local app_resources
  local info_plist
  bin_dir="$(swift build \
    "${swiftpm_environment_args[@]}" \
    --package-path "$ROOT_DIR" \
    --cache-path "$SWIFTPM_CACHE_DIR" \
    --configuration "$SWIFTPM_CONFIGURATION" \
    --show-bin-path)"
  build_binary="$bin_dir/$APP_NAME"
  app_contents="$SWIFTPM_APP_BUNDLE/Contents"
  app_macos="$app_contents/MacOS"
  app_resources="$app_contents/Resources"
  info_plist="$app_contents/Info.plist"

  /bin/rm -rf "$SWIFTPM_APP_BUNDLE"
  /bin/mkdir -p "$app_macos" "$app_resources"
  /bin/cp "$build_binary" "$app_macos/$APP_NAME"
  /bin/chmod +x "$app_macos/$APP_NAME"

  if [[ -d "$ROOT_DIR/Resources" ]]; then
    /usr/bin/ditto "$ROOT_DIR/Resources" "$app_resources"
    /bin/rm -f "$app_resources/Info.plist"
  fi

  /bin/cat >"$info_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  /usr/bin/plutil -lint "$info_plist" >/dev/null
  /usr/bin/codesign --force --sign - \
    --entitlements "$ROOT_DIR/Xike.entitlements" \
    "$SWIFTPM_APP_BUNDLE"

  APP_BUNDLE="$SWIFTPM_APP_BUNDLE"
  APP_BINARY="$app_macos/$APP_NAME"
}

package_for_personal_use() {
  /bin/rm -rf "$SWIFTPM_APP_BUNDLE"
  /bin/mkdir -p "$DIST_DIR"
  /usr/bin/ditto "$APP_BUNDLE" "$SWIFTPM_APP_BUNDLE"
  /usr/bin/codesign --force --deep --sign - \
    --entitlements "$ROOT_DIR/Xike.entitlements" \
    "$SWIFTPM_APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$SWIFTPM_APP_BUNDLE"
  echo "已生成可本机使用的 App：$SWIFTPM_APP_BUNDLE"
}

XCODE_DEVELOPER_DIR=""
if XCODE_DEVELOPER_DIR="$(resolve_full_xcode)"; then
  build_with_xcode "$XCODE_DEVELOPER_DIR"
else
  build_with_swiftpm
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_process() {
  local attempt
  for attempt in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "${DISPLAY_NAME} 已启动（进程：${APP_NAME}）。"
      return 0
    fi
    /bin/sleep 0.25
  done

  echo "$DISPLAY_NAME 未能在 5 秒内启动。" >&2
  return 1
}

case "$MODE" in
  run)
    open_app
    ;;
  --package|package)
    package_for_personal_use
    ;;
  --debug|debug)
    open_app
    verify_process
    exec /usr/bin/lldb -p "$(pgrep -x "$APP_NAME" | head -1)"
    ;;
  --logs|logs)
    open_app
    verify_process
    exec /usr/bin/log stream --info --style compact \
      --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    verify_process
    exec /usr/bin/log stream --info --style compact \
      --predicate "subsystem == \"$TELEMETRY_SUBSYSTEM\""
    ;;
  --verify|verify)
    open_app
    verify_process
    ;;
esac
