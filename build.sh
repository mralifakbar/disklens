#!/bin/bash
# Builds build/DiskLens.app.
#
#   ./build.sh               native architecture
#   ./build.sh --universal   arm64 + x86_64, what releases ship
#   ./build.sh --zip         also write build/DiskLens-<version>.zip
#   ./build.sh --install     also copy the app to /Applications
#
# The version comes from $VERSION, else the latest git tag, else 0.1.0.
set -euo pipefail
cd "$(dirname "$0")"

UNIVERSAL=0 ZIP=0 INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --zip) ZIP=1 ;;
        --install) INSTALL=1 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

ARGS=(-c release)
if [ "$UNIVERSAL" = 1 ]; then ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/DiskLens"

APP=build/DiskLens.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DiskLens"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run locally, not notarized.
codesign --force --sign - "$APP"
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/DiskLens"), $(du -sh "$APP" | cut -f1))"

if [ "$ZIP" = 1 ]; then
    rm -f "build/DiskLens-$VERSION.zip"
    ditto -c -k --keepParent "$APP" "build/DiskLens-$VERSION.zip"
    echo "Packed build/DiskLens-$VERSION.zip"
fi

if [ "$INSTALL" = 1 ]; then
    rm -rf /Applications/DiskLens.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/DiskLens.app"
fi
