#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Catel"
EXECUTABLE_NAME="Catel"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
BUILD_DIR="$ROOT_DIR/.build"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon-source.png"
ICON_ICNS="$ROOT_DIR/Resources/AppIcon.icns"

rm -rf "$APP_BUNDLE" "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$BUILD_DIR"

swiftc \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -framework SwiftUI \
    -framework AppKit \
    -framework Combine \
    "$ROOT_DIR"/Sources/*.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

cp "$ROOT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ -f "$ICON_SOURCE" ]]; then
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for entry in \
        "icon_16x16.png:16" \
        "icon_16x16@2x.png:32" \
        "icon_32x32.png:32" \
        "icon_32x32@2x.png:64" \
        "icon_128x128.png:128" \
        "icon_128x128@2x.png:256" \
        "icon_256x256.png:256" \
        "icon_256x256@2x.png:512" \
        "icon_512x512.png:512" \
        "icon_512x512@2x.png:1024"
    do
        name="${entry%%:*}"
        size="${entry##*:}"
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/$name" >/dev/null
    done
    if ! iconutil -c icns "$ICONSET" -o "$ICON_ICNS"; then
        printf 'Warning: iconutil failed — using existing AppIcon.icns if present\n' >&2
    fi
fi

if [[ -f "$ICON_ICNS" ]]; then
    cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    printf 'Icon: %s\n' "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    printf 'Warning: AppIcon.icns missing — Finder will show a generic icon\n' >&2
fi

printf 'Built %s\n' "$APP_BUNDLE"
