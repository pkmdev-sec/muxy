#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Muxy (Dev)"
APP_BUNDLE="/Applications/${APP_NAME}.app"
TRIPLE="arm64-apple-macosx14.0"

echo "==> Killing any running Muxy (Dev) instance (stable Muxy.app is left alone)"
pkill -f "/Applications/Muxy \(Dev\).app/Contents/MacOS/Muxy" 2>/dev/null || true
sleep 1

echo "==> Building release (${TRIPLE})"
cd "$PROJECT_ROOT"
swift build -c release --triple "$TRIPLE" --product Muxy

SPM_BIN="$(swift build -c release --triple "$TRIPLE" --show-bin-path)"
if [ ! -x "${SPM_BIN}/Muxy" ]; then
  echo "ERROR: build produced no Muxy binary at ${SPM_BIN}/Muxy"
  exit 1
fi

BUILD_NUMBER="$(git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Muxy/Info.plist" 2>/dev/null || echo 0.0.0)"
if [ "$SHORT_VERSION" = "VERSION_STRING" ]; then
  SHORT_VERSION="0.0.0"
fi

echo "==> Wiping ${APP_BUNDLE}"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

echo "==> Copying binary"
cp "$SPM_BIN/Muxy" "$APP_BUNDLE/Contents/MacOS/Muxy"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Muxy"
strip -Sx "$APP_BUNDLE/Contents/MacOS/Muxy"

if [ -d "$SPM_BIN/Muxy_Muxy.bundle" ]; then
  cp -R "$SPM_BIN/Muxy_Muxy.bundle" "$APP_BUNDLE/Contents/Resources/Muxy_Muxy.bundle"
fi

cp "$PROJECT_ROOT/Muxy/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}-dev" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${APP_NAME}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "$APP_BUNDLE/Contents/Info.plist"

"$SCRIPT_DIR/create-icns.sh" "$APP_BUNDLE/Contents/Resources/AppIcon.icns" >/dev/null 2>&1

SPARKLE_FW="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE_FW" ]; then
  echo "ERROR: Sparkle.framework not found at $SPARKLE_FW — run 'swift package resolve' first"
  exit 1
fi
cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | grep -v "replacing existing signature" || true

echo "==> Installed: $APP_BUNDLE"
echo "    version:    ${SHORT_VERSION}-dev  (build ${BUILD_NUMBER})"
echo "    binary:     $(stat -f%z "$APP_BUNDLE/Contents/MacOS/Muxy") bytes"
echo "    note:       ad-hoc signed; first Finder double-click shows 'unverified developer' — right-click + Open once, or use --launch"

if [ "${1:-}" = "--launch" ] || [ "${1:-}" = "-l" ]; then
  echo "==> Launching"
  open -a "$APP_BUNDLE"
fi
