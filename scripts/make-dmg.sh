#!/bin/bash
# Builds AeroWall (Release) and packages it into a drag-to-Applications DMG.
# Usage: scripts/make-dmg.sh            → dist/AeroWall-<version>.dmg and dist/AeroWall.dmg
# Optional env: VERSION=1.2.0 BUILD_NUMBER=42 override the version from project.yml (used by CI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
VENV="$BUILD/dmg-venv"
cd "$ROOT"

if command -v xcodegen >/dev/null; then
    xcodegen generate --quiet
fi

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" AeroWall/Info.plist
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" AeroWall/Info.plist
fi

echo "▸ Building AeroWall (Release)…"
xcodebuild -project AeroWall.xcodeproj -scheme AeroWall -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$BUILD/DerivedData" build -quiet
APP="$BUILD/DerivedData/Build/Products/Release/AeroWall.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

if [ ! -x "$VENV/bin/dmgbuild" ]; then
    echo "▸ Installing dmgbuild…"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild Pillow
fi

echo "▸ Drawing installer background…"
"$VENV/bin/python" scripts/dmg/generate_background.py
BACKGROUND="$BUILD/dmg-background.tiff"
tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png -out "$BACKGROUND" 2>/dev/null

mkdir -p "$DIST"
DMG="$DIST/AeroWall-$VERSION.dmg"
rm -f "$DMG"
echo "▸ Creating ${DMG}…"
"$VENV/bin/dmgbuild" -s scripts/dmg/settings.py -D app="$APP" -D background="$BACKGROUND" "AeroWall" "$DMG"

# Stable name so releases/latest/download/AeroWall.dmg always works.
cp "$DMG" "$DIST/AeroWall.dmg"

echo "✓ ${DMG}"
