#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BashTwoWindows"
BUNDLE_ID="local.example.BashTwoWindows"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/Sources/BashTwoWindows/main.swift"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
EXECUTABLE="$BUILD_DIR/$APP_NAME"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

usage() {
  cat <<EOF_USAGE
Usage:
  ./build.sh          Build dist/$APP_NAME.app
  ./build.sh run      Build and open dist/$APP_NAME.app
  ./build.sh clean    Remove build and dist directories

Optional:
  MACOSX_DEPLOYMENT_TARGET=14.0 ./build.sh

Default deployment target: 13.0
EOF_USAGE
}

clean() {
  rm -rf "$BUILD_DIR" "$DIST_DIR"
}

build() {
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "Error: xcrun was not found. Install Xcode or the Xcode Command Line Tools." >&2
    exit 1
  fi

  if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Error: swiftc was not found. Check your Xcode or Command Line Tools installation." >&2
    exit 1
  fi

  if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "Error: source file not found: $SOURCE_FILE" >&2
    exit 1
  fi

  rm -rf "$BUILD_DIR" "$DIST_DIR"
  mkdir -p "$BUILD_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

  xcrun swiftc "$SOURCE_FILE" \
    -swift-version 5 \
    -sdk "$SDK_PATH" \
    -target "${ARCH}-apple-macosx${DEPLOYMENT_TARGET}" \
    -o "$EXECUTABLE" \
    -framework Cocoa

  cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"

  # Copy app icon if present
  ICON_SRC="$SCRIPT_DIR/Resources/AppIcon.icns"
  if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
  fi

  cat > "$APP_DIR/Contents/Info.plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <key>CFBundleShortVersionString</key>
    <string>1.0</string>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>LSMinimumSystemVersion</key>
    <string>$DEPLOYMENT_TARGET</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF_PLIST

  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
  fi

  echo "Built: $APP_DIR"
}

case "${1:-build}" in
  build)
    build
    ;;
  run)
    build
    open "$APP_DIR"
    ;;
  clean)
    clean
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
