#!/usr/bin/env bash
set -euo pipefail

APP_NAME="HoldKey"
BUNDLE="${APP_NAME}.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
DIST_DIR="dist"
DMG_ROOT="${DIST_DIR}/dmg-root"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

./build.sh

echo "🧹 Preparing DMG staging folder..."
rm -rf "${DIST_DIR}"
mkdir -p "${DMG_ROOT}"

cp -R "${BUNDLE}" "${DMG_ROOT}/${BUNDLE}"
ln -s /Applications "${DMG_ROOT}/Applications"

cat > "${DMG_ROOT}/INSTALL.txt" <<EOF
Install HoldKey
===============

1. Drag HoldKey.app into the Applications folder.
2. Open HoldKey from Applications.
3. If macOS blocks the first launch, right-click HoldKey.app and choose Open.
4. Enable HoldKey in:
   System Settings -> Privacy & Security -> Accessibility

HoldKey is a tiny menu bar app for locking Premiere Pro keyframe drags to a
horizontal line.
EOF

echo "💿 Creating ${DMG_PATH}..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_ROOT}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${DMG_ROOT}"

echo ""
echo "✅ Installer image ready:"
echo "   ${DMG_PATH}"
